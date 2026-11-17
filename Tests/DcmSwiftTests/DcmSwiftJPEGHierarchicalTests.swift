import XCTest
@testable import DcmSwift

/// JPEG hierarchical decoding (ITU-T T.81 Annex J). The fixtures were
/// encoded by the ISO reference implementation (Thomas Richter's libjpeg,
/// `jpeg -y`), and each `.ref` file holds that implementation's decoding.
///
/// The reference computes in fixed point with extra fraction bits, so its
/// inverse DCT, color conversion, and two-dimensional upsampling round
/// slightly differently from T.81 J.1.1.2 and the IJG algorithms DcmSwift
/// uses. Each case therefore states the largest and mean absolute sample
/// differences it accepts; structural errors exceed them by far.
final class DcmSwiftJPEGHierarchicalTests: XCTestCase {

    private struct Fixture: Decodable {
        let name: String
        let transferSyntax: String
        let comps: Int
        let maxError: Int
        let meanError: Double
    }

    private func fixtures() throws -> [Fixture] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "jpeg-hierarchical-cases", withExtension: "json"))
        return try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
    }

    private func resource(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "jpeg-hier-\(name)", withExtension: ext)))
    }

    private func description(samples: Int, rows: Int = 37, columns: Int = 45) -> DICOMPixelDescription {
        DICOMPixelDescription(
            rows: rows, columns: columns, samplesPerPixel: samples,
            photometricInterpretation: samples == 3 ? .ybrFull422 : .monochrome2,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false, planarConfiguration: 0,
            numberOfFrames: 1, isEncapsulated: true)
    }

    func testDecodingMatchesTheISOReferenceWithinTolerance() throws {
        let fixtures = try fixtures()
        XCTAssertEqual(fixtures.count, 10)
        for fixture in fixtures {
            let decoder = try XCTUnwrap(DICOMCodecRegistry.decoder(for: fixture.transferSyntax), fixture.name)
            XCTAssertTrue(decoder is DICOMJPEGHierarchicalCodec, fixture.name)
            let decoded = try decoder.decode(try resource(fixture.name, "jpg"), description: description(samples: fixture.comps))
            let reference = try resource(fixture.name, "ref")
            XCTAssertEqual(decoded.data.count, reference.count, fixture.name)
            let errors = zip(decoded.data, reference).map { abs(Int($0) - Int($1)) }
            let mean = Double(errors.reduce(0, +)) / Double(max(errors.count, 1))
            XCTAssertLessThanOrEqual(errors.max() ?? 0, fixture.maxError, fixture.name)
            XCTAssertLessThanOrEqual(mean, fixture.meanError, fixture.name)
            // Only streams with a DCT frame are converted from YCbCr; purely
            // lossless ones keep the described photometric interpretation.
            let lossless = fixture.name.contains("sof3_") || fixture.name.contains("sof11_")
            XCTAssertEqual(decoded.description.photometricInterpretation,
                           fixture.comps == 1 ? .monochrome2 : (lossless ? .ybrFull422 : .rgb), fixture.name)
        }
    }

    func testEveryHierarchicalSyntaxIsDecodable() throws {
        let uids = (59...66).map { "1.2.840.10008.1.2.4.\($0)" }
        XCTAssertEqual(Set(uids), DICOMJPEGHierarchicalCodec().transferSyntaxUIDs)
        for uid in uids {
            XCTAssertTrue(DicomSpec.shared.isKnown(transferSyntax: uid), uid)
            XCTAssertTrue(try XCTUnwrap(TransferSyntax(uid)).capability.canDecodePixelData, uid)
            XCTAssertFalse(try XCTUnwrap(TransferSyntax(uid)).capability.canEncodePixelData, uid)
        }
    }

    func testNonHierarchicalDecodersDelegateHierarchicalStreams() throws {
        let gray = try resource("gray_sof1_sof5", "jpg")
        let expected = try DICOMJPEGHierarchicalCodec().decode(gray, description: description(samples: 1))
        XCTAssertEqual(try DICOMJPEGBaselineCodec().decode(gray, description: description(samples: 1)).data,
                       expected.data)
        let lossless = try resource("gray_sof11_sof15", "jpg")
        XCTAssertEqual(try DICOMJPEGLosslessCodec().decode(lossless, description: description(samples: 1)).data,
                       try DICOMJPEGHierarchicalCodec().decode(lossless, description: description(samples: 1)).data)
    }

    func testSingleFrameStreamsUnderHierarchicalSyntaxesStillDecode() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "jpeg-gray_23x17_q50", withExtension: "jpg"))
        let stream = try Data(contentsOf: url)
        let decoded = try DICOMJPEGHierarchicalCodec().decode(stream, description: description(samples: 1, rows: 17, columns: 23))
        XCTAssertEqual(decoded.data, try Data(contentsOf: XCTUnwrap(
            Bundle.module.url(forResource: "jpeg-gray_23x17_q50", withExtension: "ref"))))
    }

    func testMalformedStreamsAreRejectedWithoutCrashing() throws {
        let codec = DICOMJPEGHierarchicalCodec()
        let stream = try resource("color_sof10_sof14x2", "jpg")
        XCTAssertThrowsError(try codec.decode(stream, description: description(samples: 3, rows: 36)))
        XCTAssertThrowsError(try codec.decode(stream, description: description(samples: 1)))
        for length in stride(from: 4, to: stream.count, by: 13) {
            _ = try? codec.decode(stream.prefix(length), description: description(samples: 3))
        }
        // A corrupted EXP marker (expansion factor 2) is invalid.
        var bytes = [UInt8](stream)
        let exp = try XCTUnwrap((0..<(bytes.count - 4)).first { bytes[$0] == 0xFF && bytes[$0 + 1] == 0xDF })
        bytes[exp + 4] = 0x21
        XCTAssertThrowsError(try codec.decode(Data(bytes), description: description(samples: 3)))
        // Removing the expansion leaves a reference of the wrong size.
        bytes[exp + 4] = 0x00
        XCTAssertThrowsError(try codec.decode(Data(bytes), description: description(samples: 3)))
    }
}
