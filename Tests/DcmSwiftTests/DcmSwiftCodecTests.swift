import XCTest
@testable import DcmSwift

/// Encapsulated Pixel Data frame assembly (PS3.5 A.4, PS3.3 C.7.6.3.1.8) and
/// the RLE (PS3.5 Annex G) and Deflated Image Frame (A.4.13) codecs.
final class DcmSwiftCodecTests: XCTestCase {

    // MARK: RLE (PS3.5 Annex G)

    func testRLESegmentDecodingFollowsTheAnnexGPseudoCode() throws {
        // Literal run of 3, replicate run of 3, the -128 no-op, literal of 1.
        let segment: [UInt8] = [0x02, 1, 2, 3, 0xFE, 9, 0x80, 0x00, 4]
        XCTAssertEqual(try DICOMRLECodec.decodeSegment(segment[...], length: 7), [1, 2, 3, 9, 9, 9, 4])
        // Trailing padding after the expected length is ignored.
        XCTAssertEqual(try DICOMRLECodec.decodeSegment([0xFE, 7, 0x00][...], length: 3), [7, 7, 7])

        XCTAssertThrowsError(try DICOMRLECodec.decodeSegment([0x02, 1, 2][...], length: 3), "truncated literal")
        XCTAssertThrowsError(try DICOMRLECodec.decodeSegment([0x03, 1, 2, 3, 4][...], length: 3), "literal overflow")
        XCTAssertThrowsError(try DICOMRLECodec.decodeSegment([0xFC, 1][...], length: 3), "replicate overflow")
        XCTAssertThrowsError(try DICOMRLECodec.decodeSegment([0xFF, 1][...], length: 3), "segment ends early")
    }

    func testHandEncodedRLEFrames() throws {
        // 2x2 MONOCHROME2: rows [5, 5] and [5, 7].
        let mono = description(rows: 2, columns: 2)
        let monoFrame = rleFrame([[0xFF, 5, 0x01, 5, 7, 0x00]])
        XCTAssertEqual(try decodeStored(monoFrame, mono), [5, 5, 5, 7])

        // 16-bit: segment 1 holds the most significant bytes.
        let wide = description(columns: 2, bitsAllocated: 16, bitsStored: 16)
        let wideFrame = rleFrame([[0x01, 0x12, 0xAB, 0x00], [0x01, 0x34, 0xCD, 0x00]])
        XCTAssertEqual(try decodeStored(wideFrame, wide), [0x1234, 0xABCD])

        // RGB: one segment per color, returned pixel by pixel.
        let rgb = description(columns: 2, samples: 3, photometric: .rgb)
        let rgbFrame = rleFrame([[0x01, 10, 11, 0x00], [0x01, 20, 21, 0x00], [0x01, 30, 31, 0x00]])
        XCTAssertEqual(try decodeStored(rgbFrame, rgb), [10, 20, 30, 11, 21, 31])

        XCTAssertThrowsError(try DICOMRLECodec().decode(rleFrame([[0x01, 1, 2, 0x00]]), description: rgb)) {
            XCTAssertEqual($0 as? DICOMCodecError, .corruptedData("1 RLE segments for 3 expected"))
        }
    }

    func testRLEEncoderRunsFollowAnnexG() {
        var output: [UInt8] = []
        // Three identical bytes are a replicate run; a pair after a literal
        // stays literal.
        DICOMRLECodec.encodeRow([7, 7, 7, 1, 2, 2, 3][...], into: &output)
        XCTAssertEqual(output, [0xFE, 7, 0x03, 1, 2, 2, 3])

        output = []
        DICOMRLECodec.encodeRow(ArraySlice(repeating: 4, count: 130), into: &output)
        XCTAssertEqual(output, [0x81, 4, 0xFF, 4])
    }

    func testRLERoundTripsEveryLayout() throws {
        var generator = SplitMix(seed: 42)
        let layouts: [(DICOMPixelDescription, String)] = [
            (description(rows: 5, columns: 7), "8-bit"),
            (description(rows: 3, columns: 9, bitsAllocated: 16, bitsStored: 12, signed: true), "16-bit signed"),
            (description(rows: 4, columns: 4, bitsAllocated: 32, bitsStored: 32), "32-bit"),
            (description(rows: 3, columns: 5, samples: 3, photometric: .rgb), "RGB by pixel"),
            (description(rows: 3, columns: 5, samples: 3, photometric: .rgb, planar: 1), "RGB by plane"),
            (description(rows: 3, columns: 5, bitsAllocated: 1, bitsStored: 1), "1-bit"),
        ]
        let codec = DICOMRLECodec()
        for (layout, name) in layouts {
            let frameBytes = (layout.bitsPerFrame + 7) / 8
            // Runs and noise, so both run kinds are exercised.
            var native = (0..<frameBytes).map { $0 % 11 < 6 ? UInt8(0x5A) : UInt8(truncatingIfNeeded: generator.next()) }
            if layout.bitsAllocated == 1, layout.bitsPerFrame % 8 != 0 {
                native[native.count - 1] &= UInt8((1 << (layout.bitsPerFrame % 8)) - 1)
            }
            let encoded = try codec.encode(Data(native), description: layout)
            XCTAssertEqual(encoded.count % 2, 0, name)
            let decoded = try codec.decode(encoded, description: layout)
            XCTAssertEqual([UInt8](decoded.data), native, name)
        }
    }

    // MARK: Frame assembly (PS3.5 A.4)

    func testBasicOffsetTableFromAnnexG6() throws {
        // Three RLE frames of 02C8H, 036AH, and 0BC8H bytes; the Basic Offset
        // Table lists 0, 02D0H, and 0642H.
        let lengths = [0x2C8, 0x36A, 0xBC8]
        let fragments = lengths.enumerated().map { Data(repeating: UInt8($0.offset + 1), count: $0.element) }
        let dataset = encapsulatedImage(frames: 3, fragments: fragments, offsetTable: [0, 0x2D0, 0x642])
        let pixels = try DICOMEncapsulatedPixelData(dataset: dataset)
        for frame in 0..<3 {
            XCTAssertEqual(try pixels.encodedFrame(frame), fragments[frame])
        }
        XCTAssertThrowsError(try pixels.encodedFrame(3))
    }

    func testFramesSpanningFragmentsAndOffsetTableErrors() throws {
        let parts = [Data([1, 2]), Data([3, 4]), Data([5, 6])]
        // Frame 0 spans the first two Fragments.
        let spanning = encapsulatedImage(frames: 2, fragments: parts, offsetTable: [0, 20])
        XCTAssertEqual(try DICOMEncapsulatedPixelData(dataset: spanning).encodedFrame(0), Data([1, 2, 3, 4]))
        XCTAssertEqual(try DICOMEncapsulatedPixelData(dataset: spanning).encodedFrame(1), Data([5, 6]))

        // Without an offset table a single frame uses every Fragment.
        let single = encapsulatedImage(frames: 1, fragments: parts, offsetTable: [])
        XCTAssertEqual(try DICOMEncapsulatedPixelData(dataset: single).encodedFrame(0), Data([1, 2, 3, 4, 5, 6]))

        for offsets: [UInt32] in [[0, 12], [4, 10], [10, 0]] {
            XCTAssertThrowsError(try DICOMEncapsulatedPixelData(
                dataset: encapsulatedImage(frames: 2, fragments: parts, offsetTable: offsets)), "\(offsets)")
        }
        // Two frames in three Fragments cannot be located without a table.
        XCTAssertThrowsError(try DICOMEncapsulatedPixelData(
            dataset: encapsulatedImage(frames: 2, fragments: parts, offsetTable: [])))
    }

    func testExtendedOffsetTableExcludesFragmentPadding() throws {
        let fragments = [Data([1, 2, 3, 0]), Data([4, 5])]
        let dataset = encapsulatedImage(frames: 2, fragments: fragments, offsetTable: [])
        addOV("ExtendedOffsetTable", [0, 12], to: dataset)
        addOV("ExtendedOffsetTableLengths", [3, 2], to: dataset)
        let pixels = try DICOMEncapsulatedPixelData(dataset: dataset)
        XCTAssertEqual(try pixels.encodedFrame(0), Data([1, 2, 3]))
        XCTAssertEqual(try pixels.encodedFrame(1), Data([4, 5]))

        let wrong = encapsulatedImage(frames: 2, fragments: fragments, offsetTable: [])
        addOV("ExtendedOffsetTable", [0, 8], to: wrong)
        addOV("ExtendedOffsetTableLengths", [3, 2], to: wrong)
        XCTAssertThrowsError(try DICOMEncapsulatedPixelData(dataset: wrong))
    }

    // MARK: Rendering encapsulated images

    func testRLEImageRendersAfterAPart10RoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: url) }

        let layout = description(rows: 2, columns: 3, bitsAllocated: 16, bitsStored: 12, frames: 2)
        let frames = [[0, 100, 200, 300, 400, 4095], [4095, 0, 1, 2, 3, 4]].map { values in
            values.reduce(into: Data()) { $0.append(contentsOf: [UInt8($1 & 0xFF), UInt8($1 >> 8)]) }
        }
        let encoded = try frames.map { try DICOMRLECodec().encode($0, description: layout) }
        let source = encapsulatedImage(frames: 2, rows: 2, columns: 3, bitsAllocated: 16, bitsStored: 12,
                                       fragments: encoded, offsetTable: [0, UInt32(8 + encoded[0].count)])
        source.hasPreamble = true
        _ = source.set(value: "1.2.826.0.1.3680043.10.999", forTagName: "ImplementationClassUID")
        XCTAssertTrue(try DicomOutputStream(url: url).write(dataset: source))

        let decoded = try XCTUnwrap(try DicomInputStream(url: url).readDataset())
        XCTAssertEqual(decoded.transferSyntax.tsUID, DICOMRLECodec.transferSyntaxUID)
        let renderer = try DICOMImageRenderer(dataset: decoded)
        XCTAssertNil(renderer.pixelData)
        XCTAssertEqual(try renderer.storedValues(frame: 1), [4095, 0, 1, 2, 3, 4])
        XCTAssertEqual(try renderer.render(frame: 0).pixels, [0, 6, 12, 19, 25, 255])
        XCTAssertTrue(decoded.transferSyntax.capability.canDecodePixelData)
    }

    func testDeflatedImageFrameCompressionRoundTrips() throws {
        let codec = DICOMDeflatedFrameCodec()
        let frames = [Data([0, 1, 2, 3, 4, 5]), Data([5, 4, 3, 2, 1, 0])]
        let encoded = try frames.map { try codec.encode($0) }
        XCTAssertTrue(encoded.allSatisfy { $0.count % 2 == 0 })
        let dataset = encapsulatedImage(frames: 2, rows: 2, columns: 3, fragments: encoded, offsetTable: [],
                                        transferSyntax: DICOMDeflatedFrameCodec.transferSyntaxUID)
        let renderer = try DICOMImageRenderer(dataset: dataset)
        XCTAssertEqual(try renderer.storedValues(frame: 1), [5, 4, 3, 2, 1, 0])

        let short = description(rows: 2, columns: 4)
        XCTAssertThrowsError(try codec.decode(encoded[0], description: short)) {
            XCTAssertEqual($0 as? DICOMCodecError, .corruptedData("inflated frame holds 6 of 8 bytes"))
        }
    }

    func testRegisteredDecodersTakePrecedence() throws {
        struct ConstantDecoder: DICOMPixelDataDecoder {
            var transferSyntaxUIDs: Set<String> { ["1.2.840.10008.1.2.4.100"] }
            func decode(_ encodedFrame: Data, description: DICOMPixelDescription) throws -> DICOMDecodedFrame {
                DICOMDecodedFrame(description: description.decodedFrame(),
                                  data: Data(repeating: 9, count: description.pixelsPerFrame))
            }
        }
        let mpeg = encapsulatedImage(frames: 1, rows: 1, columns: 2, fragments: [Data([0, 0])], offsetTable: [],
                                     transferSyntax: "1.2.840.10008.1.2.4.100")
        XCTAssertThrowsError(try DICOMImageRenderer(dataset: mpeg))
        DICOMCodecRegistry.register(ConstantDecoder())
        XCTAssertEqual(try DICOMImageRenderer(dataset: mpeg).storedValues(), [9, 9])
    }

    // MARK: Fixtures

    private func description(
        rows: Int = 1, columns: Int, bitsAllocated: Int = 8, bitsStored: Int = 8, signed: Bool = false,
        samples: Int = 1, photometric: DICOMPhotometricInterpretation = .monochrome2, planar: Int = 0,
        frames: Int = 1
    ) -> DICOMPixelDescription {
        DICOMPixelDescription(
            rows: rows, columns: columns, samplesPerPixel: samples, photometricInterpretation: photometric,
            bitsAllocated: bitsAllocated, bitsStored: bitsStored, highBit: bitsStored - 1, isSigned: signed,
            planarConfiguration: planar, numberOfFrames: frames)
    }

    private func rleFrame(_ segments: [[UInt8]]) -> Data {
        var header = [UInt8](repeating: 0, count: 64)
        func put(_ value: Int, at offset: Int) {
            for byte in 0..<4 { header[offset + byte] = UInt8((value >> (8 * byte)) & 0xFF) }
        }
        put(segments.count, at: 0)
        var offset = 64
        for (index, segment) in segments.enumerated() {
            put(offset, at: 4 * (index + 1))
            offset += segment.count
        }
        return Data(header + segments.flatMap { $0 })
    }

    private func decodeStored(_ frame: Data, _ layout: DICOMPixelDescription) throws -> [Int64] {
        let decoded = try DICOMRLECodec().decode(frame, description: layout)
        return try DICOMNativePixelData(description: decoded.description, decodedFrames: decoded.data)
            .storedValues(frame: 0)
    }

    private func encapsulatedImage(
        frames: Int, rows: Int = 1, columns: Int = 1, bitsAllocated: Int = 8, bitsStored: Int = 8,
        fragments: [Data], offsetTable: [UInt32],
        transferSyntax: String = DICOMRLECodec.transferSyntaxUID
    ) -> DataSet {
        let dataset = DataSet()
        dataset.transferSyntax = TransferSyntax(transferSyntax)
        _ = dataset.set(value: UInt16(rows), forTagName: "Rows")
        _ = dataset.set(value: UInt16(columns), forTagName: "Columns")
        _ = dataset.set(value: UInt16(1), forTagName: "SamplesPerPixel")
        _ = dataset.set(value: "MONOCHROME2", forTagName: "PhotometricInterpretation")
        _ = dataset.set(value: UInt16(bitsAllocated), forTagName: "BitsAllocated")
        _ = dataset.set(value: UInt16(bitsStored), forTagName: "BitsStored")
        _ = dataset.set(value: UInt16(bitsStored - 1), forTagName: "HighBit")
        _ = dataset.set(value: UInt16(0), forTagName: "PixelRepresentation")
        _ = dataset.set(value: String(frames), forTagName: "NumberOfFrames")

        let sequence = PixelSequence(withTag: DataTag(withGroup: "7fe0", element: "0010"))
        sequence.vr = .OB
        sequence.length = -1
        let table = offsetTable.reduce(into: Data()) { data, offset in
            data.append(contentsOf: (0..<4).map { UInt8((offset >> (8 * $0)) & 0xFF) })
        }
        for value in [table] + fragments {
            let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
            item.data = value
            item.length = value.count
            sequence.items.append(item)
        }
        dataset.add(element: sequence)
        return dataset
    }

    private func addOV(_ name: String, _ values: [UInt64], to dataset: DataSet) {
        let element = DataElement(withTagName: name, dataset: dataset)!
        element.vr = .OV
        element.data = values.reduce(into: Data()) { data, value in
            data.append(contentsOf: (0..<8).map { UInt8((value >> (8 * UInt64($0))) & 0xFF) })
        }
        element.length = values.count * 8
        dataset.add(element: element)
    }
}

/// Deterministic pseudo-random bytes for round-trip tests.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
