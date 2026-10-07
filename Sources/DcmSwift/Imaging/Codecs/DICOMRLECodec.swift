import Foundation

/// RLE Lossless (1.2.840.10008.1.2.5, PS3.5 Annex G).
///
/// Each frame is a 64-byte header of up to 15 segment offsets followed by
/// PackBits-style segments. Segment `s * bytesPerSample + b` holds byte `b`
/// (most significant first) of sample `s` of every pixel.
public struct DICOMRLECodec: DICOMPixelDataDecoder {
    public static let transferSyntaxUID = "1.2.840.10008.1.2.5"
    public var transferSyntaxUIDs: Set<String> { [Self.transferSyntaxUID] }

    public init() {}

    // MARK: Decoding

    public func decode(_ encodedFrame: Data, description: DICOMPixelDescription) throws -> DICOMDecodedFrame {
        let bytesPerSample = try Self.bytesPerSample(description)
        let pixels = description.pixelsPerFrame
        let samples = description.samplesPerPixel
        let expectedSegments = samples * bytesPerSample
        let frame = [UInt8](encodedFrame)
        guard frame.count >= 64 else { throw DICOMCodecError.corruptedData("RLE header is truncated") }

        func uint32(at offset: Int) -> Int {
            (0..<4).reduce(0) { $0 | Int(frame[offset + $1]) << (8 * $1) }
        }
        let segmentCount = uint32(at: 0)
        guard segmentCount == expectedSegments else {
            throw DICOMCodecError.corruptedData("\(segmentCount) RLE segments for \(expectedSegments) expected")
        }
        let offsets = (1...segmentCount).map { uint32(at: $0 * 4) }
        guard offsets[0] == 64,
              zip(offsets, offsets.dropFirst()).allSatisfy({ $0 < $1 }),
              let last = offsets.last, last < frame.count else {
            throw DICOMCodecError.corruptedData("RLE segment offsets are invalid")
        }

        // Native little endian layout honoring the Planar Configuration.
        var native = [UInt8](repeating: 0, count: pixels * samples * bytesPerSample)
        for segment in 0..<segmentCount {
            let end = segment + 1 < segmentCount ? offsets[segment + 1] : frame.count
            let decoded = try Self.decodeSegment(frame[offsets[segment]..<end], length: pixels)
            let (sample, byte) = segment.quotientAndRemainder(dividingBy: bytesPerSample)
            let littleEndianByte = bytesPerSample - 1 - byte
            for pixel in 0..<pixels {
                let cell = description.planarConfiguration == 1
                    ? sample * pixels + pixel
                    : pixel * samples + sample
                native[cell * bytesPerSample + littleEndianByte] = decoded[pixel]
            }
        }

        let output = description.bitsAllocated == 1 ? Self.packBits(native) : native
        return DICOMDecodedFrame(description: description.decodedFrame(), data: Data(output))
    }

    /// Decodes one RLE Segment to exactly `length` bytes (PS3.5 G.3.2).
    static func decodeSegment(_ source: ArraySlice<UInt8>, length: Int) throws -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(length)
        var index = source.startIndex
        while output.count < length {
            guard index < source.endIndex else {
                throw DICOMCodecError.corruptedData("RLE segment ends after \(output.count) of \(length) bytes")
            }
            let header = Int(Int8(bitPattern: source[index]))
            index += 1
            if header >= 0 {
                let count = header + 1
                guard index + count <= source.endIndex, output.count + count <= length else {
                    throw DICOMCodecError.corruptedData("RLE literal run overflows the segment")
                }
                output.append(contentsOf: source[index..<(index + count)])
                index += count
            } else if header >= -127 {
                let count = 1 - header
                guard index < source.endIndex, output.count + count <= length else {
                    throw DICOMCodecError.corruptedData("RLE replicate run overflows the segment")
                }
                output.append(contentsOf: repeatElement(source[index], count: count))
                index += 1
            }
            // -128 is a no-operation.
        }
        return output
    }

    // MARK: Encoding

    /// Encodes one native little endian frame (as described) to an RLE frame.
    public func encode(_ frame: Data, description: DICOMPixelDescription) throws -> Data {
        let bytesPerSample = try Self.bytesPerSample(description)
        let pixels = description.pixelsPerFrame
        let samples = description.samplesPerPixel
        let segmentCount = samples * bytesPerSample
        guard segmentCount <= 15 else {
            throw DICOMCodecError.unsupportedImage("\(segmentCount) RLE segments exceed 15")
        }
        var native = [UInt8](frame)
        if description.bitsAllocated == 1 {
            native = (0..<pixels).map { (native[$0 >> 3] >> UInt8($0 & 7)) & 1 }
        }
        guard native.count >= pixels * samples * bytesPerSample else {
            throw DICOMPixelDataError.truncatedPixelData(
                expectedBytes: pixels * samples * bytesPerSample, actualBytes: native.count)
        }

        var segments: [[UInt8]] = []
        for segment in 0..<segmentCount {
            let (sample, byte) = segment.quotientAndRemainder(dividingBy: bytesPerSample)
            let littleEndianByte = bytesPerSample - 1 - byte
            var plane = [UInt8](repeating: 0, count: pixels)
            for pixel in 0..<pixels {
                let cell = description.planarConfiguration == 1 ? sample * pixels + pixel : pixel * samples + sample
                plane[pixel] = native[cell * bytesPerSample + littleEndianByte]
            }
            var encoded: [UInt8] = []
            // Rows are encoded separately (PS3.5 G.3.1).
            for row in 0..<description.rows {
                let start = row * description.columns
                Self.encodeRow(plane[start..<(start + description.columns)], into: &encoded)
            }
            if encoded.count % 2 == 1 { encoded.append(0) }
            segments.append(encoded)
        }

        var header = [UInt8](repeating: 0, count: 64)
        func put(_ value: Int, at offset: Int) {
            for byte in 0..<4 { header[offset + byte] = UInt8((value >> (8 * byte)) & 0xFF) }
        }
        put(segmentCount, at: 0)
        var offset = 64
        for (index, segment) in segments.enumerated() {
            put(offset, at: 4 * (index + 1))
            offset += segment.count
        }
        return Data(header + segments.flatMap { $0 })
    }

    /// Replicate runs of three or more bytes; two-byte runs inside literal
    /// runs stay literal (PS3.5 G.3.1).
    static func encodeRow(_ row: ArraySlice<UInt8>, into output: inout [UInt8]) {
        var literal: [UInt8] = []
        func flushLiteral() {
            var start = 0
            while start < literal.count {
                let count = min(128, literal.count - start)
                output.append(UInt8(count - 1))
                output.append(contentsOf: literal[start..<(start + count)])
                start += count
            }
            literal.removeAll(keepingCapacity: true)
        }
        var index = row.startIndex
        while index < row.endIndex {
            var run = 1
            while index + run < row.endIndex && run < 128 && row[index + run] == row[index] { run += 1 }
            if run >= 3 || (run == 2 && literal.isEmpty) {
                flushLiteral()
                output.append(UInt8(bitPattern: Int8(1 - run)))
                output.append(row[index])
            } else {
                literal.append(contentsOf: row[index..<(index + run)])
            }
            index += run
        }
        flushLiteral()
    }

    // MARK: Helpers

    private static func bytesPerSample(_ description: DICOMPixelDescription) throws -> Int {
        guard description.sampleFormat == .integer,
              description.bitsAllocated == 1 || description.bitsAllocated % 8 == 0 else {
            throw DICOMCodecError.unsupportedImage("RLE requires integer samples")
        }
        guard description.photometricInterpretation != .ybrFull422 else {
            throw DICOMCodecError.unsupportedImage("RLE does not carry YBR_FULL_422")
        }
        return max(1, description.bitsAllocated / 8)
    }

    /// Packs one byte per 1-bit pixel into bytes, least significant bit first.
    private static func packBits(_ bits: [UInt8]) -> [UInt8] {
        var packed = [UInt8](repeating: 0, count: (bits.count + 7) / 8)
        for (index, bit) in bits.enumerated() where bit & 1 == 1 {
            packed[index >> 3] |= 1 << UInt8(index & 7)
        }
        return packed
    }
}
