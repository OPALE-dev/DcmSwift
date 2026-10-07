import XCTest
@testable import DcmSwift

/// JPEG XL fixtures encoded and independently decoded by imagecodecs 2026.8.16
/// with libjxl 0.12.0. They cover raw codestream and container signatures,
/// grayscale and RGB, byte- and word-sized lossless samples, lossy coding,
/// and reversible JPEG recompression decoded to pixels.
final class DcmSwiftJPEGXLTests: XCTestCase {
    private struct Fixture: Decodable {
        let name: String
        let rows: Int
        let columns: Int
        let samples: Int
        let bits: Int
        let signed: Bool
        let container: Bool
    }

    private func resource(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "jpegxl-\(name)", withExtension: ext)))
    }

    private func description(_ fixture: Fixture) -> DICOMPixelDescription {
        DICOMPixelDescription(
            rows: fixture.rows, columns: fixture.columns, samplesPerPixel: fixture.samples,
            photometricInterpretation: fixture.samples == 3 ? .rgb : .monochrome2,
            bitsAllocated: fixture.bits > 8 ? 16 : 8, bitsStored: fixture.bits,
            highBit: fixture.bits - 1, isSigned: fixture.signed, planarConfiguration: 0,
            numberOfFrames: 1, isEncapsulated: true)
    }

    func testDecodingMatchesLibjxlOracle() throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: resource("cases", "json"))
        XCTAssertEqual(fixtures.count, 5)
        for fixture in fixtures {
            let decoded = try DICOMJPEGXLCodec().decode(
                try resource(fixture.name, "jxl"), description: description(fixture))
            XCTAssertEqual(decoded.data, try resource(fixture.name, "raw"), fixture.name)
            XCTAssertEqual(decoded.description.planarConfiguration, 0, fixture.name)
            XCTAssertEqual(decoded.description.photometricInterpretation,
                           fixture.samples == 3 ? .rgb : .monochrome2, fixture.name)
        }
    }

    func testCapabilitiesAndRegistry() throws {
        for uid in [DICOMJPEGXLCodec.lossless, DICOMJPEGXLCodec.jpegRecompression, DICOMJPEGXLCodec.general] {
            XCTAssertTrue(DICOMCodecRegistry.decoder(for: uid) is DICOMJPEGXLCodec, uid)
            let capability = try XCTUnwrap(TransferSyntax(uid)).capability
            XCTAssertTrue(capability.canDecodePixelData, uid)
            XCTAssertFalse(capability.canEncodePixelData, uid)
        }
    }

    func testMalformedAndInconsistentFramesAreRejected() throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: resource("cases", "json"))
        let fixture = try XCTUnwrap(fixtures.first)
        let frame = try resource(fixture.name, "jxl")
        XCTAssertThrowsError(try DICOMJPEGXLCodec().decode(Data(frame.prefix(1)), description: description(fixture)))
        XCTAssertThrowsError(try DICOMJPEGXLCodec().decode(Data(frame.dropLast(8)), description: description(fixture)))

        let wrongSize = DICOMPixelDescription(
            rows: fixture.rows + 1, columns: fixture.columns, samplesPerPixel: fixture.samples,
            photometricInterpretation: .monochrome2, bitsAllocated: 8, bitsStored: 8,
            highBit: 7, isSigned: false, planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: true)
        XCTAssertThrowsError(try DICOMJPEGXLCodec().decode(frame, description: wrongSize))

        let signed = DICOMPixelDescription(
            rows: fixture.rows, columns: fixture.columns, samplesPerPixel: fixture.samples,
            photometricInterpretation: .monochrome2, bitsAllocated: 8, bitsStored: 8,
            highBit: 7, isSigned: true, planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: true)
        XCTAssertThrowsError(try DICOMJPEGXLCodec().decode(frame, description: signed))
    }

    func testDicomFragmentPaddingIsIgnored() throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: resource("cases", "json"))
        let fixture = try XCTUnwrap(fixtures.first { $0.name == "gray12-codestream" })
        var padded = try resource(fixture.name, "jxl")
        XCTAssertEqual(padded.count % 2, 1)
        padded.append(0)
        let decoded = try DICOMJPEGXLCodec().decode(padded, description: description(fixture))
        XCTAssertEqual(decoded.data, try resource(fixture.name, "raw"))
    }
}
