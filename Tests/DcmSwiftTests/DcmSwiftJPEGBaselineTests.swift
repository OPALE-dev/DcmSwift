import XCTest
@testable import DcmSwift

/// JPEG Baseline, Extended, and Progressive decoding (ITU-T T.81 Annexes F
/// and G). The fixtures in CIResources were encoded by libjpeg-turbo
/// (imagecodecs 2026.8.16 and Pillow 12.3.0); each `.ref` file holds
/// libjpeg-turbo 3.2.0's decoding with its default settings, which DcmSwift
/// must reproduce exactly.
final class DcmSwiftJPEGBaselineTests: XCTestCase {

    private struct Fixture: Decodable {
        let name: String
        let rows: Int
        let cols: Int
        let comps: Int
        let precision: Int
    }

    private func fixtures() throws -> [Fixture] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "jpeg-baseline-cases", withExtension: "json"))
        return try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
    }

    private func resource(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "jpeg-\(name)", withExtension: ext)))
    }

    private func description(_ fixture: Fixture) -> DICOMPixelDescription {
        DICOMPixelDescription(
            rows: fixture.rows, columns: fixture.cols, samplesPerPixel: fixture.comps,
            photometricInterpretation: fixture.comps == 3 ? .ybrFull422 : .monochrome2,
            bitsAllocated: fixture.precision > 8 ? 16 : 8, bitsStored: fixture.precision,
            highBit: fixture.precision - 1, isSigned: false, planarConfiguration: 0, numberOfFrames: 1,
            isEncapsulated: true)
    }

    func testDecodingIsBitExactWithLibjpegTurbo() throws {
        let fixtures = try fixtures()
        XCTAssertEqual(fixtures.count, 15)
        for fixture in fixtures {
            let decoded = try DICOMJPEGBaselineCodec().decode(
                try resource(fixture.name, "jpg"), description: description(fixture))
            XCTAssertEqual(decoded.data, try resource(fixture.name, "ref"), fixture.name)
            XCTAssertEqual(decoded.description.photometricInterpretation,
                           fixture.comps == 3 ? .rgb : .monochrome2, fixture.name)
        }
    }

    func testEncapsulatedYBRImageRendersAsRGB() throws {
        let fixture = try XCTUnwrap(try fixtures().first { $0.name == "color_33x29_sub1" })
        let dataset = DataSet()
        dataset.transferSyntax = TransferSyntax(DICOMJPEGBaselineCodec.baseline)
        _ = dataset.set(value: UInt16(fixture.rows), forTagName: "Rows")
        _ = dataset.set(value: UInt16(fixture.cols), forTagName: "Columns")
        _ = dataset.set(value: UInt16(3), forTagName: "SamplesPerPixel")
        _ = dataset.set(value: "YBR_FULL_422", forTagName: "PhotometricInterpretation")
        _ = dataset.set(value: UInt16(0), forTagName: "PlanarConfiguration")
        for (name, value) in [("BitsAllocated", 8), ("BitsStored", 8), ("HighBit", 7), ("PixelRepresentation", 0)] {
            _ = dataset.set(value: UInt16(value), forTagName: name)
        }
        let sequence = PixelSequence(withTag: DataTag(withGroup: "7fe0", element: "0010"))
        sequence.vr = .OB
        sequence.length = -1
        var stream = try resource(fixture.name, "jpg")
        if stream.count % 2 == 1 { stream.append(0) }
        for value in [Data(), stream] {
            let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
            item.data = value
            item.length = value.count
            sequence.items.append(item)
        }
        dataset.add(element: sequence)

        let rendered = try DICOMImageRenderer(dataset: dataset).render()
        XCTAssertEqual(rendered.format, .rgb8)
        XCTAssertEqual(Data(rendered.pixels), try resource(fixture.name, "ref"))
    }

    func testInvalidStreamsAreRejected() throws {
        let fixture = try XCTUnwrap(try fixtures().first { $0.name == "gray_23x17_q50" })
        let stream = try resource(fixture.name, "jpg")
        let codec = DICOMJPEGBaselineCodec()

        let other = DICOMPixelDescription(
            rows: fixture.rows + 1, columns: fixture.cols, samplesPerPixel: 1, photometricInterpretation: .monochrome2,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false, planarConfiguration: 0, numberOfFrames: 1)
        XCTAssertThrowsError(try codec.decode(stream, description: other))

        // A lossless (SOF3) stream is not a DCT process.
        let lossless = DICOMPixelDescription(
            rows: 2, columns: 2, samplesPerPixel: 1, photometricInterpretation: .monochrome2,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false, planarConfiguration: 0, numberOfFrames: 1)
        let sof3 = try DICOMJPEGLosslessCodec().encode(Data([1, 2, 3, 4]), description: lossless)
        XCTAssertThrowsError(try codec.decode(sof3, description: lossless)) {
            XCTAssertEqual($0 as? DICOMCodecError, .unsupportedImage("SOF3 is not a DCT-based Huffman JPEG process"))
        }

        // Truncations and corrupted bytes fail or decode, but never crash.
        for length in stride(from: 2, to: stream.count, by: 5) {
            _ = try? codec.decode(stream.prefix(length), description: description(fixture))
        }
        var corrupted = [UInt8](stream)
        for index in stride(from: corrupted.count / 2, to: corrupted.count - 2, by: 3) { corrupted[index] ^= 0x5A }
        _ = try? codec.decode(Data(corrupted), description: description(fixture))
    }
}
