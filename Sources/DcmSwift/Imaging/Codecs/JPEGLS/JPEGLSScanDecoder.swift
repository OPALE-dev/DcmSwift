import Foundation

/// Reads JPEG-LS entropy-coded data, where a bit 0 is stuffed after every
/// FFH byte (T.87 9.1), so the byte that follows carries seven data bits.
/// Bytes are taken one at a time, so after any read fewer than eight
/// buffered bits remain and all of them belong to the last byte taken.
struct JPEGLSBitReader {
    private let bytes: [UInt8]
    private(set) var position: Int
    private let end: Int
    private var cache: UInt64 = 0
    private var count = 0
    private var previousWasFF = false
    /// Zero bits supplied past the end of the data.
    private var padding = 0

    init(_ bytes: [UInt8], range: Range<Int>) {
        self.bytes = bytes
        position = range.lowerBound
        end = range.upperBound
    }

    private mutating func fill(_ needed: Int) throws {
        while count < needed {
            if position < end, !(bytes[position] == 0xFF && position + 1 < end && bytes[position + 1] >= 0x80) {
                let byte = bytes[position]
                position += 1
                if previousWasFF {
                    cache |= UInt64(byte & 0x7F) << (57 - count)
                    count += 7
                } else {
                    cache |= UInt64(byte) << (56 - count)
                    count += 8
                }
                previousWasFF = byte == 0xFF
            } else {
                // A marker or the end: valid streams never consume these.
                padding += 8
                guard padding <= 64 else { throw DICOMCodecError.corruptedData("JPEG-LS scan data is truncated") }
                count += 8
            }
        }
    }

    mutating func read(_ bits: Int) throws -> Int {
        guard bits > 0 else { return 0 }
        try fill(bits)
        let value = Int(cache >> UInt64(64 - bits))
        cache <<= UInt64(bits)
        count -= bits
        return value
    }

    mutating func readBit() throws -> Int { try read(1) }

    /// Counts zero bits up to the next one bit, which is consumed.
    mutating func readUnary(maximum: Int) throws -> Int {
        var zeros = 0
        while true {
            if count == 0 { try fill(1) }
            let leading = min(cache.leadingZeroBitCount, count)
            if leading < count {
                cache <<= UInt64(leading + 1)
                count -= leading + 1
                zeros += leading
                guard zeros <= maximum else { break }
                return zeros
            }
            zeros += count
            cache = 0
            count = 0
            guard zeros <= maximum else { break }
        }
        throw DICOMCodecError.corruptedData("JPEG-LS Golomb code is too long")
    }

    /// Discards the bits left in the current byte and reads RSTm.
    mutating func restart(expecting index: Int) throws {
        cache = 0
        count = 0
        // The encoder pads with a stuffed byte after a final FFH.
        if previousWasFF, position < end, bytes[position] < 0x80 { position += 1 }
        previousWasFF = false
        while position + 1 < bytes.count, bytes[position] == 0xFF, bytes[position + 1] == 0xFF { position += 1 }
        guard position + 1 < bytes.count, bytes[position] == 0xFF,
              bytes[position + 1] == 0xD0 + UInt8(index % 8) else {
            throw DICOMCodecError.corruptedData("JPEG-LS restart marker \(index % 8) is missing")
        }
        position += 2
    }
}

/// The context modeling state of one scan (T.87 A.2, A.7), shared by its
/// components.
struct JPEGLSContextModel {
    static let runOrder: [Int] = [0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
                                  4, 4, 5, 5, 6, 6, 7, 7, 8, 9, 10, 11, 12, 13, 14, 15]

    let near: Int
    let maximum: Int
    let range: Int
    let quantizedBits: Int
    let limit: Int
    let reset: Int
    let t1: Int, t2: Int, t3: Int
    let step: Int

    var a = [Int](repeating: 0, count: 365)
    var b = [Int](repeating: 0, count: 365)
    var c = [Int](repeating: 0, count: 365)
    var n = [Int](repeating: 1, count: 365)
    /// Run interruption contexts 365 (RItype 0) and 366 (RItype 1).
    var runA = [0, 0]
    var runN = [1, 1]
    var runNn = [0, 0]
    var runIndex: [Int]

    init(_ parameters: JPEGLSStream.CodingParameters, runSlots: Int) {
        near = parameters.near
        maximum = parameters.maximumValue
        range = (maximum + 2 * near) / (2 * near + 1) + 1
        var bits = 0
        while (1 << bits) < range { bits += 1 }
        quantizedBits = bits
        var bpp = 0
        while (1 << bpp) < maximum + 1 { bpp += 1 }
        bpp = max(2, bpp)
        limit = 2 * (bpp + max(8, bpp))
        reset = parameters.reset
        t1 = parameters.threshold1
        t2 = parameters.threshold2
        t3 = parameters.threshold3
        step = 2 * near + 1
        runIndex = [Int](repeating: 0, count: runSlots)
        resetState()
    }

    /// Initial state, also restored at each restart marker (A.2.1).
    mutating func resetState() {
        let initialA = max(2, (range + 32) / 64)
        for i in 0..<365 {
            a[i] = initialA
            b[i] = 0
            c[i] = 0
            n[i] = 1
        }
        runA = [initialA, initialA]
        runN = [1, 1]
        runNn = [0, 0]
        for i in runIndex.indices { runIndex[i] = 0 }
    }

    @inline(__always) func quantize(_ d: Int) -> Int {
        if d <= -t3 { return -4 }
        if d <= -t2 { return -3 }
        if d <= -t1 { return -2 }
        if d < -near { return -1 }
        if d <= near { return 0 }
        if d < t1 { return 1 }
        if d < t2 { return 2 }
        if d < t3 { return 3 }
        return 4
    }

    @inline(__always) func context(_ ra: Int, _ rb: Int, _ rc: Int, _ rd: Int) -> Int {
        (quantize(rd - rb) * 9 + quantize(rb - rc)) * 9 + quantize(rc - ra)
    }

    /// The median edge detector (A.4.1).
    @inline(__always) static func predict(_ ra: Int, _ rb: Int, _ rc: Int) -> Int {
        if rc >= max(ra, rb) { return min(ra, rb) }
        if rc <= min(ra, rb) { return max(ra, rb) }
        return ra + rb - rc
    }

    @inline(__always) func clamp(_ value: Int) -> Int { value < 0 ? 0 : (value > maximum ? maximum : value) }

    /// Reconstruction modulo RANGE and range limiting (A.4.4).
    @inline(__always) func reconstruct(_ value: Int) -> Int {
        var value = value
        if value < -near {
            value += range * step
        } else if value > maximum + near {
            value -= range * step
        }
        return clamp(value)
    }

    func golombParameter(_ q: Int) throws -> Int {
        var k = 0
        while n[q] << k < a[q] {
            k += 1
            guard k < 32 else { throw DICOMCodecError.corruptedData("JPEG-LS context overflows") }
        }
        return k
    }

    func runGolombParameter(_ type: Int) throws -> Int {
        let temp = runA[type] + (runN[type] >> 1) * type
        var k = 0
        while runN[type] << k < temp {
            k += 1
            guard k < 32 else { throw DICOMCodecError.corruptedData("JPEG-LS run context overflows") }
        }
        return k
    }

    /// Updates A, B, C, N after a regular-mode sample (A.6).
    mutating func update(_ q: Int, error: Int) throws {
        a[q] += abs(error)
        b[q] += error * step
        guard a[q] < 1 << 24, abs(b[q]) < 1 << 24 else {
            throw DICOMCodecError.corruptedData("JPEG-LS context overflows")
        }
        if n[q] == reset {
            a[q] >>= 1
            b[q] >>= 1
            n[q] >>= 1
        }
        n[q] += 1
        if b[q] + n[q] <= 0 {
            b[q] += n[q]
            if b[q] <= -n[q] { b[q] = -n[q] + 1 }
            if c[q] > -128 { c[q] -= 1 }
        } else if b[q] > 0 {
            b[q] -= n[q]
            if b[q] > 0 { b[q] = 0 }
            if c[q] < 127 { c[q] += 1 }
        }
    }

    /// Updates the run interruption context (A.7.2.2).
    mutating func updateRun(_ type: Int, error: Int, mapped: Int) {
        if error < 0 { runNn[type] += 1 }
        runA[type] += (mapped + 1 - type) >> 1
        if runN[type] == reset {
            runA[type] >>= 1
            runN[type] >>= 1
            runNn[type] >>= 1
        }
        runN[type] += 1
    }
}

/// Two lines (previous and current) of `width + 2` pixels with `samples` interleaved samples.
final class JPEGLSLineBuffer {
    let width: Int
    let samples: Int
    let storage: UnsafeMutablePointer<Int>
    var previous: UnsafeMutablePointer<Int>
    var current: UnsafeMutablePointer<Int>

    init(width: Int, samples: Int) {
        self.width = width
        self.samples = samples
        let length = (width + 2) * samples
        storage = .allocate(capacity: 2 * length)
        storage.initialize(repeating: 0, count: 2 * length)
        previous = storage
        current = storage + length
    }

    deinit { storage.deallocate() }

    func clear() { storage.update(repeating: 0, count: 2 * (width + 2) * samples) }

    func swap() { (previous, current) = (current, previous) }
}

/// Decodes the scans of a JPEG-LS stream into one plane per component.
struct JPEGLSScanDecoder {
    let stream: JPEGLSStream

    /// Reconstructed samples per frame component, row by row at the
    /// component's own dimensions.
    func decode() throws -> [[UInt16]] {
        let frame = stream.frame
        var planes = (0..<frame.components.count).map { index -> [UInt16] in
            let (width, height) = frame.size(of: index)
            return [UInt16](repeating: 0, count: width * height)
        }
        for scan in stream.scans {
            try decode(scan, into: &planes)
        }
        return planes
    }

    private func decode(_ scan: JPEGLSStream.Scan, into planes: inout [[UInt16]]) throws {
        let frame = stream.frame
        var reader = JPEGLSBitReader(stream.bytes, range: scan.data)
        let sampleInterleaved = scan.interleave == .sample
        var model = JPEGLSContextModel(scan.parameters, runSlots: sampleInterleaved ? 1 : scan.components.count)
        let sizes = scan.components.map { frame.size(of: $0) }
        guard sizes.allSatisfy({ $0.width * $0.height <= 1 << 28 }) else {
            throw DICOMCodecError.corruptedData("JPEG-LS dimensions are invalid")
        }

        let buffers = sampleInterleaved
            ? [JPEGLSLineBuffer(width: sizes[0].width, samples: scan.components.count)]
            : sizes.map { JPEGLSLineBuffer(width: $0.width, samples: 1) }
        let qs = UnsafeMutablePointer<Int>.allocate(capacity: 4)
        defer { qs.deallocate() }

        // Units are lines, or line groups when components are line
        // interleaved (each contributes its vertical sampling factor).
        let verticals = scan.components.map { frame.components[$0].verticalSampling }
        let units: Int
        if scan.interleave == .line {
            units = zip(sizes, verticals).map { ($0.height + $1 - 1) / $1 }.max()!
        } else {
            units = sizes[0].height
        }
        var restartIndex = 0

        for unit in 0..<units {
            if scan.restartInterval > 0, unit > 0, unit % scan.restartInterval == 0 {
                try reader.restart(expecting: restartIndex)
                restartIndex += 1
                model.resetState()
                buffers.forEach { $0.clear() }
            }
            switch scan.interleave {
            case .none:
                try decodeLine(buffers[0], slot: 0, model: &model, reader: &reader, qs: qs)
                store(buffers[0], row: unit, into: &planes, components: scan.components)
            case .sample:
                try decodeLine(buffers[0], slot: 0, model: &model, reader: &reader, qs: qs)
                store(buffers[0], row: unit, into: &planes, components: scan.components)
            case .line:
                for (slot, component) in scan.components.enumerated() {
                    for line in 0..<verticals[slot] {
                        let row = unit * verticals[slot] + line
                        guard row < sizes[slot].height else { break }
                        try decodeLine(buffers[slot], slot: slot, model: &model, reader: &reader, qs: qs)
                        store(buffers[slot], row: row, into: &planes, components: [component])
                    }
                }
            }
        }
    }

    private func store(_ buffer: JPEGLSLineBuffer, row: Int, into planes: inout [[UInt16]], components: [Int]) {
        let width = buffer.width, samples = buffer.samples
        for (offset, component) in components.enumerated() {
            planes[component].withUnsafeMutableBufferPointer { plane in
                let base = row * width
                for x in 0..<width {
                    plane[base + x] = UInt16(truncatingIfNeeded: buffer.current[(x + 1) * samples + offset])
                }
            }
        }
    }

    /// Decodes one line (A.3 to A.7); `slot` selects the run index.
    private func decodeLine(
        _ buffer: JPEGLSLineBuffer, slot: Int, model: inout JPEGLSContextModel, reader: inout JPEGLSBitReader,
        qs: UnsafeMutablePointer<Int>
    ) throws {
        buffer.swap()
        let prev = buffer.previous, cur = buffer.current
        let width = buffer.width, samples = buffer.samples
        // Edge samples (A.2.1): Rd past the end repeats Rb, and Ra at the
        // start is Rb; Rc at the start is the previous line's Ra.
        for s in 0..<samples {
            prev[(width + 1) * samples + s] = prev[width * samples + s]
            cur[s] = prev[samples + s]
        }

        var x = 1
        while x <= width {
            var run = true
            for s in 0..<samples {
                let ra = cur[(x - 1) * samples + s], rb = prev[x * samples + s]
                let rc = prev[(x - 1) * samples + s], rd = prev[(x + 1) * samples + s]
                qs[s] = model.context(ra, rb, rc, rd)
                if qs[s] != 0 { run = false }
            }
            if run {
                x += try decodeRun(buffer, at: x, slot: slot, model: &model, reader: &reader)
                continue
            }
            for s in 0..<samples {
                let ra = cur[(x - 1) * samples + s], rb = prev[x * samples + s]
                let rc = prev[(x - 1) * samples + s]
                cur[x * samples + s] = try decodeRegular(
                    qs[s], predicted: JPEGLSContextModel.predict(ra, rb, rc), model: &model, reader: &reader)
            }
            x += 1
        }
    }

    private func decodeMapped(_ k: Int, limit: Int, model: JPEGLSContextModel, reader: inout JPEGLSBitReader) throws -> Int {
        let q = try reader.readUnary(maximum: limit - model.quantizedBits - 1)
        if q < limit - model.quantizedBits - 1 {
            return (q << k) + (try reader.read(k))
        }
        return try reader.read(model.quantizedBits) + 1
    }

    /// Regular mode (A.4 to A.6).
    private func decodeRegular(
        _ context: Int, predicted: Int, model: inout JPEGLSContextModel, reader: inout JPEGLSBitReader
    ) throws -> Int {
        let sign = context < 0 ? -1 : 1
        let q = context * sign
        let corrected = model.clamp(predicted + sign * model.c[q])
        let k = try model.golombParameter(q)
        let mapped = try decodeMapped(k, limit: model.limit, model: model, reader: &reader)
        var error = mapped & 1 == 0 ? mapped >> 1 : -((mapped + 1) >> 1)
        guard abs(error) <= 65535 else { throw DICOMCodecError.corruptedData("JPEG-LS prediction error overflows") }
        if k == 0, model.near == 0, 2 * model.b[q] + model.n[q] - 1 < 0 {
            error = -error - 1
        }
        try model.update(q, error: error)
        return model.reconstruct(corrected + sign * error * model.step)
    }

    /// Run mode (A.7): the run length, then the interruption sample.
    private func decodeRun(
        _ buffer: JPEGLSLineBuffer, at start: Int, slot: Int, model: inout JPEGLSContextModel, reader: inout JPEGLSBitReader
    ) throws -> Int {
        let prev = buffer.previous, cur = buffer.current
        let width = buffer.width, samples = buffer.samples
        let remaining = width - start + 1
        var length = 0
        while try reader.readBit() == 1 {
            let span = 1 << JPEGLSContextModel.runOrder[model.runIndex[slot]]
            let count = min(span, remaining - length)
            length += count
            if count == span { model.runIndex[slot] = min(31, model.runIndex[slot] + 1) }
            if length == remaining { break }
        }
        if length != remaining {
            let bits = JPEGLSContextModel.runOrder[model.runIndex[slot]]
            length += try reader.read(bits)
        }
        guard length <= remaining else { throw DICOMCodecError.corruptedData("JPEG-LS run overflows the line") }
        for i in 0..<(length * samples) {
            cur[start * samples + i] = cur[(start - 1) * samples + i % samples]
        }
        let end = start + length
        if end > width { return length }

        // Run interruption sample (A.7.2).
        for s in 0..<samples {
            let ra = cur[(start - 1) * samples + s], rb = prev[end * samples + s]
            let type = samples == 1 && abs(ra - rb) <= model.near ? 1 : 0
            let k = try model.runGolombParameter(type)
            let limit = model.limit - JPEGLSContextModel.runOrder[model.runIndex[slot]] - 1
            let mapped = try decodeMapped(k, limit: limit, model: model, reader: &reader)
            let temp = mapped + type
            let map = temp & 1 == 1
            let magnitude = (temp + (map ? 1 : 0)) / 2
            let error = ((k != 0 || 2 * model.runNn[type] >= model.runN[type]) == map) ? -magnitude : magnitude
            model.updateRun(type, error: error, mapped: mapped)
            cur[end * samples + s] = type == 1
                ? model.reconstruct(ra + error * model.step)
                : model.reconstruct(rb + error * (rb >= ra ? 1 : -1) * model.step)
        }
        model.runIndex[slot] = max(0, model.runIndex[slot] - 1)
        return length + 1
    }
}
