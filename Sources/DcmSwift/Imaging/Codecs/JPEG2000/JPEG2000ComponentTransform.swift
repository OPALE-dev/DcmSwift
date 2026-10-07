import Foundation

/// The inverse multiple component transformation of one tile (ISO/IEC
/// 15444-2 Annex J): the stages listed by MCO, each made of the component
/// collections of an MCC segment, transformed by array-based (decorrelation
/// or dependency) or wavelet-based inverse transforms.
struct JPEG2000ComponentTransform {
    enum Operation {
        /// J.3.1.1.1: W = T C + o, T is M x N.
        case decorrelation(coefficients: [Double])
        /// J.3.1.1.3: N + 1 single element reversible steps, T is (N + 1) x N.
        case reversibleDecorrelation(coefficients: [Double])
        /// J.3.1.2.1: strictly lower triangular T, stored row by row.
        case dependency(coefficients: [Double])
        /// J.3.1.2.3: lower triangular T with power-of-two diagonal scales.
        case reversibleDependency(coefficients: [Double])
        /// J.3.2: one-dimensional inverse DWT across the collection.
        case wavelet(levels: Int, reversible: Bool, origin: Int)
    }

    struct Collection {
        let inputs: [Int]
        let outputs: [Int]
        let operation: Operation
        let offsets: [Double]
    }

    struct Stage {
        let collections: [Collection]
        /// Number of intermediate components this stage produces.
        let outputCount: Int
    }

    let inputCount: Int
    let stages: [Stage]

    /// Builds the transform a tile applies from its resolved segments, or
    /// nil when the tile has no stage (Nmco = 0, J.2.1).
    static func make(
        tile: JPEG2000Codestream.TransformSegments?, main: JPEG2000Codestream.TransformSegments,
        codestreamComponents: Int, outputComponents: Int
    ) throws -> JPEG2000ComponentTransform? {
        func fail(_ reason: String) -> DICOMCodecError { .corruptedData("JPEG 2000 Part 2: \(reason)") }
        guard let order = tile?.stageOrder ?? main.stageOrder, !order.isEmpty else { return nil }

        func array(_ key: Int) -> [Double]? { tile?.arrays[key] ?? main.arrays[key] }

        // Collections of every stage, with the count of input components each
        // stage reads (Equation J-1).
        var parsed: [[(kind: Int, inputs: [Int], outputs: [Int], t: Int, origin: Int)]] = []
        for index in order {
            guard let segment = tile?.collections[index] ?? main.collections[index] else {
                throw fail("MCO refers to the missing MCC segment \(index)")
            }
            var reader = Reader(bytes: segment.records)
            var collections: [(Int, [Int], [Int], Int, Int)] = []
            for _ in 0..<segment.count {
                let kind = try reader.byte() & 0x03
                guard kind != 2 else { throw fail("reserved MCC transform type") }
                let n = try reader.u16()
                let inputs = try (0..<(n & 0x7FFF)).map { _ in try n & 0x8000 != 0 ? reader.u16() : reader.byte() }
                let m = try reader.u16()
                let outputs = try (0..<(m & 0x7FFF)).map { _ in try m & 0x8000 != 0 ? reader.u16() : reader.byte() }
                let t = try reader.u24()
                let origin = kind == 3 ? try reader.u32() : 0
                guard !inputs.isEmpty, !outputs.isEmpty else { throw fail("empty component collection") }
                collections.append((kind, inputs, outputs, t, origin))
            }
            guard reader.isAtEnd else { throw fail("MCC segment \(index) has trailing data") }
            parsed.append(collections)
        }

        var stages: [Stage] = []
        var available = codestreamComponents
        for (k, collections) in parsed.enumerated() {
            let outputCount = k + 1 < parsed.count
                ? 1 + (parsed[k + 1].flatMap(\.inputs).max() ?? 0)
                : outputComponents
            var written = Set<Int>()
            var built: [Collection] = []
            for (kind, inputs, outputs, t, origin) in collections {
                guard inputs.allSatisfy({ $0 < available }) else {
                    throw fail("stage \(k) reads a component beyond its \(available) inputs")
                }
                guard outputs.allSatisfy({ $0 < outputCount && written.insert($0).inserted }) else {
                    throw fail("stage \(k) writes a component twice or beyond its \(outputCount) outputs")
                }
                let n = inputs.count, m = outputs.count
                let reversible = t & 0x10000 != 0
                var offsets = [Double](repeating: 0, count: m)
                let offsetIndex = (t >> 8) & 0xFF
                if offsetIndex != 0 {
                    guard let values = array(2 << 8 | offsetIndex), values.count == m else {
                        throw fail("offset array \(offsetIndex) is missing or does not hold \(m) values")
                    }
                    offsets = values
                }

                let operation: Operation
                if kind == 3 {
                    let kernel = t & 0xFF
                    guard kernel <= 1 else {
                        throw fail("arbitrary transformation kernels are not allowed in DICOM (PS3.5 A.4.4)")
                    }
                    let levels = (t >> 16) & 0x3F
                    guard n == m, levels <= 32 else {
                        throw fail("a wavelet collection has \(n) inputs, \(m) outputs, and \(levels) levels")
                    }
                    operation = .wavelet(levels: levels, reversible: kernel == 1, origin: origin)
                } else {
                    let arrayIndex = t & 0xFF
                    let coefficients = arrayIndex == 0 ? nil : array(kind << 8 | arrayIndex)
                    if arrayIndex != 0, coefficients == nil {
                        throw fail("transform array \(arrayIndex) is missing")
                    }
                    func checked(_ count: Int) throws -> [Double]? {
                        guard let coefficients else { return nil }
                        guard coefficients.count == count else {
                            throw fail("transform array \(arrayIndex) holds \(coefficients.count) values, \(count) expected")
                        }
                        return coefficients
                    }
                    switch (kind, reversible) {
                    case (1, false):
                        let identity = (0..<(m * n)).map { $0 / n == $0 % n ? 1.0 : 0.0 }
                        operation = .decorrelation(coefficients: try checked(m * n) ?? identity)
                    case (1, true):
                        guard n == m else { throw fail("a reversible decorrelation has \(n) inputs and \(m) outputs") }
                        // Null array: unit scales and no other term (J.3.1.1.3).
                        let identity = (0..<((n + 1) * n)).map { index -> Double in
                            let row = index / n, column = index % n
                            return (row == n && column == n - 1) || (row < n && column == n - 1 - row) ? 1 : 0
                        }
                        let coefficients = try checked((n + 1) * n) ?? identity
                        // The scale of each step must be a power of two (J.3.1.1.3).
                        guard (0...n).allSatisfy({ coefficients[$0 * n + ($0 < n ? n - 1 - $0 : n - 1)] != 0 }) else {
                            throw fail("reversible decorrelation array \(arrayIndex) has a zero scale")
                        }
                        operation = .reversibleDecorrelation(coefficients: coefficients)
                    case (_, false):
                        guard n == m else { throw fail("a dependency transform has \(n) inputs and \(m) outputs") }
                        operation = .dependency(
                            coefficients: try checked(m * (m - 1) / 2) ?? [Double](repeating: 0, count: m * (m - 1) / 2))
                    case (_, true):
                        guard n == m else { throw fail("a dependency transform has \(n) inputs and \(m) outputs") }
                        let identity = (1..<max(m, 1)).flatMap { row in
                            [Double](repeating: 0, count: row) + [1]
                        }
                        let coefficients = try checked(m * (m + 1) / 2 - 1) ?? identity
                        // Diagonal scales must be powers of two (J.3.1.2.3).
                        guard (1..<max(m, 1)).allSatisfy({ coefficients[($0 - 1) * ($0 + 2) / 2 + $0] != 0 }) else {
                            throw fail("reversible dependency array \(arrayIndex) has a zero scale")
                        }
                        operation = .reversibleDependency(coefficients: coefficients)
                    }
                }
                built.append(Collection(inputs: inputs, outputs: outputs, operation: operation, offsets: offsets))
            }
            stages.append(Stage(collections: built, outputCount: outputCount))
            available = outputCount
        }
        return JPEG2000ComponentTransform(inputCount: codestreamComponents, stages: stages)
    }

    /// Applies the inverse transform to the codestream component samples at
    /// one location; returns the reconstructed image component samples.
    final class Evaluator {
        let transform: JPEG2000ComponentTransform
        private(set) var input: [Double]
        private var buffers: [[Double]]
        private var gathered: [Double] = []
        private var result: [Double] = []
        private var wavelet = WaveletBuffers()

        init(_ transform: JPEG2000ComponentTransform) {
            self.transform = transform
            input = [Double](repeating: 0, count: transform.inputCount)
            buffers = transform.stages.map { [Double](repeating: 0, count: $0.outputCount) }
        }

        func setInput(_ index: Int, _ value: Double) {
            input[index] = value
        }

        /// The reconstructed image components after `run()`.
        var output: [Double] { buffers[buffers.count - 1] }

        func run() {
            for (k, stage) in transform.stages.enumerated() {
                let source = k == 0 ? input : buffers[k - 1]
                // Components no collection writes are null components (J.2.3.1).
                for index in buffers[k].indices { buffers[k][index] = 0 }
                for collection in stage.collections {
                    gathered.removeAll(keepingCapacity: true)
                    for index in collection.inputs { gathered.append(source[index]) }
                    apply(collection)
                    for (position, index) in collection.outputs.enumerated() {
                        buffers[k][index] = result[position]
                    }
                }
            }
        }

        private func apply(_ collection: Collection) {
            let c = gathered
            let o = collection.offsets
            let m = collection.outputs.count, n = c.count
            result.removeAll(keepingCapacity: true)
            switch collection.operation {
            case .decorrelation(let t):
                for row in 0..<m {
                    var sum = o[row]
                    for column in 0..<n { sum += t[row * n + column] * c[column] }
                    result.append(sum)
                }
            case .reversibleDecorrelation(let t):
                // Equations J-4 to J-6.
                result.append(contentsOf: c)
                for step in 0...n {
                    let target = step < n ? n - 1 - step : n - 1
                    let scale = t[step * n + target]
                    let magnitude = abs(scale)
                    var sum = (magnitude / 2).rounded(.down)
                    for column in 0..<n where column != target { sum += t[step * n + column] * result[column] }
                    let adjusted = result[target] - (sum / magnitude).rounded(.down)
                    result[target] = step < n ? adjusted : (scale < 0 ? -adjusted : adjusted)
                }
                for row in 0..<n { result[row] += o[row] }
            case .dependency(let t):
                // Equations J-11 and J-12.
                for row in 0..<m {
                    var value = c[row] + o[row]
                    let start = row * (row - 1) / 2
                    for column in 0..<row { value += t[start + column] * result[column] }
                    result.append(value)
                }
            case .reversibleDependency(let t):
                // Equations J-14 and J-15.
                for row in 0..<m {
                    let y = c[row] + o[row]
                    guard row > 0 else { result.append(y); continue }
                    let start = (row - 1) * (row + 2) / 2
                    let scale = t[start + row]
                    var sum = (scale / 2).rounded(.down)
                    for column in 0..<row { sum += t[start + column] * result[column] }
                    result.append((sum / scale).rounded(.down) + y)
                }
            case .wavelet(let levels, let reversible, let origin):
                wavelet.inverse(c, levels: levels, reversible: reversible, origin: origin, into: &result)
                for row in 0..<m { result[row] += o[row] }
            }
        }
    }
}

/// The one-dimensional inverse DWT of a component collection (J.3.2.1),
/// following ISO/IEC 15444-1 Annex F on the interval [origin, origin + M).
struct WaveletBuffers {
    private var low: [Double] = []
    private var signal: [Double] = []
    private var extended: [Double] = []

    private static func ceilDiv(_ a: Int, _ b: Int) -> Int {
        a >= 0 ? (a + b - 1) / b : -((-a) / b)
    }

    mutating func inverse(_ c: [Double], levels: Int, reversible: Bool, origin: Int, into result: inout [Double]) {
        let x0 = origin, x1 = origin + c.count
        // Band extents (Equation B-15) and the order the samples are stored:
        // NL LL, then NL HL down to 1 HL.
        func lowRange(_ level: Int) -> Range<Int> {
            Self.ceilDiv(x0, 1 << level)..<Self.ceilDiv(x1, 1 << level)
        }
        func highRange(_ level: Int) -> Range<Int> {
            let half = 1 << (level - 1)
            return Self.ceilDiv(x0 - half, 1 << level)..<Self.ceilDiv(x1 - half, 1 << level)
        }
        var position = lowRange(levels).count
        low = Array(c[0..<position])
        for level in stride(from: levels, to: 0, by: -1) {
            let lows = lowRange(level), highs = highRange(level)
            let target = lowRange(level - 1)
            signal = [Double](repeating: 0, count: target.count)
            for (offset, u) in lows.enumerated() { signal[2 * u - target.lowerBound] = low[offset] }
            for u in highs {
                signal[2 * u + 1 - target.lowerBound] = c[position]
                position += 1
            }
            reconstruct(from: target.lowerBound, reversible: reversible)
            low = signal
        }
        result.append(contentsOf: low)
    }

    /// The forward transform (J.3.2.2): the samples of NL LL, then NL HL
    /// down to 1 HL.
    mutating func forward(_ w: [Double], levels: Int, reversible: Bool, origin: Int, into result: inout [Double]) {
        var start = origin
        signal = w
        var highs: [[Double]] = []
        for _ in 0..<levels {
            analyze(from: start, reversible: reversible)
            // Even indices form the low band, odd ones the high band.
            var lows: [Double] = [], high: [Double] = []
            for (k, value) in signal.enumerated() {
                if (start + k) & 1 == 0 { lows.append(value) } else { high.append(value) }
            }
            highs.append(high)
            signal = lows
            start = Self.ceilDiv(start, 2)
        }
        result.append(contentsOf: signal)
        for high in highs.reversed() { result.append(contentsOf: high) }
    }

    /// Periodic symmetric extension of `signal` by four samples on each side
    /// (F.3.7, F.4.7); the first sample of `signal` has index i0.
    private mutating func extend() {
        let count = signal.count
        let period = 2 * (count - 1)
        extended.removeAll(keepingCapacity: true)
        for k in -Self.margin..<(count + Self.margin) {
            var m = k % period
            if m < 0 { m += period }
            extended.append(signal[min(m, period - m)])
        }
    }

    private static let margin = 4
    private static let alpha = -1.586134342059924, beta = -0.052980118572961
    private static let gamma = 0.882911075530934, delta = 0.443506852043971
    private static let k = 1.230174104914001

    /// 1D_SR (F.3.6) of `signal`, whose first sample has index i0.
    private mutating func reconstruct(from i0: Int, reversible: Bool) {
        let count = signal.count
        guard count > 1 else {
            if count == 1, i0 % 2 != 0 { signal[0] /= 2 }
            return
        }
        extend()
        // Absolute index of extended[j] is i0 - margin + j.
        let base = i0 - Self.margin
        func isEven(_ j: Int) -> Bool { (base + j) & 1 == 0 }
        let last = extended.count - 1
        if reversible {
            // Equations F-5 and F-6.
            for j in 1..<last where isEven(j) {
                extended[j] -= ((extended[j - 1] + extended[j + 1] + 2) / 4).rounded(.down)
            }
            for j in 1..<last where !isEven(j) {
                extended[j] += ((extended[j - 1] + extended[j + 1]) / 2).rounded(.down)
            }
        } else {
            // Equation F-7 and Table F.4.
            for j in 0...last { extended[j] *= isEven(j) ? Self.k : 1 / Self.k }
            for (even, factor) in [(true, Self.delta), (false, Self.gamma), (true, Self.beta), (false, Self.alpha)] {
                for j in 1..<last where isEven(j) == even {
                    extended[j] -= factor * (extended[j - 1] + extended[j + 1])
                }
            }
        }
        for k in 0..<count { signal[k] = extended[Self.margin + k] }
    }

    /// 1D_SD (F.4.6) of `signal`, whose first sample has index i0.
    private mutating func analyze(from i0: Int, reversible: Bool) {
        let count = signal.count
        guard count > 1 else {
            if count == 1, i0 % 2 != 0 { signal[0] *= 2 }
            return
        }
        extend()
        let base = i0 - Self.margin
        func isEven(_ j: Int) -> Bool { (base + j) & 1 == 0 }
        let last = extended.count - 1
        if reversible {
            // Equations F-9 and F-10.
            for j in 1..<last where !isEven(j) {
                extended[j] -= ((extended[j - 1] + extended[j + 1]) / 2).rounded(.down)
            }
            for j in 1..<last where isEven(j) {
                extended[j] += ((extended[j - 1] + extended[j + 1] + 2) / 4).rounded(.down)
            }
        } else {
            // Equation F-11.
            for (even, factor) in [(false, Self.alpha), (true, Self.beta), (false, Self.gamma), (true, Self.delta)] {
                for j in 1..<last where isEven(j) == even {
                    extended[j] += factor * (extended[j - 1] + extended[j + 1])
                }
            }
            for j in 0...last { extended[j] *= isEven(j) ? 1 / Self.k : Self.k }
        }
        for k in 0..<count { signal[k] = extended[Self.margin + k] }
    }
}

private struct Reader {
    let bytes: [UInt8]
    var position = 0

    var isAtEnd: Bool { position == bytes.count }

    mutating func byte() throws -> Int {
        guard position < bytes.count else { throw DICOMCodecError.corruptedData("JPEG 2000 Part 2: truncated MCC") }
        defer { position += 1 }
        return Int(bytes[position])
    }

    mutating func u16() throws -> Int { try byte() << 8 | byte() }
    mutating func u24() throws -> Int { try u16() << 8 | byte() }
    mutating func u32() throws -> Int { try u16() << 16 | u16() }
}
