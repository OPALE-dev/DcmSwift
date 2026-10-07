import XCTest
@testable import DcmSwift

/// JPEG 2000 and HTJ2K through the vendored OpenJPEG.
///
/// The `ht_*` fixtures were encoded by OpenJPH 0.31 (through imagecodecs), an
/// implementation independent of the OpenJPEG decoder; `jp2_rgb8_padded` is
/// an OpenJPEG JP2 file followed by a DICOM padding byte. Lossless `.raw`
/// files hold the source samples, lossy ones the encoder's own decoding.
final class DcmSwiftJPEG2000Tests: XCTestCase {

    private struct Fixture: Decodable {
        let name: String
        let rows: Int
        let columns: Int
        let samples: Int
        let bits: Int
        let signed: Bool
        let lossless: Bool
        let transferSyntax: String
    }

    private func resource(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "jpeg2000-\(name)", withExtension: ext)))
    }

    private func description(
        rows: Int, columns: Int, samples: Int, bits: Int, signed: Bool,
        photometric: DICOMPhotometricInterpretation? = nil, encapsulated: Bool = true
    ) -> DICOMPixelDescription {
        DICOMPixelDescription(
            rows: rows, columns: columns, samplesPerPixel: samples,
            photometricInterpretation: photometric ?? (samples == 3 ? .rgb : .monochrome2),
            bitsAllocated: bits > 8 ? 16 : 8, bitsStored: bits, highBit: bits - 1, isSigned: signed,
            planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: encapsulated)
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

    func testDecodingMatchesIndependentEncoders() throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: resource("cases", "json"))
        XCTAssertEqual(fixtures.count, 6)
        for fixture in fixtures {
            let decoder = try XCTUnwrap(DICOMCodecRegistry.decoder(for: fixture.transferSyntax), fixture.name)
            XCTAssertTrue(decoder is DICOMJPEG2000Codec, fixture.name)
            let encoded = description(
                rows: fixture.rows, columns: fixture.columns, samples: fixture.samples, bits: fixture.bits,
                signed: fixture.signed, photometric: fixture.samples == 3 ? .ybrRCT : nil)
            let decoded = try decoder.decode(try resource(fixture.name, "j2k"), description: encoded)
            let actual = values(decoded.data, bits: fixture.bits, signed: fixture.signed)
            let expected = values(try resource(fixture.name, "raw"), bits: fixture.bits, signed: fixture.signed)
            XCTAssertEqual(actual.count, expected.count, fixture.name)
            // Lossy 9/7 decoding may round differently between implementations.
            let tolerance = fixture.lossless ? 0 : 1
            XCTAssertLessThanOrEqual(zip(actual, expected).map { abs($0 - $1) }.max() ?? 0, tolerance, fixture.name)
            if fixture.samples == 3 {
                XCTAssertEqual(decoded.description.photometricInterpretation, .rgb, fixture.name)
            }
        }
    }

    func testEncoderRoundTripsLosslessFrames() throws {
        var state: UInt64 = 3
        func random() -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(state >> 33)
        }
        let codec = DICOMJPEG2000Codec()
        for (rows, columns, samples, bits, signed) in [
            (29, 37, 1, 8, false), (48, 64, 1, 12, false), (65, 33, 1, 16, true), (17, 31, 1, 13, true),
            (1, 1, 1, 8, false), (70, 3, 1, 8, false), (30, 50, 3, 8, false),
        ] {
            let native = description(rows: rows, columns: columns, samples: samples, bits: bits, signed: signed,
                                     encapsulated: false)
            var frame = [UInt8]()
            for index in 0..<(rows * columns * samples) {
                let x = index / samples % columns, y = index / samples / columns
                let value = (((x * 5 + y * 3) << max(0, bits - 8)) + (random() & 7)) & ((1 << bits) - 1)
                frame.append(UInt8(value & 0xFF))
                if bits > 8 { frame.append(UInt8(value >> 8)) }
            }
            let (data, photometric) = try codec.encode(Data(frame), description: native)
            XCTAssertEqual(data.count % 2, 0)
            XCTAssertTrue(data.starts(with: [0xFF, 0x4F, 0xFF, 0x51]))
            XCTAssertEqual(photometric, samples == 3 ? .ybrRCT : .monochrome2)
            let decoded = try codec.decode(data, description: description(
                rows: rows, columns: columns, samples: samples, bits: bits, signed: signed, photometric: photometric))
            XCTAssertEqual(values(decoded.data, bits: bits, signed: signed),
                           values(Data(frame), bits: bits, signed: signed), "\(bits) bits, \(samples) samples")
            XCTAssertEqual(decoded.description.photometricInterpretation, samples == 3 ? .rgb : .monochrome2)
        }
    }

    func testIrreversibleEncodingHonorsRateControl() throws {
        let rows = 64, columns = 64
        var frame = [UInt8]()
        for index in 0..<(rows * columns * 3) {
            frame.append(UInt8((index / 3 % columns) * 2 + index / 3 / columns + index % 3 * 30))
        }
        let native = description(rows: rows, columns: columns, samples: 3, bits: 8, signed: false, encapsulated: false)
        let codec = DICOMJPEG2000Codec()
        let (data, photometric) = try codec.encode(Data(frame), description: native, quality: .compressionRatio(10))
        XCTAssertEqual(photometric, .ybrICT)
        XCTAssertLessThanOrEqual(data.count, frame.count / 9)
        // The COD segment selects the irreversible 9/7 wavelet and the MCT.
        let bytes = [UInt8](data)
        let cod = try XCTUnwrap((0..<(bytes.count - 1)).first { bytes[$0] == 0xFF && bytes[$0 + 1] == 0x52 })
        XCTAssertEqual(bytes[cod + 8], 1)
        XCTAssertEqual(bytes[cod + 13], 0)
        let decoded = try codec.decode(data, description: description(
            rows: rows, columns: columns, samples: 3, bits: 8, signed: false, photometric: .ybrICT))
        let error = zip(decoded.data, frame).map { abs(Int($0) - Int($1)) }
        XCTAssertLessThan(Double(error.reduce(0, +)) / Double(error.count), 4)

        let (quality, _) = try codec.encode(Data(frame), description: native, quality: .peakSignalToNoiseRatio(40))
        XCTAssertLessThan(quality.count, frame.count)
    }

    func testHTJ2KEncoderRoundTripsAndFollowsTheTransferSyntaxRules() throws {
        let codec = DICOMJPEG2000Codec()
        for (rows, columns, samples, bits, signed, mode) in [
            (29, 37, 1, 8, false, DICOMJPEG2000Codec.HTJ2KMode.lossless), (65, 33, 1, 16, true, .lossless),
            (17, 31, 1, 13, true, .lossless), (1, 1, 1, 8, false, .lossless), (30, 50, 3, 8, false, .lossless),
            (140, 300, 1, 12, false, .losslessRPCL), (70, 130, 3, 8, false, .losslessRPCL),
        ] {
            let native = description(rows: rows, columns: columns, samples: samples, bits: bits, signed: signed,
                                     encapsulated: false)
            var frame = [UInt8]()
            for index in 0..<(rows * columns * samples) {
                let x = index / samples % columns, y = index / samples / columns
                let value = (((x * 5 + y * 3 + index % samples * 20) << max(0, bits - 8)) + index % 7) & ((1 << bits) - 1)
                frame.append(UInt8(value & 0xFF))
                if bits > 8 { frame.append(UInt8(value >> 8)) }
            }
            let (data, photometric) = try codec.encodeHTJ2K(Data(frame), description: native, mode: mode)
            XCTAssertEqual(photometric, samples == 3 ? .ybrRCT : .monochrome2)
            let label = "\(columns)x\(rows)x\(samples), \(bits) bits, \(mode)"
            let markers = mainHeaderMarkers([UInt8](data))
            XCTAssertNotNil(markers[0x50], "CAP: \(label)")
            let cod = try XCTUnwrap(markers[0x52], label)
            XCTAssertEqual(cod[1], 2, "RPCL: \(label)")
            if mode == .losslessRPCL {
                XCTAssertNotNil(markers[0x55], "TLM: \(label)")
                let levels = Int(cod[5])
                XCTAssertLessThanOrEqual((max(rows, columns) + (1 << levels) - 1) >> levels, 64, label)
            }
            let decoded = try codec.decode(data, description: description(
                rows: rows, columns: columns, samples: samples, bits: bits, signed: signed, photometric: photometric))
            XCTAssertEqual(values(decoded.data, bits: bits, signed: signed),
                           values(Data(frame), bits: bits, signed: signed), label)
        }

        let native = description(rows: 64, columns: 64, samples: 1, bits: 12, signed: false, encapsulated: false)
        var frame = [UInt8]()
        for index in 0..<(64 * 64) {
            let value = (index % 64) * 40 + index / 64 * 20
            frame += [UInt8(value & 0xFF), UInt8(value >> 8)]
        }
        let (data, _) = try codec.encodeHTJ2K(Data(frame), description: native, mode: .irreversible(quantizationStep: 0.005))
        XCTAssertLessThan(data.count, frame.count / 2)
        let decoded = try codec.decode(data, description: description(rows: 64, columns: 64, samples: 1, bits: 12, signed: false))
        let error = zip(values(decoded.data, bits: 12, signed: false), values(Data(frame), bits: 12, signed: false))
            .map { abs($0 - $1) }
        XCTAssertLessThan(error.max() ?? 0, 64)
        XCTAssertThrowsError(try codec.encodeHTJ2K(Data(frame), description: native, mode: .irreversible(quantizationStep: 0)))
    }

    /// The main header marker segments, by marker code, without their length.
    private func mainHeaderMarkers(_ bytes: [UInt8]) -> [UInt8: [UInt8]] {
        var markers: [UInt8: [UInt8]] = [:]
        var position = 2
        while position + 4 <= bytes.count, bytes[position] == 0xFF, bytes[position + 1] != 0x90 {
            let length = Int(bytes[position + 2]) << 8 | Int(bytes[position + 3])
            markers[bytes[position + 1]] = Array(bytes[(position + 4)..<min(bytes.count, position + 2 + length)])
            position += 2 + length
        }
        return markers
    }

    func testCapabilitiesAndRegistry() throws {
        for uid in [DICOMJPEG2000Codec.lossless, DICOMJPEG2000Codec.lossy, DICOMJPEG2000Codec.htj2kLossless,
                    DICOMJPEG2000Codec.htj2kLosslessRPCL, DICOMJPEG2000Codec.htj2k] {
            let capability = try XCTUnwrap(TransferSyntax(uid)).capability
            XCTAssertTrue(capability.canDecodePixelData, uid)
            XCTAssertTrue(capability.canEncodePixelData, uid)
        }
        // Part 2 multi-component and JPIP syntaxes are preserved only.
        for uid in ["1.2.840.10008.1.2.4.92", "1.2.840.10008.1.2.4.93", "1.2.840.10008.1.2.4.94"] {
            XCTAssertNil(DICOMCodecRegistry.decoder(for: uid), uid)
        }
    }

    func testMalformedStreamsAreRejectedWithoutCrashing() throws {
        let codec = DICOMJPEG2000Codec()
        let stream = try resource("ht_rgb8", "j2k")
        let good = description(rows: 23, columns: 31, samples: 3, bits: 8, signed: false, photometric: .ybrRCT)
        XCTAssertThrowsError(try codec.decode(stream, description: description(
            rows: 22, columns: 31, samples: 3, bits: 8, signed: false)))
        XCTAssertThrowsError(try codec.decode(stream, description: description(
            rows: 23, columns: 31, samples: 1, bits: 8, signed: false)))
        XCTAssertThrowsError(try codec.decode(Data([0x00, 0x01, 0x02, 0x03]), description: good))
        for length in stride(from: 2, to: stream.count, by: 41) {
            _ = try? codec.decode(stream.prefix(length), description: good)
        }
        var bytes = [UInt8](stream)
        for index in stride(from: 60, to: bytes.count, by: 67) {
            bytes[index] ^= 0xA5
            _ = try? codec.decode(Data(bytes), description: good)
        }
    }
}
