import Foundation

/// JPEG Baseline (Process 1, 1.2.840.10008.1.2.4.50) and Extended (Process 2
/// and 4, 1.2.840.10008.1.2.4.51), DCT-based with Huffman coding (ITU-T T.81
/// Annexes F and G). Progressive (SOF2) streams are also decoded, as
/// recommended for receivers.
///
/// Decoding reproduces the IJG reference algorithms (accurate integer IDCT,
/// fancy upsampling, and fixed-point YCbCr conversion), so results match
/// libjpeg-turbo, DCMTK, and GDCM exactly. Color frames are returned as RGB.
/// The retired progressive Huffman syntaxes (Processes 6, 8, 10, and 12) use
/// the same decoder so that older files remain readable.
public struct DICOMJPEGBaselineCodec: DICOMPixelDataDecoder {
    public static let baseline = "1.2.840.10008.1.2.4.50"
    public static let extended = "1.2.840.10008.1.2.4.51"
    /// Retired: Spectral Selection, Non-Hierarchical (Process 6 & 8).
    public static let spectralSelection = "1.2.840.10008.1.2.4.53"
    /// Retired: Full Progression, Non-Hierarchical (Process 10 & 12).
    public static let fullProgression = "1.2.840.10008.1.2.4.55"
    public var transferSyntaxUIDs: Set<String> {
        [Self.baseline, Self.extended, Self.spectralSelection, Self.fullProgression]
    }

    public init() {}

    public func decode(_ encodedFrame: Data, description: DICOMPixelDescription) throws -> DICOMDecodedFrame {
        let bytes = [UInt8](encodedFrame)
        let stream = try JPEGStream(bytes)
        let frame = stream.frame
        guard frame.process <= 2 else {
            throw DICOMCodecError.unsupportedImage("SOF\(frame.process) is not a DCT-based Huffman JPEG process")
        }
        guard frame.precision == 8 || frame.precision == 12 else {
            throw DICOMCodecError.corruptedData("JPEG precision \(frame.precision)")
        }
        guard frame.lines == description.rows, frame.samplesPerLine == description.columns,
              frame.components.count == description.samplesPerPixel,
              frame.components.count == 1 || frame.components.count == 3 else {
            throw DICOMCodecError.corruptedData(
                "JPEG frame is \(frame.samplesPerLine)x\(frame.lines)x\(frame.components.count), image is "
                    + "\(description.columns)x\(description.rows)x\(description.samplesPerPixel)")
        }
        let cellBytes = description.bitsAllocated / 8
        guard (cellBytes == 1 || cellBytes == 2), frame.precision <= description.bitsAllocated else {
            throw DICOMCodecError.unsupportedImage(
                "\(frame.precision)-bit JPEG in \(description.bitsAllocated) bits allocated")
        }

        var decoder = try JPEGDCTDecoder(frame: frame)
        for scan in stream.scans {
            try decoder.decode(scan, progressive: frame.process == 2)
        }
        let planes = try decoder.samplePlanes(quantization: stream.scans.last!.quantizationTables)

        var photometric = description.photometricInterpretation
        var output: [UInt16]
        if frame.components.count == 3 {
            let pixels = try decoder.upsample(planes)
            if Self.isYCbCr(bytes, frame: frame) {
                output = Self.ycbcrToRGB(pixels, count: frame.lines * frame.samplesPerLine, precision: frame.precision)
                photometric = .rgb
            } else {
                output = pixels
                photometric = .rgb
            }
        } else {
            output = planes[0].croppedSamples(width: frame.samplesPerLine, height: frame.lines)
        }

        var data = [UInt8](repeating: 0, count: output.count * cellBytes)
        for (index, value) in output.enumerated() {
            data[index * cellBytes] = UInt8(value & 0xFF)
            if cellBytes == 2 { data[index * cellBytes + 1] = UInt8(value >> 8) }
        }
        return DICOMDecodedFrame(
            description: description.decodedFrame(photometricInterpretation: photometric, planarConfiguration: 0),
            data: Data(data))
    }

    /// libjpeg's color space detection: JFIF implies YCbCr, an Adobe marker
    /// states the transform, and otherwise component identifiers "R", "G",
    /// "B" denote RGB.
    static func isYCbCr(_ bytes: [UInt8], frame: JPEGStream.Frame) -> Bool {
        var position = 2
        var sawJFIF = false
        var adobeTransform: UInt8?
        while position + 4 <= bytes.count, bytes[position] == 0xFF {
            let marker = bytes[position + 1]
            if marker == 0xDA || marker == 0xD9 { break }
            let length = Int(bytes[position + 2]) << 8 | Int(bytes[position + 3])
            guard length >= 2, position + 2 + length <= bytes.count else { break }
            let payload = bytes[(position + 4)..<(position + 2 + length)]
            if marker == 0xE0, payload.starts(with: Array("JFIF\0".utf8)) { sawJFIF = true }
            if marker == 0xEE, payload.starts(with: Array("Adobe".utf8)), payload.count >= 12 {
                adobeTransform = payload[payload.startIndex + 11]
            }
            position += 2 + length
        }
        if sawJFIF { return true }
        if let adobeTransform { return adobeTransform != 0 }
        let identifiers = frame.components.map(\.identifier)
        return identifiers != [0x52, 0x47, 0x42]
    }

    /// IJG fixed-point YCbCr to RGB conversion (jdcolor.c, 16 fraction bits).
    static func ycbcrToRGB(_ samples: [UInt16], count: Int, precision: Int) -> [UInt16] {
        let tables = precision > 8 ? ColorTables.twelveBit : ColorTables.eightBit
        let maximum = (1 << precision) - 1
        var output = [UInt16](repeating: 0, count: count * 3)
        samples.withUnsafeBufferPointer { input in
            output.withUnsafeMutableBufferPointer { out in
                for pixel in 0..<count {
                    let y = Int(input[pixel * 3])
                    let cb = Int(input[pixel * 3 + 1])
                    let cr = Int(input[pixel * 3 + 2])
                    let r = y + tables.crR[cr]
                    let g = y + ((tables.cbG[cb] + tables.crG[cr]) >> 16)
                    let b = y + tables.cbB[cb]
                    out[pixel * 3] = UInt16(r < 0 ? 0 : (r > maximum ? maximum : r))
                    out[pixel * 3 + 1] = UInt16(g < 0 ? 0 : (g > maximum ? maximum : g))
                    out[pixel * 3 + 2] = UInt16(b < 0 ? 0 : (b > maximum ? maximum : b))
                }
            }
        }
        return output
    }

    private struct ColorTables {
        let crR: [Int], cbB: [Int], crG: [Int], cbG: [Int]

        static let eightBit = ColorTables(precision: 8)
        static let twelveBit = ColorTables(precision: 12)

        init(precision: Int) {
            let maximum = (1 << precision) - 1
            let center = 1 << (precision - 1)
            let half = 1 << 15
            func fix(_ value: Double) -> Int { Int(value * 65536 + 0.5) }
            crR = (0...maximum).map { (fix(1.40200) * ($0 - center) + half) >> 16 }
            cbB = (0...maximum).map { (fix(1.77200) * ($0 - center) + half) >> 16 }
            crG = (0...maximum).map { -fix(0.71414) * ($0 - center) }
            cbG = (0...maximum).map { -fix(0.34414) * ($0 - center) + half }
        }
    }
}

/// One component's samples after the inverse DCT, padded to whole blocks.
struct JPEGSamplePlane {
    let width: Int
    let height: Int
    let stride: Int
    var samples: [UInt16]

    func croppedSamples(width: Int, height: Int) -> [UInt16] {
        (0..<height).flatMap { row in samples[(row * stride)..<(row * stride + width)] }
    }

    func sample(_ x: Int, _ y: Int) -> Int {
        Int(samples[min(y, height - 1) * stride + min(x, width - 1)])
    }
}

/// Coefficient decoding for sequential and progressive DCT scans.
struct JPEGDCTDecoder {
    private let frame: JPEGStream.Frame
    private let maxHorizontal: Int
    private let maxVertical: Int
    private let mcusPerLine: Int
    private let mcuRows: Int
    /// Coefficients (natural order) of every block, per component.
    private var coefficients: [[Int32]]
    private var blocksPerLine: [Int]
    /// Blocks covering the component itself (non-interleaved scans).
    private var componentBlocks: [(columns: Int, rows: Int)]

    init(frame: JPEGStream.Frame) throws {
        self.frame = frame
        maxHorizontal = frame.components.map(\.horizontalSampling).max()!
        maxVertical = frame.components.map(\.verticalSampling).max()!
        mcusPerLine = (frame.samplesPerLine + 8 * maxHorizontal - 1) / (8 * maxHorizontal)
        mcuRows = (frame.lines + 8 * maxVertical - 1) / (8 * maxVertical)
        guard frame.lines > 0, frame.samplesPerLine > 0, mcusPerLine * mcuRows <= 1 << 24 else {
            throw DICOMCodecError.corruptedData("JPEG dimensions are invalid")
        }
        coefficients = []
        blocksPerLine = []
        componentBlocks = []
        for component in frame.components {
            let perLine = mcusPerLine * component.horizontalSampling
            let rows = mcuRows * component.verticalSampling
            coefficients.append([Int32](repeating: 0, count: perLine * rows * 64))
            blocksPerLine.append(perLine)
            let width = (frame.samplesPerLine * component.horizontalSampling + maxHorizontal - 1) / maxHorizontal
            let height = (frame.lines * component.verticalSampling + maxVertical - 1) / maxVertical
            componentBlocks.append(((width + 7) / 8, (height + 7) / 8))
        }
    }

    mutating func decode(_ scan: JPEGStream.Scan, progressive: Bool) throws {
        var reader = JPEGBitReader(scan.entropyCodedData)
        var predictions = [Int](repeating: 0, count: frame.components.count)
        var endOfBandRun = 0
        let restartInterval = scan.restartInterval
        var restartIndex = 0
        var untilRestart = restartInterval

        func table(_ tables: [Int: JPEGHuffmanTable], _ identifier: Int) throws -> JPEGHuffmanTable {
            guard let table = tables[identifier] else {
                throw DICOMCodecError.corruptedData("JPEG Huffman table \(identifier) is missing")
            }
            return table
        }
        let dcTables = try scan.components.map { component -> JPEGHuffmanTable? in
            progressive && scan.spectralStart > 0 ? nil : try table(scan.dcTables, component.dcTable)
        }
        let acTables = try scan.components.map { component -> JPEGHuffmanTable? in
            progressive && scan.spectralStart == 0 ? nil : try table(scan.acTables, component.acTable)
        }
        if progressive {
            // G.1.1.1: DC scans have Ss = Se = 0; AC scans 0 < Ss <= Se <= 63
            // and a single component.
            let validDC = scan.spectralStart == 0 && scan.spectralEnd == 0
            let validAC = scan.spectralStart > 0 && scan.spectralStart <= scan.spectralEnd
                && scan.spectralEnd <= 63 && scan.components.count == 1
            guard validDC || validAC else {
                throw DICOMCodecError.corruptedData("JPEG progressive scan parameters are invalid")
            }
        }

        func decodeBlock(_ scanIndex: Int, _ component: Int, _ blockIndex: Int) throws {
            let base = blockIndex * 64
            if !progressive {
                let category = try dcTables[scanIndex]!.decode(&reader)
                guard category <= 15 else { throw DICOMCodecError.corruptedData("JPEG DC category \(category)") }
                predictions[component] += reader.receiveExtend(category)
                coefficients[component][base] = Int32(truncatingIfNeeded: predictions[component])
                var k = 1
                while k < 64 {
                    let symbol = try acTables[scanIndex]!.decode(&reader)
                    let run = symbol >> 4, size = symbol & 15
                    if size == 0 {
                        if run == 15 { k += 16; continue }
                        break
                    }
                    k += run
                    guard k < 64 else { throw DICOMCodecError.corruptedData("JPEG AC run overflows the block") }
                    coefficients[component][base + JPEGIDCT.naturalOrder[k]] = Int32(reader.receiveExtend(size))
                    k += 1
                }
                return
            }

            let low = scan.approximationLow
            if scan.spectralStart == 0 {
                if scan.approximationHigh == 0 {
                    let category = try dcTables[scanIndex]!.decode(&reader)
                    guard category <= 15 else { throw DICOMCodecError.corruptedData("JPEG DC category \(category)") }
                    predictions[component] += reader.receiveExtend(category)
                    coefficients[component][base] = Int32(truncatingIfNeeded: predictions[component] << low)
                } else if reader.bits(1) == 1 {
                    coefficients[component][base] |= Int32(1 << low)
                }
                return
            }

            let start = scan.spectralStart, end = scan.spectralEnd
            if scan.approximationHigh == 0 {
                // AC first pass (G.1.2.2).
                if endOfBandRun > 0 { endOfBandRun -= 1; return }
                var k = start
                while k <= end {
                    let symbol = try acTables[scanIndex]!.decode(&reader)
                    let run = symbol >> 4, size = symbol & 15
                    if size != 0 {
                        k += run
                        guard k <= end else { throw DICOMCodecError.corruptedData("JPEG AC run overflows the band") }
                        coefficients[component][base + JPEGIDCT.naturalOrder[k]] =
                            Int32(truncatingIfNeeded: reader.receiveExtend(size) << low)
                    } else if run == 15 {
                        k += 15
                    } else {
                        endOfBandRun = (1 << run) - 1 + reader.bits(run)
                        break
                    }
                    k += 1
                }
                return
            }

            // AC refinement (G.1.2.3), as in IJG decode_mcu_AC_refine.
            let plusOne = Int32(1 << low), minusOne = Int32(-1 << low)
            var k = start
            func refine(_ index: Int) {
                let position = base + JPEGIDCT.naturalOrder[index]
                let value = coefficients[component][position]
                if value != 0, reader.bits(1) == 1, value & plusOne == 0 {
                    coefficients[component][position] = value >= 0 ? value + plusOne : value + minusOne
                }
            }
            if endOfBandRun == 0 {
                while k <= end {
                    let symbol = try acTables[scanIndex]!.decode(&reader)
                    var run = symbol >> 4
                    let size = symbol & 15
                    var newValue: Int32 = 0
                    if size != 0 {
                        guard size == 1 else { throw DICOMCodecError.corruptedData("JPEG refinement size \(size)") }
                        newValue = reader.bits(1) == 1 ? plusOne : minusOne
                    } else if run != 15 {
                        endOfBandRun = (1 << run) + reader.bits(run)
                        break
                    }
                    // Skip `run` zero coefficients, refining non-zero ones.
                    while k <= end {
                        let position = base + JPEGIDCT.naturalOrder[k]
                        if coefficients[component][position] != 0 {
                            refine(k)
                        } else {
                            if run == 0 { break }
                            run -= 1
                        }
                        k += 1
                    }
                    if newValue != 0, k <= end {
                        coefficients[component][base + JPEGIDCT.naturalOrder[k]] = newValue
                    }
                    k += 1
                }
            }
            if endOfBandRun > 0 {
                while k <= end {
                    refine(k)
                    k += 1
                }
                endOfBandRun -= 1
            }
        }

        func restartIfNeeded() throws {
            guard restartInterval > 0 else { return }
            if untilRestart == 0 {
                try reader.restart(expecting: restartIndex)
                restartIndex += 1
                untilRestart = restartInterval
                predictions = predictions.map { _ in 0 }
                endOfBandRun = 0
            }
            untilRestart -= 1
        }

        if scan.components.count == 1 {
            // Non-interleaved: one block per MCU over the component's own
            // blocks (A.2.2).
            let component = scan.components[0].componentIndex
            let (columns, rows) = componentBlocks[component]
            for row in 0..<rows {
                for column in 0..<columns {
                    try restartIfNeeded()
                    try decodeBlock(0, component, row * blocksPerLine[component] + column)
                }
            }
        } else {
            for mcuRow in 0..<mcuRows {
                for mcuColumn in 0..<mcusPerLine {
                    try restartIfNeeded()
                    for (scanIndex, scanComponent) in scan.components.enumerated() {
                        let component = scanComponent.componentIndex
                        let h = frame.components[component].horizontalSampling
                        let v = frame.components[component].verticalSampling
                        for blockRow in 0..<v {
                            for blockColumn in 0..<h {
                                let row = mcuRow * v + blockRow
                                let column = mcuColumn * h + blockColumn
                                try decodeBlock(scanIndex, component, row * blocksPerLine[component] + column)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Dequantizes and inverse transforms every block.
    func samplePlanes(quantization: [Int: [Int]]) throws -> [JPEGSamplePlane] {
        try frame.components.enumerated().map { index, component in
            guard let zigzag = quantization[component.quantizationTable] else {
                throw DICOMCodecError.corruptedData("JPEG quantization table \(component.quantizationTable) is missing")
            }
            var natural = [Int32](repeating: 0, count: 64)
            for k in 0..<64 { natural[JPEGIDCT.naturalOrder[k]] = Int32(zigzag[k]) }
            let perLine = blocksPerLine[index]
            let rows = coefficients[index].count / 64 / perLine
            let stride = perLine * 8
            var samples = [UInt16](repeating: 0, count: stride * rows * 8)
            let block = UnsafeMutablePointer<Int32>.allocate(capacity: 64)
            let workspace = UnsafeMutablePointer<Int>.allocate(capacity: 64)
            defer { block.deallocate(); workspace.deallocate() }
            coefficients[index].withUnsafeBufferPointer { source in
                samples.withUnsafeMutableBufferPointer { output in
                    for blockRow in 0..<rows {
                        for blockColumn in 0..<perLine {
                            let base = (blockRow * perLine + blockColumn) * 64
                            for i in 0..<64 { block[i] = source[base + i] &* natural[i] }
                            JPEGIDCT.inverse(
                                block, precision: frame.precision,
                                output: output.baseAddress! + blockRow * 8 * stride + blockColumn * 8, stride: stride,
                                workspace: workspace)
                        }
                    }
                }
            }
            let width = (frame.samplesPerLine * component.horizontalSampling + maxHorizontal - 1) / maxHorizontal
            let height = (frame.lines * component.verticalSampling + maxVertical - 1) / maxVertical
            return JPEGSamplePlane(width: width, height: height, stride: stride, samples: samples)
        }
    }

    /// Upsamples every component to full resolution and interleaves them,
    /// with IJG fancy (triangle) filters for h2v1, h1v2, and h2v2 and
    /// replication otherwise.
    func upsample(_ planes: [JPEGSamplePlane]) throws -> [UInt16] {
        let width = frame.samplesPerLine, height = frame.lines
        let count = planes.count
        var output = [UInt16](repeating: 0, count: width * height * count)
        // One full-resolution row, written then interleaved.
        var row = [Int](repeating: 0, count: 2 * (width + 8))
        for (index, plane) in planes.enumerated() {
            let hFactor = maxHorizontal / frame.components[index].horizontalSampling
            let vFactor = maxVertical / frame.components[index].verticalSampling
            guard hFactor * frame.components[index].horizontalSampling == maxHorizontal,
                  vFactor * frame.components[index].verticalSampling == maxVertical else {
                throw DICOMCodecError.unsupportedImage("fractional JPEG sampling factors")
            }
            // libjpeg-turbo filters h2 components only when wider than two
            // samples (jinit_upsampler).
            let fancy = hFactor == 1 || plane.width > 2
            let mode = (fancy ? hFactor : 0, vFactor)
            let pw = plane.width, ph = plane.height, stride = plane.stride

            plane.samples.withUnsafeBufferPointer { source in
                output.withUnsafeMutableBufferPointer { out in
                    row.withUnsafeMutableBufferPointer { line in
                        @inline(__always) func s(_ x: Int, _ y: Int) -> Int { Int(source[y * stride + x]) }
                        @inline(__always) func emit(_ y: Int) {
                            guard y < height else { return }
                            let base = y * width * count + index
                            for x in 0..<width { out[base + x * count] = UInt16(line[x]) }
                        }
                        switch mode {
                        case (1, 1):
                            for y in 0..<height {
                                for x in 0..<width { line[x] = s(x, y) }
                                emit(y)
                            }
                        case (2, 1):
                            for y in 0..<ph {
                                var center = s(0, y) * 3
                                line[0] = s(0, y)
                                line[1] = (center + s(1, y) + 2) >> 2
                                for x in 1..<(pw - 1) {
                                    center = s(x, y) * 3
                                    line[2 * x] = (center + s(x - 1, y) + 1) >> 2
                                    line[2 * x + 1] = (center + s(x + 1, y) + 2) >> 2
                                }
                                let last = pw - 1
                                line[2 * last] = (s(last, y) * 3 + s(last - 1, y) + 1) >> 2
                                line[2 * last + 1] = s(last, y)
                                emit(y)
                            }
                        case (1, 2):
                            for y in 0..<ph {
                                let above = max(y - 1, 0), below = min(y + 1, ph - 1)
                                for x in 0..<pw { line[x] = (s(x, y) * 3 + s(x, above) + 1) >> 2 }
                                emit(2 * y)
                                for x in 0..<pw { line[x] = (s(x, y) * 3 + s(x, below) + 2) >> 2 }
                                emit(2 * y + 1)
                            }
                        case (2, 2):
                            var sums = [Int](repeating: 0, count: pw)
                            for y in 0..<ph {
                                for (outputRow, neighbor) in [(2 * y, max(y - 1, 0)), (2 * y + 1, min(y + 1, ph - 1))] {
                                    // Vertical triangle sums, then horizontal (jdsample.c).
                                    for x in 0..<pw { sums[x] = s(x, y) * 3 + s(x, neighbor) }
                                    line[0] = (sums[0] * 4 + 8) >> 4
                                    line[1] = (sums[0] * 3 + sums[1] + 7) >> 4
                                    for x in 1..<(pw - 1) {
                                        line[2 * x] = (sums[x] * 3 + sums[x - 1] + 8) >> 4
                                        line[2 * x + 1] = (sums[x] * 3 + sums[x + 1] + 7) >> 4
                                    }
                                    let last = pw - 1
                                    line[2 * last] = (sums[last] * 3 + sums[last - 1] + 8) >> 4
                                    line[2 * last + 1] = (sums[last] * 4 + 7) >> 4
                                    emit(outputRow)
                                }
                            }
                        default:
                            for y in 0..<height {
                                let sourceRow = min(y / vFactor, ph - 1)
                                for x in 0..<width { line[x] = s(min(x / hFactor, pw - 1), sourceRow) }
                                emit(y)
                            }
                        }
                    }
                }
            }
        }
        return output
    }
}
