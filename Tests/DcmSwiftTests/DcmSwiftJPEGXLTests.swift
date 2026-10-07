import XCTest
@testable import DcmSwift

/// JPEG XL fixtures encoded and independently decoded by imagecodecs 2026.8.16
/// with libjxl 0.12.0. They cover raw codestream and container signatures,
/// grayscale and RGB, byte- and word-sized lossless samples, lossy coding,
/// and reversible JPEG recompression decoded to pixels.
///
/// The encoder is checked by round trips through this decoder (itself
/// qualified by the fixtures) and by JPEG reconstruction; imagecodecs also
/// decoded its lossless, lossy, and recompressed output identically and
/// rebuilt every recompressed JPEG bit for bit.
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
            XCTAssertTrue(capability.canEncodePixelData, uid)
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

    // MARK: Encoding

    private func frame(rows: Int, columns: Int, samples: Int, bits: Int, seed: UInt64 = 3) -> [Int] {
        var state = seed
        return (0..<(rows * columns * samples)).map { index in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let x = Double(index / samples % columns), y = Double(index / samples / columns)
            let smooth = (sin(x / 4) + cos(y / 3) + 2) / 4 * Double((1 << bits) - 1)
            return min(max(Int(smooth) + Int(state >> 61) - 4, 0), (1 << bits) - 1)
        }
    }

    private func bytes(_ values: [Int], bits: Int) -> Data {
        Data(values.flatMap { bits > 8 ? [UInt8($0 & 0xFF), UInt8($0 >> 8)] : [UInt8($0)] })
    }

    private func values(_ data: Data, bits: Int) -> [Int] {
        let raw = [UInt8](data)
        return bits > 8 ? stride(from: 0, to: raw.count - 1, by: 2).map { Int(raw[$0]) | Int(raw[$0 + 1]) << 8 }
            : raw.map(Int.init)
    }

    private func layout(
        rows: Int, columns: Int, samples: Int, bits: Int, photometric: DICOMPhotometricInterpretation,
        planar: Int = 0
    ) -> DICOMPixelDescription {
        DICOMPixelDescription(
            rows: rows, columns: columns, samplesPerPixel: samples, photometricInterpretation: photometric,
            bitsAllocated: bits > 8 ? 16 : 8, bitsStored: bits, highBit: bits - 1, isSigned: false,
            planarConfiguration: planar, numberOfFrames: 1)
    }

    func testEncoderRoundTripsLosslessFrames() throws {
        let codec = DICOMJPEGXLCodec()
        let layouts: [(Int, Int, Int, Int, DICOMPhotometricInterpretation)] = [
            (37, 41, 1, 12, .monochrome2), (30, 20, 1, 8, .monochrome1), (9, 13, 1, 1, .monochrome2),
            (16, 24, 1, 16, .monochrome2), (33, 29, 3, 8, .rgb), (20, 17, 3, 10, .rgb), (1, 1, 1, 8, .monochrome2),
        ]
        for (rows, columns, samples, bits, photometric) in layouts {
            let name = "\(rows)x\(columns)x\(samples) \(bits)-bit"
            let source = frame(rows: rows, columns: columns, samples: samples, bits: bits)
            let description = layout(rows: rows, columns: columns, samples: samples, bits: bits, photometric: photometric)
            let encoded = try codec.encode(bytes(source, bits: bits), description: description)
            XCTAssertEqual(encoded.photometric, photometric, name)
            XCTAssertEqual(encoded.data.count % 2, 0, name)
            XCTAssertEqual(DICOMJPEGXLCodec.Mode.lossless.transferSyntaxUID, DICOMJPEGXLCodec.lossless)
            let decoded = try codec.decode(encoded.data, description: description)
            XCTAssertEqual(values(decoded.data, bits: bits), source, name)
        }

        // Planar Configuration 1 is accepted and decoded pixel by pixel.
        let source = frame(rows: 6, columns: 5, samples: 3, bits: 8)
        let planes = (0..<3).flatMap { sample in stride(from: sample, to: source.count, by: 3).map { source[$0] } }
        let planar = layout(rows: 6, columns: 5, samples: 3, bits: 8, photometric: .rgb, planar: 1)
        let encoded = try codec.encode(bytes(planes, bits: 8), description: planar)
        let decoded = try codec.decode(encoded.data, description: layout(rows: 6, columns: 5, samples: 3, bits: 8,
                                                                         photometric: .rgb))
        XCTAssertEqual(values(decoded.data, bits: 8), source)
    }

    func testLossyEncodingFollowsTheDistance() throws {
        let codec = DICOMJPEGXLCodec()
        let source = frame(rows: 48, columns: 64, samples: 3, bits: 8)
        let description = layout(rows: 48, columns: 64, samples: 3, bits: 8, photometric: .rgb)
        var previous = Int.max
        for distance: Float in [0.5, 1, 4] {
            let encoded = try codec.encode(bytes(source, bits: 8), description: description, mode: .distance(distance))
            XCTAssertLessThan(encoded.data.count, previous, "\(distance)")
            previous = encoded.data.count
            let decoded = values(try codec.decode(encoded.data, description: description).data, bits: 8)
            let squares = zip(decoded, source).map { pair -> Double in Double((pair.0 - pair.1) * (pair.0 - pair.1)) }
            let psnr = 10 * log10(255.0 * 255.0 / max(squares.reduce(0, +) / Double(squares.count), 1e-9))
            XCTAssertGreaterThan(psnr, distance > 2 ? 25 : 32, "\(distance)")
        }
        XCTAssertEqual(DICOMJPEGXLCodec.Mode.distance(1).transferSyntaxUID, DICOMJPEGXLCodec.general)
    }

    func testJPEGRecompressionRebuildsTheOriginalBitstream() throws {
        let codec = DICOMJPEGXLCodec()
        for name in ["color_33x29_sub0", "color_33x29_sub1", "color_33x29_sub2", "color_32x24_sub12",
                     "color_2x40_sub1", "color_3x5_sub2", "gray_23x17_q50", "gray_7x33_q95", "gray_1x1_q50"] {
            let jpeg = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "jpeg-\(name)", withExtension: "jpg")))
            let recompressed = try codec.recompressJPEG(jpeg)
            XCTAssertEqual(recompressed.count % 2, 0, name)
            XCTAssertEqual(try codec.reconstructJPEG(recompressed), jpeg, name)

            // The pixels are close to the JPEG decoded by this library.
            let gray = name.hasPrefix("gray")
            let bytes = [UInt8](jpeg)
            let sof = try XCTUnwrap((2..<(bytes.count - 9)).first {
                bytes[$0] == 0xFF && (0xC0...0xC2).contains(bytes[$0 + 1])
            })
            let reference = try DICOMJPEGBaselineCodec().decode(jpeg, description: DICOMPixelDescription(
                rows: Int(bytes[sof + 5]) << 8 | Int(bytes[sof + 6]), columns: Int(bytes[sof + 7]) << 8 | Int(bytes[sof + 8]),
                samplesPerPixel: gray ? 1 : 3, photometricInterpretation: gray ? .monochrome2 : .ybrFull422,
                bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false, planarConfiguration: 0,
                numberOfFrames: 1, isEncapsulated: true))
            let pixels = try codec.decode(recompressed, description: reference.description)
            let differences = zip([UInt8](pixels.data), [UInt8](reference.data)).map { abs(Int($0) - Int($1)) }
            XCTAssertEqual(differences.count, reference.data.count, name)
            // libjxl renders JPEG coefficients with its own IDCT and chroma
            // upsampling: imagecodecs shows the same differences (up to 16
            // levels at chroma edges) between libjxl and libjpeg-turbo.
            XCTAssertLessThanOrEqual(differences.max() ?? 0, 16, name)
            XCTAssertLessThanOrEqual(Double(differences.reduce(0, +)) / Double(max(differences.count, 1)), 3.5, name)
        }
        // The DICOM pad byte after EOI is not part of the bitstream.
        let jpeg = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "jpeg-gray_23x17_q50", withExtension: "jpg")))
        if jpeg.count % 2 == 1 {
            XCTAssertEqual(try codec.reconstructJPEG(codec.recompressJPEG(jpeg + Data([0]))), jpeg)
        }
        // Frames without reconstruction data cannot rebuild a JPEG.
        let lossless = try codec.encode(bytes(frame(rows: 4, columns: 4, samples: 1, bits: 8), bits: 8),
                                        description: layout(rows: 4, columns: 4, samples: 1, bits: 8, photometric: .monochrome2))
        XCTAssertThrowsError(try codec.reconstructJPEG(lossless.data))
        // The fixture recompressed by imagecodecs carries its JPEG too.
        XCTAssertNoThrow(try codec.reconstructJPEG(resource("rgb8-jpeg-recompression", "jxl")))
    }

    func testEncoderRejectsUnsupportedInputs() throws {
        let codec = DICOMJPEGXLCodec()
        let data = bytes(frame(rows: 4, columns: 4, samples: 3, bits: 8), bits: 8)
        let rgb = layout(rows: 4, columns: 4, samples: 3, bits: 8, photometric: .rgb)
        XCTAssertThrowsError(try codec.encode(data, description: rgb, effort: 0))
        XCTAssertThrowsError(try codec.encode(data, description: rgb, mode: .distance(30)))
        XCTAssertThrowsError(try codec.encode(data, description: layout(rows: 4, columns: 4, samples: 3, bits: 8,
                                                                        photometric: .ybrFull)))
        XCTAssertThrowsError(try codec.encode(data, description: layout(rows: 4, columns: 4, samples: 3, bits: 7,
                                                                        photometric: .rgb)))
        let signed = DICOMPixelDescription(
            rows: 4, columns: 4, samplesPerPixel: 1, photometricInterpretation: .monochrome2, bitsAllocated: 16,
            bitsStored: 12, highBit: 11, isSigned: true, planarConfiguration: 0, numberOfFrames: 1)
        XCTAssertThrowsError(try codec.encode(Data(count: 32), description: signed))
        XCTAssertThrowsError(try codec.recompressJPEG(Data([0x00, 0x01, 0x02, 0x03, 0x04])))
        // JPEG XL cannot represent 4:1:1 chroma.
        let jpeg411 = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "jpeg-color_32x24_sub41", withExtension: "jpg")))
        XCTAssertThrowsError(try codec.recompressJPEG(jpeg411))
        let jpeg = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "jpeg-color_33x29_sub0", withExtension: "jpg")))
        XCTAssertThrowsError(try codec.recompressJPEG(jpeg.prefix(jpeg.count / 2)))
    }
}
