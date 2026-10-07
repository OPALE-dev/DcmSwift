import Foundation

/// Binary arithmetic decoder from ITU-T T.81 Annex D. A statistics byte
/// stores the MPS in bit 7 and the Table D.2 state in bits 0...6.
struct JPEGArithmeticDecoder {
    private let bytes: ArraySlice<UInt8>
    private var position: ArraySlice<UInt8>.Index
    private var unreadMarker: UInt8?
    private var c: UInt32 = 0
    private var a: UInt32 = 0x10000
    private var ct = 0
    private var initialized = false

    init(_ bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
        position = bytes.startIndex
    }

    mutating func decode(_ statistics: inout [UInt8], _ index: Int) throws -> Int {
        guard statistics.indices.contains(index) else {
            throw DICOMCodecError.corruptedData("JPEG arithmetic statistics index \(index)")
        }
        if !initialized {
            try byteIn(); c &<<= 8
            try byteIn(); c &<<= 8
            initialized = true
        }
        let state = statistics[index]
        let entry = Self.table[Int(state & 0x7F)]
        let qe = entry >> 16
        let nextMPS = UInt8((entry >> 8) & 0xFF)
        let nextLPS = UInt8(entry & 0xFF)
        a -= qe
        var lps: Bool
        if c >> 16 < a {
            if a & 0x8000 != 0 { return Int(state >> 7) }
            lps = a < qe
        } else {
            lps = a >= qe
            c &-= a << 16
            a = qe
        }
        let result: Int
        if lps {
            result = Int((state >> 7) ^ 1)
            statistics[index] = (state & 0x80) ^ nextLPS
        } else {
            result = Int(state >> 7)
            statistics[index] = (state & 0x80) ^ nextMPS
        }
        repeat {
            if ct == 0 {
                try byteIn()
                ct = 8
            }
            a <<= 1
            c &<<= 1
            ct -= 1
        } while a & 0x8000 == 0
        return result
    }

    mutating func restart(expecting index: Int) throws {
        if unreadMarker == nil { try readMarker() }
        guard unreadMarker == UInt8(0xD0 + (index & 7)) else {
            throw DICOMCodecError.corruptedData("JPEG arithmetic restart marker RST\(index & 7) is missing")
        }
        unreadMarker = nil
        c = 0
        a = 0x10000
        ct = 0
        initialized = false
    }

    private mutating func nextDataByte() throws -> UInt8 {
        if unreadMarker != nil { return 0 }
        guard position < bytes.endIndex else { return 0 }
        var data = bytes[position]
        position += 1
        if data != 0xFF { return data }
        repeat {
            guard position < bytes.endIndex else { return 0 }
            data = bytes[position]
            position += 1
        } while data == 0xFF
        if data == 0 { return 0xFF }
        unreadMarker = data
        return 0
    }

    private mutating func byteIn() throws {
        c |= UInt32(try nextDataByte()) << 8
    }

    private mutating func readMarker() throws {
        while position < bytes.endIndex, bytes[position] != 0xFF { position += 1 }
        guard position < bytes.endIndex else { return }
        repeat { position += 1 } while position < bytes.endIndex && bytes[position] == 0xFF
        guard position < bytes.endIndex else { return }
        let marker = bytes[position]
        position += 1
        if marker != 0 { unreadMarker = marker }
    }

    // T.81 Table D.2, packed as Qe | next-MPS | (switch-MPS,next-LPS).
    private static let table: [UInt32] = [
        0x5a1d0181,0x2586020e,0x11140310,0x080b0412,0x03d80514,0x01da0617,0x00e50719,0x006f081c,
        0x0036091e,0x001a0a21,0x000d0b23,0x00060c09,0x00030d0a,0x00010d0c,0x5a7f0f8f,0x3f251024,
        0x2cf21126,0x207c1227,0x17b91328,0x1182142a,0x0cef152b,0x09a1162d,0x072f172e,0x055c1830,
        0x04061931,0x03031a33,0x02401b34,0x01b11c36,0x01441d38,0x00f51e39,0x00b71f3b,0x008a203c,
        0x0068213e,0x004e223f,0x003b2320,0x002c0921,0x5ae125a5,0x484c2640,0x3a0d2741,0x2ef12843,
        0x261f2944,0x1f332a45,0x19a82b46,0x15182c48,0x11772d49,0x0e742e4a,0x0bfb2f4b,0x09f8304d,
        0x0861314e,0x0706324f,0x05cd3330,0x04de3432,0x040f3532,0x03633633,0x02d43734,0x025c3835,
        0x01f83936,0x01a43a37,0x01603b38,0x01253c39,0x00f63d3a,0x00cb3e3b,0x00ab3f3d,0x008f203d,
        0x5b1241c1,0x4d044250,0x412c4351,0x37d84452,0x2fe84553,0x293c4654,0x23794756,0x1edf4857,
        0x1aa94957,0x174e4a48,0x14244b48,0x119c4c4a,0x0f6b4d4a,0x0d514e4b,0x0bb64f4d,0x0a40304d,
        0x583251d0,0x4d1c5258,0x438e5359,0x3bdd545a,0x34ee555b,0x2eae565c,0x299a575d,0x25164756,
        0x557059d8,0x4ca95a5f,0x44d95b60,0x3e225c61,0x38245d63,0x32b45e63,0x2e17565d,0x56a860df,
        0x4f466165,0x47e56266,0x41cf6367,0x3c3d6468,0x375e5d63,0x52316669,0x4c0f676a,0x4639686b,
        0x415e6367,0x56276ae9,0x50e76b6c,0x4b85676d,0x55976d6e,0x504f6b6f,0x5a106fee,0x55226d70,
        0x59eb6ff0,0x5a1d7171,
    ]
}

extension JPEGDCTDecoder {
    /// Decodes one SOF9/SOF10 scan per T.81 Annexes D, F, and G.
    mutating func decodeArithmetic(_ scan: JPEGStream.Scan, progressive: Bool) throws {
        if progressive {
            let dc = scan.spectralStart == 0 && scan.spectralEnd == 0
            let ac = scan.spectralStart > 0 && scan.spectralStart <= scan.spectralEnd
                && scan.spectralEnd <= 63 && scan.components.count == 1
            guard dc || ac, scan.approximationHigh == 0 || scan.approximationHigh == scan.approximationLow + 1,
                  scan.approximationLow <= 13 else {
                throw DICOMCodecError.corruptedData("JPEG arithmetic progressive scan parameters are invalid")
            }
        } else {
            guard scan.spectralStart == 0, scan.spectralEnd == 63,
                  scan.approximationHigh == 0, scan.approximationLow == 0 else {
                throw DICOMCodecError.corruptedData("JPEG arithmetic sequential scan parameters are invalid")
            }
        }

        var coder = JPEGArithmeticDecoder(scan.entropyCodedData)
        var dcStatistics = [[UInt8]](repeating: [UInt8](repeating: 0, count: 64), count: 4)
        var acStatistics = [[UInt8]](repeating: [UInt8](repeating: 0, count: 256), count: 4)
        // State 113 is the non-adaptive probability estimate 0.5.
        var fixed: [UInt8] = [113]
        var predictions = [Int](repeating: 0, count: scan.components.count)
        var dcContexts = [Int](repeating: 0, count: scan.components.count)
        var untilRestart = scan.restartInterval
        var restartIndex = 0

        func resetForRestart() {
            for (scanIndex, component) in scan.components.enumerated() {
                if !progressive || (scan.spectralStart == 0 && scan.approximationHigh == 0) {
                    dcStatistics[component.dcTable] = [UInt8](repeating: 0, count: 64)
                    predictions[scanIndex] = 0
                    dcContexts[scanIndex] = 0
                }
                if !progressive || scan.spectralStart > 0 {
                    acStatistics[component.acTable] = [UInt8](repeating: 0, count: 256)
                }
            }
        }

        func restartIfNeeded() throws {
            guard scan.restartInterval > 0 else { return }
            if untilRestart == 0 {
                try coder.restart(expecting: restartIndex)
                restartIndex += 1
                untilRestart = scan.restartInterval
                resetForRestart()
            }
            untilRestart -= 1
        }

        func decodeDC(_ scanIndex: Int) throws -> Int {
            let component = scan.components[scanIndex]
            let table = component.dcTable
            var statistics = dcStatistics[table]
            var state = dcContexts[scanIndex]
            if try coder.decode(&statistics, state) == 0 {
                dcContexts[scanIndex] = 0
            } else {
                let sign = try coder.decode(&statistics, state + 1)
                state += 2 + sign
                var magnitude = try coder.decode(&statistics, state)
                if magnitude != 0 {
                    state = 20
                    while try coder.decode(&statistics, state) != 0 {
                        magnitude <<= 1
                        guard magnitude != 0x8000 else {
                            throw DICOMCodecError.corruptedData("JPEG arithmetic DC magnitude overflows")
                        }
                        state += 1
                    }
                }
                let conditioning = scan.arithmeticDCTables[table] ?? (0, 1)
                if magnitude < ((1 << conditioning.lower) >> 1) {
                    dcContexts[scanIndex] = 0
                } else if magnitude > ((1 << conditioning.upper) >> 1) {
                    dcContexts[scanIndex] = 12 + sign * 4
                } else {
                    dcContexts[scanIndex] = 4 + sign * 4
                }
                var value = magnitude
                state += 14
                var bit = magnitude >> 1
                while bit != 0 {
                    if try coder.decode(&statistics, state) != 0 { value |= bit }
                    bit >>= 1
                }
                value += 1
                if sign != 0 { value = -value }
                // Differential frames do not predict the DC (T.81 J.2.2).
                if differential {
                    dcStatistics[table] = statistics
                    return value & 0xFFFF
                }
                predictions[scanIndex] = (predictions[scanIndex] + value) & 0xFFFF
            }
            dcStatistics[table] = statistics
            return predictions[scanIndex]
        }

        func decodeAC(_ scanIndex: Int, component: Int, base: Int, start: Int, end: Int, low: Int) throws {
            let table = scan.components[scanIndex].acTable
            let conditioning = scan.arithmeticACTables[table] ?? 5
            var statistics = acStatistics[table]
            var k = start
            while k <= end {
                var state = 3 * (k - 1)
                if try coder.decode(&statistics, state) != 0 { break }
                while try coder.decode(&statistics, state + 1) == 0 {
                    state += 3
                    k += 1
                    guard k <= end else {
                        throw DICOMCodecError.corruptedData("JPEG arithmetic AC run overflows the band")
                    }
                }
                let sign = try coder.decode(&fixed, 0)
                state += 2
                var magnitude = try coder.decode(&statistics, state)
                if magnitude != 0, try coder.decode(&statistics, state) != 0 {
                    magnitude <<= 1
                    state = k <= conditioning ? 189 : 217
                    while try coder.decode(&statistics, state) != 0 {
                        magnitude <<= 1
                        guard magnitude != 0x8000 else {
                            throw DICOMCodecError.corruptedData("JPEG arithmetic AC magnitude overflows")
                        }
                        state += 1
                    }
                }
                var value = magnitude
                state += 14
                var bit = magnitude >> 1
                while bit != 0 {
                    if try coder.decode(&statistics, state) != 0 { value |= bit }
                    bit >>= 1
                }
                value += 1
                if sign != 0 { value = -value }
                coefficients[component][base + JPEGIDCT.naturalOrder[k]] = Int32(truncatingIfNeeded: value << low)
                k += 1
            }
            acStatistics[table] = statistics
        }

        func decodeBlock(_ scanIndex: Int, component: Int, blockIndex: Int) throws {
            let base = blockIndex * 64
            if !progressive {
                let dc = try decodeDC(scanIndex)
                coefficients[component][base] = Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: dc)))
                try decodeAC(scanIndex, component: component, base: base, start: 1, end: 63, low: 0)
                return
            }
            let low = scan.approximationLow
            if scan.spectralStart == 0 {
                if scan.approximationHigh == 0 {
                    let dc = Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: try decodeDC(scanIndex))))
                    coefficients[component][base] = dc << low
                } else if try coder.decode(&fixed, 0) != 0 {
                    coefficients[component][base] |= Int32(1 << low)
                }
                return
            }
            if scan.approximationHigh == 0 {
                try decodeAC(scanIndex, component: component, base: base,
                             start: scan.spectralStart, end: scan.spectralEnd, low: low)
                return
            }

            let plus = Int32(1 << low)
            let minus = -plus
            let table = scan.components[scanIndex].acTable
            var statistics = acStatistics[table]
            var lastNonzero = scan.spectralEnd
            while lastNonzero > 0,
                  coefficients[component][base + JPEGIDCT.naturalOrder[lastNonzero]] == 0 { lastNonzero -= 1 }
            var k = scan.spectralStart
            while k <= scan.spectralEnd {
                var state = 3 * (k - 1)
                if k > lastNonzero, try coder.decode(&statistics, state) != 0 { break }
                while true {
                    let position = base + JPEGIDCT.naturalOrder[k]
                    if coefficients[component][position] != 0 {
                        if try coder.decode(&statistics, state + 2) != 0 {
                            coefficients[component][position] += coefficients[component][position] < 0 ? minus : plus
                        }
                        break
                    }
                    if try coder.decode(&statistics, state + 1) != 0 {
                        coefficients[component][position] = try coder.decode(&fixed, 0) != 0 ? minus : plus
                        break
                    }
                    state += 3
                    k += 1
                    guard k <= scan.spectralEnd else {
                        throw DICOMCodecError.corruptedData("JPEG arithmetic AC refinement run overflows the band")
                    }
                }
                k += 1
            }
            acStatistics[table] = statistics
        }

        resetForRestart()
        if scan.components.count == 1 {
            let component = scan.components[0].componentIndex
            let dimensions = componentBlocks[component]
            for row in 0..<dimensions.rows {
                for column in 0..<dimensions.columns {
                    try restartIfNeeded()
                    try decodeBlock(0, component: component, blockIndex: row * blocksPerLine[component] + column)
                }
            }
        } else {
            for mcuRow in 0..<mcuRows {
                for mcuColumn in 0..<mcusPerLine {
                    try restartIfNeeded()
                    for (scanIndex, item) in scan.components.enumerated() {
                        let component = item.componentIndex
                        let sampling = frame.components[component]
                        for blockRow in 0..<sampling.verticalSampling {
                            for blockColumn in 0..<sampling.horizontalSampling {
                                let row = mcuRow * sampling.verticalSampling + blockRow
                                let column = mcuColumn * sampling.horizontalSampling + blockColumn
                                try decodeBlock(scanIndex, component: component,
                                                blockIndex: row * blocksPerLine[component] + column)
                            }
                        }
                    }
                }
            }
        }
    }
}

extension DICOMJPEGLosslessCodec {
    /// SOF11 predictive decoding (T.81 Annex H) with the arithmetic contexts
    /// defined by F.1.4.4.1 and the neighbouring prediction residuals.
    func decodeArithmeticScan(
        _ scan: JPEGStream.Scan, precision: Int, width: Int, height: Int,
        planes: inout [[Int]], differential: Bool = false
    ) throws {
        let predictor = scan.spectralStart
        let pointTransform = scan.approximationLow
        // Differential frames (SOF15) code differences without prediction.
        guard differential || (1...7).contains(predictor) else {
            throw DICOMCodecError.unsupportedImage("JPEG Lossless predictor \(predictor)")
        }
        guard pointTransform < precision, scan.spectralEnd == 0, scan.approximationHigh == 0 else {
            throw DICOMCodecError.corruptedData("JPEG arithmetic Lossless scan parameters are invalid")
        }

        var coder = JPEGArithmeticDecoder(scan.entropyCodedData)
        // 25 sign/zero sets of four bins, then low/high magnitude sets,
        // each containing 15 X and 15 M bins.
        // H.1.2 models every scan component independently. The DC table
        // selector chooses its conditioning bounds, not a shared state area.
        var statistics = [[UInt8]](
            repeating: [UInt8](repeating: 0, count: 160), count: scan.components.count)
        var leftDifferences = [Int](repeating: 0, count: scan.components.count)
        var aboveDifferences = [[Int]](
            repeating: [Int](repeating: 0, count: width), count: scan.components.count)
        var untilRestart = scan.restartInterval
        var restartIndex = 0
        var restartOrigin = (x: 0, y: 0)
        let initial = 1 << (precision - pointTransform - 1)

        func category(_ difference: Int, lower: Int, upper: Int) -> Int {
            let magnitude = abs(difference)
            if magnitude <= ((1 << lower) >> 1) { return 0 }
            if magnitude <= (1 << upper) { return difference < 0 ? -1 : 1 }
            return difference < 0 ? -2 : 2
        }

        func prediction(_ plane: [Int], _ index: Int, _ x: Int, _ y: Int) -> Int {
            if differential { return 0 }
            if y == restartOrigin.y {
                return x == restartOrigin.x ? initial : plane[index - 1]
            }
            if x == 0 { return plane[index - width] }
            let a = plane[index - 1], b = plane[index - width], c = plane[index - width - 1]
            switch predictor {
            case 1: return a
            case 2: return b
            case 3: return c
            case 4: return a + b - c
            case 5: return a + ((b - c) >> 1)
            case 6: return b + ((a - c) >> 1)
            default: return (a + b) >> 1
            }
        }

        for y in 0..<height {
            leftDifferences = leftDifferences.map { _ in 0 }
            for x in 0..<width {
                if scan.restartInterval > 0 && untilRestart == 0 {
                    try coder.restart(expecting: restartIndex)
                    restartIndex += 1
                    untilRestart = scan.restartInterval
                    statistics = statistics.map { _ in [UInt8](repeating: 0, count: 160) }
                    leftDifferences = leftDifferences.map { _ in 0 }
                    aboveDifferences = aboveDifferences.map { _ in [Int](repeating: 0, count: width) }
                    restartOrigin = (x, y)
                }
                let index = y * width + x
                for (scanIndex, component) in scan.components.enumerated() {
                    let table = component.dcTable
                    let conditioning = scan.arithmeticDCTables[table] ?? (0, 1)
                    let da = leftDifferences[scanIndex]
                    let db = aboveDifferences[scanIndex][x]
                    let ca = category(da, lower: conditioning.lower, upper: conditioning.upper) + 2
                    let cb = category(db, lower: conditioning.lower, upper: conditioning.upper) + 2
                    let zeroBase = (ca * 5 + cb) * 4
                    var bins = statistics[scanIndex]
                    let difference: Int
                    if try coder.decode(&bins, zeroBase) == 0 {
                        difference = 0
                    } else {
                        let negative = try coder.decode(&bins, zeroBase + 1) != 0
                        let nonunit = try coder.decode(&bins, zeroBase + (negative ? 3 : 2)) != 0
                        var shiftedMagnitude = 0
                        if nonunit {
                            let high = abs(db) > (1 << conditioning.upper)
                            let magnitudeBase = high ? 130 : 100
                            var i = 0
                            var bit = 2
                            while try coder.decode(&bins, magnitudeBase + i) != 0 {
                                bit <<= 1
                                i += 1
                                guard i < 15 else {
                                    throw DICOMCodecError.corruptedData("JPEG arithmetic Lossless magnitude overflows")
                                }
                            }
                            bit >>= 1
                            shiftedMagnitude = bit
                            while true {
                                bit >>= 1
                                if bit == 0 { break }
                                if try coder.decode(&bins, magnitudeBase + 15 + i) != 0 {
                                    shiftedMagnitude |= bit
                                }
                            }
                        }
                        difference = negative ? -shiftedMagnitude - 1 : shiftedMagnitude + 1
                    }
                    statistics[scanIndex] = bins
                    let planeIndex = component.componentIndex
                    let predicted = prediction(planes[planeIndex], index, x, y)
                    planes[planeIndex][index] = (predicted + difference) & 0xFFFF
                    leftDifferences[scanIndex] = difference
                    aboveDifferences[scanIndex][x] = difference
                }
                if scan.restartInterval > 0 { untilRestart -= 1 }
            }
        }
    }
}
