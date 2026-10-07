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

    func testArithmeticSequentialAndProgressiveFixtures() throws {
        for uid in [DICOMJPEGBaselineCodec.arithmeticExtended,
                    DICOMJPEGBaselineCodec.arithmeticSpectralSelection,
                    DICOMJPEGBaselineCodec.arithmeticFullProgression,
                    DICOMJPEGLosslessCodec.processFifteen] {
            XCTAssertTrue(DicomSpec.shared.isKnown(transferSyntax: uid), uid)
            XCTAssertTrue(try XCTUnwrap(TransferSyntax(uid)).capability.canDecodePixelData, uid)
            XCTAssertNotNil(DICOMCodecRegistry.decoder(for: uid), uid)
        }
        let sequential =
            "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcp" +
            "LDAxNDQ0Hyc5PTgyPC4zNDL/yQALCAARABcBAREA/8wABgAQEAX/2gAIAQEAAD8A7XVi/NMylUJ4hRJnmkSqs6iiq0xBx4YV" +
            "GoW/SkIhsDXeOxMrg4xdP5nDcX9Wg5+1bt5cdfwViguX7RI1WpuD4skL32ht8r1mTrjNQ39J1nsk1zs7CUtVg3bibHNLbYTb" +
            "NQq0WTxakmjtUfMFRo/VpTfRuB+uXhmtuo5kekNCAhqtWKMKGc3wyc1VcTZpwwPlVfE6jB7a46vvXlF4LHK270LaHyfGdQ15" +
            "s0mzxsCVkH4BUKImCC/6Ocz3sR1vcJQNkypOCBeBK6+pLyQkNs3FNllIx0U44Nru+nj1pq2Z/wDNFja3O7T7ETaU3A8kPnfd" +
            "oDJNIaxokzGK3GlKDP/Z"
        let progressive =
            "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcp" +
            "LDAxNDQ0Hyc5PTgyPC4zNDL/ygALCAARABcBAREA/8wABAAQ/9oACAEBAAAAAeG1eo7/zAAEEAX/2gAIAQEAAQUCKeSHRCcI" +
            "Xd6erwzDH+dBY3YUC5D/zAAEEAX/2gAIAQEABj8CS6f5Ny2qFxw/RDdpilmSHgcjJeuY0L6niQTav68mnFmZI3yv4UoCC1Y2" +
            "ugDt4AgRCs0m1b4ar+/l69m84pRSsCMRJGRyeTxPKzyqpP/MAAQQBf/aAAgBAQABPyFoj3xOGArSaNFJOAmf4JAFpiyAWSRR" +
            "IyxjjON/2QHSZ+eWU9pX5oTsRqDEkZsXDUt9Zk3VLpcn+U4sKL8mWnWs0f/aAAgBAQAAABA2/8wABBAF/9oACAEBAAE/EHGB" +
            "9ZX1wMZ+UjIu5rrxHynW+lQ0YDRkLhcqdaVjOPoG7hHPjwAzqph2Bbvp4GtsPyaDvpjjqHDdfsThtQWCzDaqZ28Q44B3EwAP" +
            "HYbbhrb/2Q=="
        let expected = try XCTUnwrap(Data(base64Encoded:
            "ACpFbo7A2wMmU22VvssDLU19nKv0BCV2brzc9SM3b4e02volWYWKsdcBMj2BkL3/BylkirLK/wZPaHmrv/giRVaSssj/KmiU" +
            "mMriBD1RhKLF/xc9ZHqr4uEaN12UtdMJK1R4nMDuCjdCg4jL3x8bVoyYxf0iSXGbud4AK0tzhcrpAClWbJvK4goncICn49oeQ" +
            "HGaotf/Ezd6irfX/xU1iYvC9BkybYKiyO8YP16Cs9D6D0pWna3H/zdUe53G5g4xWIycwugVNmCTlM/tBlRQhM3bBTBUcZ3A" +
            "0A40VHuSvtQYMFuGk8P9FlBui7Hg+CFVaJG20gksVmmSzMsLNWl9qsv/F0dniKzW/R0tc4Ot0f0aSWeD2OcSPUuCks/yDjRu" +
            "fq/a7BVTZIyuy/8kW3SL3PAgKV2Bo7H9CBtafpa95Bo6WJe71xcfMmWdrdgXGk9vs7/eGS5Pf5S6/xlMZorN2/8tRGWds9cE" +
            "H01skr7VDS9ihavR8R09Yois1PgcQGiMsdL9HUdpjA=="))
        let description = DICOMPixelDescription(
            rows: 17, columns: 23, samplesPerPixel: 1, photometricInterpretation: .monochrome2,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false,
            planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: true)
        for encoded in [sequential, progressive] {
            let decoded = try DICOMJPEGBaselineCodec().decode(
                try XCTUnwrap(Data(base64Encoded: encoded)), description: description)
            XCTAssertEqual(decoded.data, expected)
        }
        var malformedDAC = [UInt8](try XCTUnwrap(Data(base64Encoded: sequential)))
        let dac = try XCTUnwrap(malformedDAC.indices.dropLast().first {
            malformedDAC[$0] == 0xFF && malformedDAC[$0 + 1] == 0xCC
        })
        malformedDAC[dac + 5] = 0x01 // L=1, U=0 is forbidden.
        XCTAssertThrowsError(try JPEGStream(malformedDAC))
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
    func testArithmeticDCTMatchesLibjpegTurboWhenAvailable() throws {
        let cjpegCandidates = ["/opt/homebrew/bin/cjpeg", "/usr/local/bin/cjpeg", "/usr/bin/cjpeg"]
        let djpegCandidates = ["/opt/homebrew/bin/djpeg", "/usr/local/bin/djpeg", "/usr/bin/djpeg"]
        guard let cjpeg = cjpegCandidates.first(where: FileManager.default.isExecutableFile(atPath:)),
              let djpeg = djpegCandidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw XCTSkip("cjpeg and djpeg are not installed")
        }
        let width = 23, height = 17
        var pixels = [UInt8]()
        for index in 0..<(width * height) {
            pixels.append(UInt8((index * 37 + (index / width) * 19) & 255))
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-arithmetic-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.pgm")
        try Data("P5\n\(width) \(height)\n255\n".utf8 + pixels).write(to: input)
        let scans = directory.appendingPathComponent("spectral.scans")
        try Data("0: 0 0 0 0; 0: 1 5 0 0; 0: 6 20 0 0; 0: 21 63 0 0;\n".utf8).write(to: scans)
        let description = DICOMPixelDescription(
            rows: height, columns: width, samplesPerPixel: 1, photometricInterpretation: .monochrome2,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false,
            planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: true)

        for (name, modeArguments) in [("sequential", [String]()),
                                      ("spectral", ["-scans", scans.path]),
                                      ("full", ["-progressive"])] {
            let jpeg = directory.appendingPathComponent("\(name).jpg")
            let reference = directory.appendingPathComponent("\(name).pgm")
            let encoder = Process()
            encoder.executableURL = URL(fileURLWithPath: cjpeg)
            encoder.arguments = ["-arithmetic", "-restart", "2B"] + modeArguments
                + ["-outfile", jpeg.path, input.path]
            try encoder.run(); encoder.waitUntilExit()
            XCTAssertEqual(encoder.terminationStatus, 0)
            let decoder = Process()
            decoder.executableURL = URL(fileURLWithPath: djpeg)
            decoder.arguments = ["-grayscale", "-outfile", reference.path, jpeg.path]
            try decoder.run(); decoder.waitUntilExit()
            XCTAssertEqual(decoder.terminationStatus, 0)
            let referenceBytes = try Data(contentsOf: reference)
            let headerEnd = try XCTUnwrap(referenceBytes.range(of: Data("\n255\n".utf8))).upperBound
            let decoded = try DICOMJPEGBaselineCodec().decode(Data(contentsOf: jpeg), description: description)
            let expected = Data(referenceBytes.suffix(from: headerEnd))
            if decoded.data != expected {
                let actualValues = [UInt8](decoded.data), expectedValues = [UInt8](expected)
                let mismatch = zip(actualValues, expectedValues).enumerated().first { $0.element.0 != $0.element.1 }
                XCTFail("\(name) first mismatch \(String(describing: mismatch)) actual \(actualValues.prefix(16)) expected \(expectedValues.prefix(16))")
            }
        }
    }

    func testArithmeticDCTColorAndTwelveBitWhenAvailable() throws {
        let cjpegCandidates = ["/opt/homebrew/bin/cjpeg", "/usr/local/bin/cjpeg", "/usr/bin/cjpeg"]
        let djpegCandidates = ["/opt/homebrew/bin/djpeg", "/usr/local/bin/djpeg", "/usr/bin/djpeg"]
        guard let cjpeg = cjpegCandidates.first(where: FileManager.default.isExecutableFile(atPath:)),
              let djpeg = djpegCandidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw XCTSkip("cjpeg and djpeg are not installed")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-arithmetic-wide-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func run(_ executable: String, _ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            try process.run(); process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, arguments.joined(separator: " "))
        }

        let colorWidth = 17, colorHeight = 13
        var color = [UInt8]()
        for index in 0..<(colorWidth * colorHeight) {
            let x = index % colorWidth, y = index / colorWidth
            color += [UInt8((x * 17 + y * 5) & 255), UInt8((x * 7 + y * 23) & 255),
                      UInt8((x * 29 + y * 3) & 255)]
        }
        let ppm = directory.appendingPathComponent("color.ppm")
        let colorJPEG = directory.appendingPathComponent("color.jpg")
        let colorReference = directory.appendingPathComponent("color-reference.ppm")
        try Data("P6\n\(colorWidth) \(colorHeight)\n255\n".utf8 + color).write(to: ppm)
        try run(cjpeg, ["-arithmetic", "-sample", "2x2,1x1,1x1", "-restart", "1B",
                         "-outfile", colorJPEG.path, ppm.path])
        try run(djpeg, ["-rgb", "-outfile", colorReference.path, colorJPEG.path])
        let colorPNM = try Data(contentsOf: colorReference)
        let colorHeader = try XCTUnwrap(colorPNM.range(of: Data("\n255\n".utf8))).upperBound
        let colorDescription = DICOMPixelDescription(
            rows: colorHeight, columns: colorWidth, samplesPerPixel: 3,
            photometricInterpretation: .ybrFull422, bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: true)
        XCTAssertEqual(try DICOMJPEGBaselineCodec().decode(
            Data(contentsOf: colorJPEG), description: colorDescription).data,
                       Data(colorPNM.suffix(from: colorHeader)))

        let wideWidth = 19, wideHeight = 11
        var widePNM = [UInt8]()
        for index in 0..<(wideWidth * wideHeight) {
            let value = (index * 173 + (index / wideWidth) * 97) & 4095
            widePNM += [UInt8(value >> 8), UInt8(value & 0xFF)]
        }
        let pgm = directory.appendingPathComponent("wide.pgm")
        let wideJPEG = directory.appendingPathComponent("wide.jpg")
        let wideReference = directory.appendingPathComponent("wide-reference.pgm")
        try Data("P5\n\(wideWidth) \(wideHeight)\n4095\n".utf8 + widePNM).write(to: pgm)
        try run(cjpeg, ["-precision", "12", "-arithmetic", "-restart", "2B",
                         "-outfile", wideJPEG.path, pgm.path])
        try run(djpeg, ["-outfile", wideReference.path, wideJPEG.path])
        let referencePNM = try Data(contentsOf: wideReference)
        let wideHeader = try XCTUnwrap(referencePNM.range(of: Data("\n4095\n".utf8))).upperBound
        let referenceBigEndian = [UInt8](referencePNM.suffix(from: wideHeader))
        var referenceLittleEndian = [UInt8]()
        for offset in stride(from: 0, to: referenceBigEndian.count, by: 2) {
            referenceLittleEndian += [referenceBigEndian[offset + 1], referenceBigEndian[offset]]
        }
        let wideDescription = DICOMPixelDescription(
            rows: wideHeight, columns: wideWidth, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2, bitsAllocated: 16, bitsStored: 12, highBit: 11,
            isSigned: false, planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: true)
        XCTAssertEqual(try DICOMJPEGBaselineCodec().decode(
            Data(contentsOf: wideJPEG), description: wideDescription).data, Data(referenceLittleEndian))
    }

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
            XCTAssertEqual($0 as? DICOMCodecError, .unsupportedImage("SOF3 is not a supported DCT-based JPEG process"))
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
