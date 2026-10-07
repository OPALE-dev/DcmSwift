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

    func testRetiredProgressiveHuffmanSyntaxesRemainReadable() throws {
        // Processes 6/8 (spectral selection) and 10/12 (full progression) are
        // retired but still found in archives.
        for uid in [DICOMJPEGBaselineCodec.spectralSelection, DICOMJPEGBaselineCodec.fullProgression] {
            XCTAssertTrue(DicomSpec.shared.isKnown(transferSyntax: uid))
            XCTAssertTrue(try XCTUnwrap(TransferSyntax(uid)).capability.canDecodePixelData, uid)
            XCTAssertTrue(DICOMCodecRegistry.decoder(for: uid) is DICOMJPEGBaselineCodec, uid)
        }
        let fixture = try XCTUnwrap(try fixtures().first { $0.name == "progressive_gray" })
        let decoder = try XCTUnwrap(DICOMCodecRegistry.decoder(for: DICOMJPEGBaselineCodec.fullProgression))
        let decoded = try decoder.decode(try resource(fixture.name, "jpg"), description: description(fixture))
        XCTAssertEqual(decoded.data, try resource(fixture.name, "ref"))
    }

    func testEncoderRoundTripsSamplingModesAndRestartMarkers() throws {
        let width = 17, height = 13
        let pixels = (0..<(width * height)).flatMap { pixel -> [UInt8] in
            let x = pixel % width, y = pixel / width
            return [UInt8((x * 13 + y * 7) & 255), UInt8((x * 3 + y * 19) & 255),
                    UInt8((x * 23 + y * 5) & 255)]
        }
        let description = DICOMPixelDescription(
            rows: height, columns: width, samplesPerPixel: 3, photometricInterpretation: .rgb,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false,
            planarConfiguration: 0, numberOfFrames: 1)
        let cases: [(DICOMJPEGBaselineCodec.Subsampling, Int, Int, DICOMPhotometricInterpretation)] = [
            (.s444, 1, 1, .ybrFull), (.s422, 2, 1, .ybrFull422), (.s420, 2, 2, .ybrFull422),
        ]
        for (subsampling, horizontal, vertical, photometric) in cases {
            let encoded = try DICOMJPEGBaselineCodec().encode(
                Data(pixels), description: description, quality: 90,
                subsampling: subsampling, restartInterval: 1)
            XCTAssertEqual(encoded.photometric, photometric)
            let stream = try JPEGStream([UInt8](encoded.data))
            XCTAssertEqual(stream.frame.process, 0)
            XCTAssertEqual(stream.frame.components.map(\.horizontalSampling), [horizontal, 1, 1])
            XCTAssertEqual(stream.frame.components.map(\.verticalSampling), [vertical, 1, 1])
            XCTAssertEqual(stream.scans.first?.restartInterval, 1)
            let decodedDescription = DICOMPixelDescription(
                rows: height, columns: width, samplesPerPixel: 3, photometricInterpretation: photometric,
                bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false,
                planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: true)
            let decoded = try DICOMJPEGBaselineCodec().decode(encoded.data, description: decodedDescription)
            XCTAssertEqual(decoded.data.count, pixels.count)
            XCTAssertEqual(decoded.description.photometricInterpretation, .rgb)
        }
    }

    #if os(macOS) || os(Linux)
    func testEncoderMatchesLibjpegTurboIntegerPipelineWhenAvailable() throws {
        let candidates = ["/opt/homebrew/bin/cjpeg", "/usr/local/bin/cjpeg", "/usr/bin/cjpeg"]
        guard let cjpeg = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw XCTSkip("cjpeg is not installed")
        }
        let width = 17, height = 13
        let pixels = (0..<(width * height)).flatMap { pixel -> [UInt8] in
            let x = pixel % width, y = pixel / width
            return [UInt8((x * 13 + y * 7) & 255), UInt8((x * 3 + y * 19) & 255),
                    UInt8((x * 23 + y * 5) & 255)]
        }
        let description = DICOMPixelDescription(
            rows: height, columns: width, samplesPerPixel: 3, photometricInterpretation: .rgb,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false,
            planarConfiguration: 0, numberOfFrames: 1)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dcmswift-jpeg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ppm = directory.appendingPathComponent("input.ppm")
        try Data("P6\n\(width) \(height)\n255\n".utf8 + pixels).write(to: ppm)

        let cases: [(DICOMJPEGBaselineCodec.Subsampling, String)] = [
            (.s444, "1x1,1x1,1x1"), (.s422, "2x1,1x1,1x1"), (.s420, "2x2,1x1,1x1"),
        ]
        for quality in [50, 90] {
            for (subsampling, sample) in cases {
                let referenceURL = directory.appendingPathComponent("reference-\(quality)-\(sample).jpg")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: cjpeg)
                process.arguments = ["-quality", "\(quality)", "-sample", sample, "-dct", "int",
                                     "-outfile", referenceURL.path, ppm.path]
                try process.run()
                process.waitUntilExit()
                XCTAssertEqual(process.terminationStatus, 0)

                let encoded = try DICOMJPEGBaselineCodec().encode(
                    Data(pixels), description: description, quality: quality, subsampling: subsampling)
                let encodedDescription = DICOMPixelDescription(
                    rows: height, columns: width, samplesPerPixel: 3,
                    photometricInterpretation: encoded.photometric,
                    bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false,
                    planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: true)
                let ours = try DICOMJPEGBaselineCodec().decode(encoded.data, description: encodedDescription)
                let reference = try DICOMJPEGBaselineCodec().decode(
                    Data(contentsOf: referenceURL), description: encodedDescription)
                XCTAssertEqual(ours.data, reference.data, "quality \(quality), sampling \(sample)")
            }
        }
    }
    #endif

    func testEncoderRejectsUnsupportedInputs() throws {
        let codec = DICOMJPEGBaselineCodec()
        let signed = DICOMPixelDescription(
            rows: 1, columns: 1, samplesPerPixel: 1, photometricInterpretation: .monochrome2,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: true,
            planarConfiguration: 0, numberOfFrames: 1)
        XCTAssertThrowsError(try codec.encode(Data([0]), description: signed))
        let palette = DICOMPixelDescription(
            rows: 1, columns: 1, samplesPerPixel: 1, photometricInterpretation: .paletteColor,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false,
            planarConfiguration: 0, numberOfFrames: 1)
        XCTAssertThrowsError(try codec.encode(Data([0]), description: palette))
        XCTAssertThrowsError(try codec.encode(Data([0]), description: palette, quality: 0))
    }

    func testExtendedEncoderRoundTripsTwelveBitMonochrome() throws {
        let width = 19, height = 11
        var values = [UInt16]()
        for index in 0..<(width * height) {
            values.append(UInt16((index * 37 + (index / width) * 113) & 0xFFF))
        }
        var bytes = [UInt8]()
        for value in values { bytes += [UInt8(value & 0xFF), UInt8(value >> 8)] }
        let description = DICOMPixelDescription(
            rows: height, columns: width, samplesPerPixel: 1, photometricInterpretation: .monochrome2,
            bitsAllocated: 16, bitsStored: 12, highBit: 11, isSigned: false,
            planarConfiguration: 0, numberOfFrames: 1)
        for quality in [1, 90, 100] {
            let encoded = try DICOMJPEGBaselineCodec().encode(
                Data(bytes), description: description, quality: quality, restartInterval: 2)
            let stream = try JPEGStream([UInt8](encoded.data))
            XCTAssertEqual(stream.frame.process, 1)
            XCTAssertEqual(stream.frame.precision, 12)
            XCTAssertEqual(encoded.photometric, .monochrome2)
            if quality == 1 {
                XCTAssertTrue(stream.scans[0].quantizationTables[0]!.contains { $0 > 255 })
            }
            let decoded = try DICOMJPEGBaselineCodec().decode(
                encoded.data, description: description.decodedFrame())
            XCTAssertEqual(decoded.data.count, bytes.count)
        }
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
