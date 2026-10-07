import XCTest
@testable import DcmSwift

/// JPEG-LS (ITU-T T.87) decoding and encoding.
///
/// `jpegls-conformance-*` are streams from the T.87 Annex E conformance
/// suite with their source image. The `charls` cases were encoded by CharLS
/// 2.4 from the `.raw` samples, so DcmSwift must reproduce them byte for
/// byte; the `charls-hp` cases add CharLS's HP color transforms; the
/// `dcmswift` cases (restart intervals, which CharLS does not encode) were
/// produced by DcmSwift and their `.raw` samples decoded by CharLS.
final class DcmSwiftJPEGLSTests: XCTestCase {

    private struct Fixture: Decodable {
        let name: String
        let width: Int
        let height: Int
        let comps: Int
        let bits: Int
        let near: Int
        let ilv: Int
        let restart: Int
        let source: String
    }

    private func resource(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "jpegls-\(name)", withExtension: ext)))
    }

    private func fixtures() throws -> [Fixture] {
        try JSONDecoder().decode([Fixture].self, from: resource("cases", "json"))
    }

    private func description(
        rows: Int, columns: Int, samples: Int, bits: Int, encapsulated: Bool = true
    ) -> DICOMPixelDescription {
        DICOMPixelDescription(
            rows: rows, columns: columns, samplesPerPixel: samples,
            photometricInterpretation: samples == 3 ? .rgb : .monochrome2,
            bitsAllocated: bits > 8 ? 16 : 8, bitsStored: bits, highBit: bits - 1, isSigned: false,
            planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: encapsulated)
    }

    private func samples(_ data: Data, bits: Int) -> [Int] {
        let bytes = [UInt8](data)
        return bits > 8
            ? stride(from: 0, to: bytes.count - 1, by: 2).map { Int(bytes[$0]) | Int(bytes[$0 + 1]) << 8 }
            : bytes.map(Int.init)
    }

    func testDecodingMatchesTheSourceWithinNear() throws {
        let fixtures = try fixtures()
        XCTAssertEqual(fixtures.count, 14)
        for fixture in fixtures {
            let decoder = try XCTUnwrap(DICOMCodecRegistry.decoder(
                for: fixture.near == 0 ? DICOMJPEGLSCodec.lossless : DICOMJPEGLSCodec.nearLossless))
            let decoded = try decoder.decode(
                try resource(fixture.name, "jls"),
                description: description(rows: fixture.height, columns: fixture.width, samples: fixture.comps, bits: fixture.bits))
            let expected = samples(try resource(fixture.name, "raw"), bits: fixture.bits)
            let actual = samples(decoded.data, bits: fixture.bits)
            XCTAssertEqual(actual.count, expected.count, fixture.name)
            // Restart cases hold CharLS's own decoding, so they match exactly.
            let tolerance = fixture.source == "dcmswift" ? 0 : fixture.near
            XCTAssertLessThanOrEqual(zip(actual, expected).map { abs($0 - $1) }.max() ?? 0, tolerance, fixture.name)
            XCTAssertEqual(decoded.description.photometricInterpretation,
                           fixture.comps == 3 ? .rgb : .monochrome2, fixture.name)
        }
    }

    func testEncodingReproducesCharLSByteForByte() throws {
        for fixture in try fixtures() where fixture.source == "charls" || (fixture.source == "dcmswift" && fixture.near == 0) {
            let encoded = try DICOMJPEGLSCodec().encode(
                try resource(fixture.name, "raw"),
                description: description(rows: fixture.height, columns: fixture.width, samples: fixture.comps,
                                         bits: fixture.bits, encapsulated: false),
                near: fixture.near, interleave: try XCTUnwrap(DICOMJPEGLSCodec.Interleave(rawValue: fixture.ilv)),
                restartInterval: fixture.restart)
            var expected = try resource(fixture.name, "jls")
            if expected.count % 2 == 1 { expected.append(0) }
            XCTAssertEqual(encoded, expected, fixture.name)
        }
    }

    func testConformanceStreamsWithPresetParameters() throws {
        // t8nde0/3: T1 = T2 = T3 = 9 and RESET = 31 through an LSE segment.
        let pgm = [UInt8](try resource("conformance-test8bs2", "pgm"))
        let source = pgm.suffix(128 * 128).map(Int.init)
        for (name, near) in [("t8nde0", 0), ("t8nde3", 3)] {
            let stream = try resource("conformance-\(name)", "jls")
            let parsed = try JPEGLSStream([UInt8](stream))
            XCTAssertEqual(parsed.scans[0].parameters.threshold1, 9, name)
            XCTAssertEqual(parsed.scans[0].parameters.reset, 31, name)
            let decoded = try DICOMJPEGLSCodec().decode(
                stream, description: description(rows: 128, columns: 128, samples: 1, bits: 8))
            let errors = zip(decoded.data.map(Int.init), source).map { abs($0 - $1) }
            XCTAssertEqual(errors.count, 128 * 128, name)
            XCTAssertLessThanOrEqual(errors.max() ?? 0, near, name)
        }
    }

    func testEncoderRoundTripsSignedAndNearLosslessFrames() throws {
        var state: UInt64 = 11
        func random() -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(state >> 33)
        }
        let codec = DICOMJPEGLSCodec()
        for (bits, signed, near, samples, interleave) in [
            (16, true, 0, 1, DICOMJPEGLSCodec.Interleave.none), (12, false, 2, 1, .none),
            (8, false, 0, 3, .none), (8, false, 4, 3, .sample), (6, false, 0, 3, .line),
        ] {
            let rows = 13, columns = 17
            let allocated = bits > 8 ? 16 : 8
            var frame = [UInt8]()
            for index in 0..<(rows * columns * samples) {
                let value = index % 7 == 0 ? 3 : random() & ((1 << bits) - 1)
                frame.append(UInt8(value & 0xFF))
                if allocated == 16 { frame.append(UInt8(value >> 8)) }
            }
            var native = description(rows: rows, columns: columns, samples: samples, bits: bits, encapsulated: false)
            native = DICOMPixelDescription(
                rows: rows, columns: columns, samplesPerPixel: samples, photometricInterpretation: native.photometricInterpretation,
                bitsAllocated: allocated, bitsStored: bits, highBit: bits - 1, isSigned: signed,
                planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: false)
            let encoded = try codec.encode(Data(frame), description: native, near: near, interleave: interleave,
                                           restartInterval: 4)
            XCTAssertEqual(encoded.count % 2, 0)
            let decoded = try codec.decode(encoded, description: description(
                rows: rows, columns: columns, samples: samples, bits: bits))
            let errors = zip(self.samples(decoded.data, bits: bits), self.samples(Data(frame), bits: bits))
                .map { abs($0 - $1) }
            XCTAssertLessThanOrEqual(errors.max() ?? 0, near, "\(bits) bits, near \(near)")
        }
    }

    func testCapabilitiesAndRegistry() throws {
        for uid in [DICOMJPEGLSCodec.lossless, DICOMJPEGLSCodec.nearLossless] {
            let capability = try XCTUnwrap(TransferSyntax(uid)).capability
            XCTAssertTrue(capability.canDecodePixelData, uid)
            XCTAssertTrue(capability.canEncodePixelData, uid)
            XCTAssertTrue(DICOMCodecRegistry.decoder(for: uid) is DICOMJPEGLSCodec, uid)
        }
    }

    func testMalformedStreamsAreRejectedWithoutCrashing() throws {
        let codec = DICOMJPEGLSCodec()
        let stream = try resource("syn_rgb_b16_i1", "jls")
        let good = description(rows: 29, columns: 31, samples: 3, bits: 16)
        XCTAssertThrowsError(try codec.decode(stream, description: description(rows: 28, columns: 31, samples: 3, bits: 16)))
        XCTAssertThrowsError(try codec.decode(stream, description: description(rows: 29, columns: 31, samples: 3, bits: 8)))
        for length in stride(from: 4, to: stream.count, by: 37) {
            _ = try? codec.decode(stream.prefix(length), description: good)
        }
        // Flipping entropy-coded bytes must fail or decode, never trap.
        var bytes = [UInt8](stream)
        for index in stride(from: 40, to: bytes.count - 2, by: 53) {
            bytes[index] ^= 0x5A
            _ = try? codec.decode(Data(bytes), description: good)
        }
        // A scan selecting a mapping table is not supported.
        var mapped = [UInt8](try resource("syn_b2_n0", "jls"))
        let sos = try XCTUnwrap((0..<(mapped.count - 1)).first { mapped[$0] == 0xFF && mapped[$0 + 1] == 0xDA })
        mapped[sos + 6] = 1
        XCTAssertThrowsError(try codec.decode(Data(mapped), description: description(rows: 37, columns: 53, samples: 1, bits: 2)))
        XCTAssertThrowsError(try codec.encode(Data(count: 4), description: DICOMPixelDescription(
            rows: 1, columns: 1, samplesPerPixel: 2, photometricInterpretation: .rgb, bitsAllocated: 16, bitsStored: 16,
            highBit: 15, isSigned: false, planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: false)))
    }

    /// The full T.87 conformance suite, when a directory holding it (as
    /// distributed with CharLS in test/data/conformance) is supplied.
    func testFullConformanceSuiteWhenAvailable() throws {
        guard let path = ProcessInfo.processInfo.environment["DCMSWIFT_JPEGLS_CONFORMANCE"] else {
            throw XCTSkip("Set DCMSWIFT_JPEGLS_CONFORMANCE to the T.87 conformance directory")
        }
        let directory = URL(fileURLWithPath: path)
        func pnm(_ name: String) throws -> [[Int]] {
            let bytes = [UInt8](try Data(contentsOf: directory.appendingPathComponent(name)))
            let header = String(decoding: bytes.prefix(32), as: UTF8.self).split(whereSeparator: \.isWhitespace)
            let width = Int(header[1])!, height = Int(header[2])!, wide = Int(header[3])! > 255
            let channels = header[0] == "P6" ? 3 : 1
            let count = width * height * channels
            let body = Array(bytes.suffix(count * (wide ? 2 : 1)))
            let values = (0..<count).map { wide ? Int(body[2 * $0]) << 8 | Int(body[2 * $0 + 1]) : Int(body[$0]) }
            return (0..<channels).map { c in stride(from: c, to: count, by: channels).map { values[$0] } }
        }
        let color = try pnm("test8.ppm")
        let subsampled = try pnm("test8r.pgm") + pnm("test8gr4.pgm") + pnm("test8bs2.pgm")
        let cases: [(String, [[Int]], Int)] = [
            ("t8c0e0", color, 0), ("t8c0e3", color, 3), ("t8c1e0", color, 0), ("t8c1e3", color, 3),
            ("t8c2e0", color, 0), ("t8c2e3", color, 3), ("t8sse0", subsampled, 0), ("t8sse3", subsampled, 3),
            ("t8nde0", try pnm("test8bs2.pgm"), 0), ("t8nde3", try pnm("test8bs2.pgm"), 3),
            ("t16e0", try pnm("test16.pgm"), 0), ("t16e3", try pnm("test16.pgm"), 3),
        ]
        for (name, expected, near) in cases {
            let stream = try JPEGLSStream([UInt8](try Data(contentsOf: directory.appendingPathComponent("\(name).jls"))))
            let planes = try JPEGLSScanDecoder(stream: stream).decode()
            XCTAssertEqual(planes.map(\.count), expected.map(\.count), name)
            for (plane, reference) in zip(planes, expected) {
                XCTAssertLessThanOrEqual(zip(plane, reference).map { abs(Int($0) - $1) }.max() ?? 0, near, name)
            }
        }
    }
}
