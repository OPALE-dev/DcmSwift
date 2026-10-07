import Foundation

/// The marker structure of an ITU-T T.81 (ISO/IEC 10918-1) interchange
/// format stream: frame header, tables, and scans with their entropy-coded
/// segments. Shared by the JPEG decoders.
struct JPEGStream {
    struct Component: Equatable {
        let identifier: UInt8
        let horizontalSampling: Int
        let verticalSampling: Int
        let quantizationTable: Int
    }

    struct Frame {
        /// The SOF marker's low nibble: 0 baseline, 1 extended, 2
        /// progressive, 3 lossless (Huffman); others are unsupported.
        let process: UInt8
        let precision: Int
        let lines: Int
        let samplesPerLine: Int
        let components: [Component]
    }

    struct ScanComponent {
        let componentIndex: Int
        let dcTable: Int
        let acTable: Int
    }

    struct Scan {
        let components: [ScanComponent]
        /// Ss: spectral selection start, or the lossless predictor.
        let spectralStart: Int
        let spectralEnd: Int
        let approximationHigh: Int
        /// Al: successive approximation low bit, or the lossless point
        /// transform.
        let approximationLow: Int
        let restartInterval: Int
        let dcTables: [Int: JPEGHuffmanTable]
        let acTables: [Int: JPEGHuffmanTable]
        let quantizationTables: [Int: [Int]]
        /// The entropy-coded data, including RST markers and stuffed bytes.
        let entropyCodedData: ArraySlice<UInt8>
    }

    let frame: Frame
    let scans: [Scan]

    init(_ bytes: [UInt8]) throws {
        func fail(_ reason: String) -> DICOMCodecError { .corruptedData("JPEG \(reason)") }

        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { throw fail("stream does not start with SOI") }
        var position = 2
        var frame: Frame?
        var scans: [Scan] = []
        var dcTables: [Int: JPEGHuffmanTable] = [:]
        var acTables: [Int: JPEGHuffmanTable] = [:]
        var quantizationTables: [Int: [Int]] = [:]
        var restartInterval = 0

        func uint16(_ at: Int) -> Int { Int(bytes[at]) << 8 | Int(bytes[at + 1]) }

        markers: while true {
            // Markers may be preceded by any number of FFH fill bytes.
            while position < bytes.count && bytes[position] == 0xFF && position + 1 < bytes.count
                    && bytes[position + 1] == 0xFF {
                position += 1
            }
            guard position + 1 < bytes.count, bytes[position] == 0xFF else {
                throw fail("expected a marker at byte \(position)")
            }
            let marker = bytes[position + 1]
            position += 2
            if marker == 0xD9 { break markers }
            if (0xD0...0xD7).contains(marker) || marker == 0x01 { continue }

            guard position + 2 <= bytes.count else { throw fail("marker segment is truncated") }
            let length = uint16(position)
            guard length >= 2, position + length <= bytes.count else { throw fail("marker segment length is invalid") }
            let segment = (position + 2)..<(position + length)
            position += length

            switch marker {
            case 0xC0...0xCF where marker != 0xC4 && marker != 0xC8 && marker != 0xCC:
                guard frame == nil else { throw fail("has several frame headers") }
                guard segment.count >= 6 else { throw fail("frame header is truncated") }
                let count = Int(bytes[segment.lowerBound + 5])
                guard count >= 1, segment.count == 6 + 3 * count else { throw fail("frame header is invalid") }
                let components = (0..<count).map { index -> Component in
                    let base = segment.lowerBound + 6 + 3 * index
                    return Component(
                        identifier: bytes[base],
                        horizontalSampling: Int(bytes[base + 1] >> 4),
                        verticalSampling: Int(bytes[base + 1] & 0x0F),
                        quantizationTable: Int(bytes[base + 2]))
                }
                guard components.allSatisfy({ (1...4).contains($0.horizontalSampling) && (1...4).contains($0.verticalSampling) }) else {
                    throw fail("sampling factors are invalid")
                }
                frame = Frame(
                    process: marker & 0x0F,
                    precision: Int(bytes[segment.lowerBound]),
                    lines: uint16(segment.lowerBound + 1),
                    samplesPerLine: uint16(segment.lowerBound + 3),
                    components: components)

            case 0xC4:
                var offset = segment.lowerBound
                while offset < segment.upperBound {
                    guard offset + 17 <= segment.upperBound else { throw fail("Huffman table is truncated") }
                    let tableClass = bytes[offset] >> 4
                    let identifier = Int(bytes[offset] & 0x0F)
                    let counts = Array(bytes[(offset + 1)..<(offset + 17)])
                    let total = counts.reduce(0) { $0 + Int($1) }
                    guard tableClass <= 1, identifier <= 3, offset + 17 + total <= segment.upperBound else {
                        throw fail("Huffman table is invalid")
                    }
                    let values = Array(bytes[(offset + 17)..<(offset + 17 + total)])
                    let table = try JPEGHuffmanTable(counts: counts, values: values)
                    if tableClass == 0 { dcTables[identifier] = table } else { acTables[identifier] = table }
                    offset += 17 + total
                }

            case 0xDB:
                var offset = segment.lowerBound
                while offset < segment.upperBound {
                    let precision = bytes[offset] >> 4
                    let identifier = Int(bytes[offset] & 0x0F)
                    let size = precision == 0 ? 64 : 128
                    guard identifier <= 3, precision <= 1, offset + 1 + size <= segment.upperBound else {
                        throw fail("quantization table is invalid")
                    }
                    quantizationTables[identifier] = (0..<64).map { index in
                        precision == 0 ? Int(bytes[offset + 1 + index]) : uint16(offset + 1 + 2 * index)
                    }
                    offset += 1 + size
                }

            case 0xDD:
                guard segment.count == 2 else { throw fail("restart interval is invalid") }
                restartInterval = uint16(segment.lowerBound)

            case 0xDA:
                guard let frame else { throw fail("scan precedes the frame header") }
                guard segment.count >= 1 else { throw fail("scan header is truncated") }
                let count = Int(bytes[segment.lowerBound])
                guard count >= 1, count <= 4, segment.count == 4 + 2 * count else { throw fail("scan header is invalid") }
                let components = try (0..<count).map { index -> ScanComponent in
                    let base = segment.lowerBound + 1 + 2 * index
                    guard let componentIndex = frame.components.firstIndex(where: { $0.identifier == bytes[base] }) else {
                        throw fail("scan refers to an unknown component")
                    }
                    return ScanComponent(
                        componentIndex: componentIndex,
                        dcTable: Int(bytes[base + 1] >> 4),
                        acTable: Int(bytes[base + 1] & 0x0F))
                }
                let tail = segment.upperBound - 3
                let entropyEnd = Self.endOfEntropyCodedData(in: bytes, from: position)
                scans.append(Scan(
                    components: components,
                    spectralStart: Int(bytes[tail]),
                    spectralEnd: Int(bytes[tail + 1]),
                    approximationHigh: Int(bytes[tail + 2] >> 4),
                    approximationLow: Int(bytes[tail + 2] & 0x0F),
                    restartInterval: restartInterval,
                    dcTables: dcTables,
                    acTables: acTables,
                    quantizationTables: quantizationTables,
                    entropyCodedData: bytes[position..<entropyEnd]))
                position = entropyEnd

            case 0xDC:
                throw DICOMCodecError.unsupportedImage("JPEG DNL markers are not supported")

            default:
                // APPn, COM, and other segments carry nothing the decoders need.
                break
            }

            if position >= bytes.count {
                // A missing EOI is tolerated once the scans are complete.
                break markers
            }
        }

        guard let frame else { throw fail("has no frame header") }
        guard !scans.isEmpty else { throw fail("has no scan") }
        self.frame = frame
        self.scans = scans
    }

    /// The index of the first marker that ends the entropy-coded segment:
    /// FFH followed by a byte other than 00H (stuffing) or D0H-D7H (RST).
    private static func endOfEntropyCodedData(in bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index + 1 < bytes.count {
            if bytes[index] == 0xFF {
                let next = bytes[index + 1]
                if next == 0x00 || (0xD0...0xD7).contains(next) {
                    index += 2
                    continue
                }
                if next == 0xFF {
                    index += 1
                    continue
                }
                return index
            }
            index += 1
        }
        return bytes.count
    }
}
