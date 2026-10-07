import XCTest
@testable import DcmSwift

/// JPEG 2000 Part 2 multi-component image compression (PS3.5 A.4.4, 10.6;
/// ISO/IEC 15444-2 Annex J): Transfer Syntaxes 1.2.840.10008.1.2.4.92/93.
///
/// Every `jpeg2000-part2-*` codestream was decoded by Kakadu 8.4.1
/// (`kdu_expand`), an implementation independent of this one, which wrote
/// the `.raw` references. The wavelet and matrix cases were encoded by
/// `kdu_compress`; the dependency, multi-stage, extra-output, and
/// tile-override cases (which `kdu_compress` cannot write) carry hand-built
/// Annex J segments injected into Kakadu Part 1 codestreams.
/// `dep-rev-split` splits its MCT and MCC series over several segments with
/// 16-bit component indices, which Kakadu does not read: its reference is
/// the source volume, losslessly reconstructed.
final class DcmSwiftJPEG2000Part2Tests: XCTestCase {

    private struct Fixture: Decodable {
        let name: String
        let frames: Int
        let rows: Int
        let columns: Int
        let samples: Int
        let bits: Int
        let signed: Bool
        let tolerance: Int
    }

    private func resource(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "jpeg2000-part2-\(name)", withExtension: ext)))
    }

    private func fixtures() throws -> [Fixture] {
        try JSONDecoder().decode([Fixture].self, from: resource("cases", "json"))
    }

    private func description(_ fixture: Fixture, frames: Int = 1) -> DICOMPixelDescription {
        DICOMPixelDescription(
            rows: fixture.rows, columns: fixture.columns, samplesPerPixel: fixture.samples,
            photometricInterpretation: fixture.samples == 3 ? .rgb : .monochrome2,
            bitsAllocated: fixture.bits > 8 ? 16 : 8, bitsStored: fixture.bits, highBit: fixture.bits - 1,
            isSigned: fixture.signed, planarConfiguration: 0, numberOfFrames: frames, isEncapsulated: true)
    }

    /// Stored values: the low `bits` of each cell, sign-extended if signed.
    private func values(_ data: Data, bits: Int, signed: Bool) -> [Int] {
        let bytes = [UInt8](data)
        let cells = bits > 8
            ? stride(from: 0, to: bytes.count - 1, by: 2).map { Int(bytes[$0]) | Int(bytes[$0 + 1]) << 8 }
            : bytes.map(Int.init)
        let mask = (1 << bits) - 1
        return cells.map { cell in
            let value = cell & mask
            return signed && value >> (bits - 1) == 1 ? value - (mask + 1) : value
        }
    }

    private func maximumDifference(_ a: [Int], _ b: [Int]) -> Int {
        zip(a, b).map { abs($0 - $1) }.max() ?? 0
    }

    func testDecodingMatchesKakadu() throws {
        let fixtures = try fixtures()
        XCTAssertEqual(fixtures.count, 14)
        for fixture in fixtures {
            let frames = try DICOMJPEG2000Codec().decodeCollection(
                resource(fixture.name, "j2c"), description: description(fixture))
            XCTAssertEqual(frames.count, fixture.frames, fixture.name)
            let actual = frames.flatMap { values($0.data, bits: fixture.bits, signed: fixture.signed) }
            let expected = values(try resource(fixture.name, "raw"), bits: fixture.bits, signed: fixture.signed)
            XCTAssertEqual(actual.count, expected.count, fixture.name)
            XCTAssertLessThanOrEqual(maximumDifference(actual, expected), fixture.tolerance, fixture.name)
            XCTAssertEqual(frames.first?.description.numberOfFrames, 1, fixture.name)
        }
    }

    func testSingleFrameCodestreamsDecodeAsFrames() throws {
        let fixture = try XCTUnwrap(fixtures().first { $0.name == "matrix-rct" })
        let codec = try XCTUnwrap(DICOMCodecRegistry.decoder(for: DICOMJPEG2000Codec.partTwoLossless))
        let encoded = try resource(fixture.name, "j2c")
        // The DICOM image may declare the transform's color space; the
        // decoded frame is RGB.
        var ybr = description(fixture)
        ybr = DICOMPixelDescription(
            rows: ybr.rows, columns: ybr.columns, samplesPerPixel: 3, photometricInterpretation: .ybrRCT,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false, planarConfiguration: 0,
            numberOfFrames: 1, isEncapsulated: true)
        let frame = try codec.decode(encoded, description: ybr)
        XCTAssertEqual(frame.description.photometricInterpretation, .rgb)
        XCTAssertEqual(values(frame.data, bits: 8, signed: false),
                       values(try resource(fixture.name, "raw"), bits: 8, signed: false))

        // A codestream holding several frames is not one frame.
        let volume = try XCTUnwrap(fixtures().first { $0.name == "dwt53-6f" })
        XCTAssertThrowsError(try codec.decode(resource(volume.name, "j2c"), description: description(volume)))
        // Its components must fill whole frames.
        let rgb = DICOMPixelDescription(
            rows: volume.rows, columns: volume.columns, samplesPerPixel: 3, photometricInterpretation: .rgb,
            bitsAllocated: 16, bitsStored: 12, highBit: 11, isSigned: false, planarConfiguration: 0,
            numberOfFrames: 1, isEncapsulated: true)
        XCTAssertNoThrow(try DICOMJPEG2000Codec().decodeCollection(resource(volume.name, "j2c"), description: rgb))
        let seven = try XCTUnwrap(fixtures().first { $0.name == "dwt53-7f-odd" })
        XCTAssertThrowsError(try DICOMJPEG2000Codec().decodeCollection(
            resource(seven.name, "j2c"),
            description: DICOMPixelDescription(
                rows: seven.rows, columns: seven.columns, samplesPerPixel: 3, photometricInterpretation: .rgb,
                bitsAllocated: 16, bitsStored: 12, highBit: 11, isSigned: false, planarConfiguration: 0,
                numberOfFrames: 1, isEncapsulated: true)))
    }

    /// Frames are components of component collections; each Fragment holds
    /// data of one collection, which may span several Fragments (PS3.5
    /// A.4.4).
    func testMultiFrameImagesDecodeByComponentCollection() throws {
        let fixtures = try fixtures()
        let first = try XCTUnwrap(fixtures.first { $0.name == "dwt53-6f" })
        let second = try XCTUnwrap(fixtures.first { $0.name == "dwt53-2f" })
        let a = try resource(first.name, "j2c"), b = try resource(second.name, "j2c")
        let expected = [first, second].flatMap { fixture -> [[Int]] in
            let samples = values(try! resource(fixture.name, "raw"), bits: 12, signed: false)
            let size = fixture.rows * fixture.columns
            return (0..<fixture.frames).map { Array(samples[($0 * size)..<(($0 + 1) * size)]) }
        }

        // The first collection spans three Fragments, the second one.
        func evenSplit(_ data: Data, _ parts: Int) -> [Data] {
            let step = (data.count / parts) & ~1
            return (0..<parts).map { part in
                data.subdata(in: (part * step)..<(part == parts - 1 ? data.count : (part + 1) * step))
            }
        }
        for uid in [DICOMJPEG2000Codec.partTwoLossless, DICOMJPEG2000Codec.partTwo] {
            let dataset = encapsulatedImage(
                frames: 8, rows: first.rows, columns: first.columns,
                fragments: evenSplit(a, 3) + [b.count % 2 == 0 ? b : b + Data([0])], transferSyntax: uid)
            let pixels = try DICOMEncapsulatedPixelData(dataset: dataset)
            // Out of order, crossing collections both ways.
            for frame in [7, 0, 5, 6, 1, 2, 3, 4] {
                let decoded = try pixels.decodedFrame(frame)
                XCTAssertEqual(values(decoded.data, bits: 12, signed: false), expected[frame], "\(uid) \(frame)")
            }
            XCTAssertThrowsError(try pixels.decodedFrame(8))
            XCTAssertThrowsError(try pixels.encodedFrame(0))

            let image = try DICOMImageRenderer(dataset: dataset)
            XCTAssertEqual(try image.storedValues(frame: 6).map(Int.init), expected[6])
        }

        // More frames declared than the collections hold.
        let short = encapsulatedImage(
            frames: 9, rows: first.rows, columns: first.columns, fragments: [a, b + Data([0])],
            transferSyntax: DICOMJPEG2000Codec.partTwoLossless)
        XCTAssertThrowsError(try DICOMEncapsulatedPixelData(dataset: short).decodedFrame(8))
        // Fragments that do not start with a codestream cannot be grouped.
        let shifted = encapsulatedImage(
            frames: 8, rows: first.rows, columns: first.columns, fragments: [Data([0, 0]), a, b + Data([0])],
            transferSyntax: DICOMJPEG2000Codec.partTwoLossless)
        XCTAssertThrowsError(try DICOMEncapsulatedPixelData(dataset: shifted))
    }

    func testCapabilitiesAndRegistry() throws {
        for uid in [DICOMJPEG2000Codec.partTwoLossless, DICOMJPEG2000Codec.partTwo] {
            XCTAssertTrue(DICOMCodecRegistry.decoder(for: uid) is DICOMJPEG2000Codec, uid)
            let capability = try XCTUnwrap(TransferSyntax(uid)).capability
            XCTAssertTrue(capability.canDecodePixelData, uid)
            XCTAssertFalse(capability.canEncodePixelData, uid)
        }
        XCTAssertEqual(DICOMEncapsulatedPixelData.collectionTransferSyntaxUIDs,
                       [DICOMJPEG2000Codec.partTwoLossless, DICOMJPEG2000Codec.partTwo])
    }

    /// Marker segment offsets of a main header, by marker code.
    private func mainHeaderSegments(_ bytes: [UInt8]) -> [UInt8: [Int]] {
        var segments: [UInt8: [Int]] = [:]
        var position = 2
        while position + 4 <= bytes.count, bytes[position] == 0xFF, bytes[position + 1] != 0x90 {
            segments[bytes[position + 1], default: []].append(position)
            position += 2 + (Int(bytes[position + 2]) << 8 | Int(bytes[position + 3]))
        }
        return segments
    }

    func testCodestreamsOutsideTheDICOMProfileAreRejected() throws {
        let fixture = try XCTUnwrap(fixtures().first { $0.name == "dwt53-6f" })
        let stream = [UInt8](try resource(fixture.name, "j2c"))
        let segments = mainHeaderSegments(stream)
        let codec = DICOMJPEG2000Codec()
        func decode(_ bytes: [UInt8]) throws {
            _ = try codec.decodeCollection(Data(bytes), description: description(fixture))
        }

        // Part 2 capabilities other than the multiple component transform.
        var rsiz = stream
        rsiz[7] |= 0x02
        XCTAssertThrowsError(try decode(rsiz)) {
            guard case .unsupportedImage = $0 as? DICOMCodecError else { return XCTFail("\($0)") }
        }
        // Arbitrary transformation kernels (ATK) in the wavelet collection.
        let mcc = try XCTUnwrap(segments[0x75]?.first)
        let length = Int(stream[mcc + 2]) << 8 | Int(stream[mcc + 3])
        var kernel = stream
        // Tmcc ends 4 bytes (Omcc) before the end of the single record.
        kernel[mcc + 2 + length - 5] = 2
        XCTAssertThrowsError(try decode(kernel)) {
            guard case .corruptedData(let reason) = $0 as? DICOMCodecError else { return XCTFail("\($0)") }
            XCTAssertTrue(reason.contains("arbitrary transformation kernels"), reason)
        }
        // An MCO stage without its MCC segment.
        let mco = try XCTUnwrap(segments[0x77]?.first)
        var missing = stream
        missing[mco + 5] ^= 0x40
        XCTAssertThrowsError(try decode(missing))
        // No CBD segment.
        let cbd = try XCTUnwrap(segments[0x78]?.first)
        var withoutCBD = stream
        withoutCBD[cbd + 1] = 0x64
        XCTAssertThrowsError(try decode(withoutCBD))
        // An offset array of the wrong size.
        let mct = try XCTUnwrap(segments[0x74]?.first)
        var shortArray = stream
        shortArray.replaceSubrange((mct + 2)..<(mct + 4), with: [0x00, 0x1C])
        shortArray.replaceSubrange((mct + 30)..<(mct + 34), with: [0xFF, 0x64, 0x00, 0x02])
        XCTAssertThrowsError(try decode(shortArray))
    }

    func testMalformedStreamsAreRejectedWithoutCrashing() throws {
        let fixture = try XCTUnwrap(fixtures().first { $0.name == "two-stages" })
        let stream = try resource(fixture.name, "j2c")
        let codec = DICOMJPEG2000Codec()
        for length in stride(from: 2, to: stream.count, by: 53) {
            _ = try? codec.decodeCollection(stream.prefix(length), description: description(fixture))
        }
        var bytes = [UInt8](stream)
        for index in stride(from: 4, to: min(bytes.count, 400), by: 7) {
            let original = bytes[index]
            bytes[index] ^= 0x5A
            _ = try? codec.decodeCollection(Data(bytes), description: description(fixture))
            bytes[index] = original
        }
    }

    private func encapsulatedImage(
        frames: Int, rows: Int, columns: Int, fragments: [Data], transferSyntax: String
    ) -> DataSet {
        let dataset = DataSet()
        dataset.transferSyntax = TransferSyntax(transferSyntax)
        _ = dataset.set(value: UInt16(rows), forTagName: "Rows")
        _ = dataset.set(value: UInt16(columns), forTagName: "Columns")
        _ = dataset.set(value: UInt16(1), forTagName: "SamplesPerPixel")
        _ = dataset.set(value: "MONOCHROME2", forTagName: "PhotometricInterpretation")
        _ = dataset.set(value: UInt16(16), forTagName: "BitsAllocated")
        _ = dataset.set(value: UInt16(12), forTagName: "BitsStored")
        _ = dataset.set(value: UInt16(11), forTagName: "HighBit")
        _ = dataset.set(value: UInt16(0), forTagName: "PixelRepresentation")
        _ = dataset.set(value: String(frames), forTagName: "NumberOfFrames")

        let sequence = PixelSequence(withTag: DataTag(withGroup: "7fe0", element: "0010"))
        sequence.vr = .OB
        sequence.length = -1
        for value in [Data()] + fragments {
            let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
            item.data = value
            item.length = value.count
            sequence.items.append(item)
        }
        dataset.add(element: sequence)
        return dataset
    }
}
