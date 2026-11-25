import XCTest
import COpenJPEG
@testable import DcmSwift

/// Non-regression tests of the vendored C codecs, for geometries and streams
/// that DcmSwift's own APIs do not produce. Without a sanitizer, a memory
/// error shows only as an occasional crash: Scripts/crosscheck/openjpeg_asan.sh
/// runs the same cases under AddressSanitizer.
final class DcmSwiftVendoredCodecTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dcmswift-vendored-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    /// The 8-bit sample of a test image at (x, y).
    private func sample(_ x: Int, _ y: Int) -> Int32 { Int32((x * 7 + y * 13) & 0xFF) }

    /// Encodes a tiled grayscale image losslessly with OpenJPEG directly.
    private func encodeTiled(
        width: Int, height: Int, tileWidth: Int, tileHeight: Int, resolutions: Int, to url: URL
    ) throws {
        var component = opj_image_cmptparm_t()
        component.dx = 1
        component.dy = 1
        component.w = OPJ_UINT32(width)
        component.h = OPJ_UINT32(height)
        component.prec = 8
        let image = try XCTUnwrap(opj_image_create(1, &component, OPJ_CLRSPC_GRAY))
        defer { opj_image_destroy(image) }
        image.pointee.x1 = OPJ_UINT32(width)
        image.pointee.y1 = OPJ_UINT32(height)
        for y in 0..<height {
            for x in 0..<width { image.pointee.comps[0].data[y * width + x] = sample(x, y) }
        }

        var parameters = opj_cparameters_t()
        opj_set_default_encoder_parameters(&parameters)
        parameters.tcp_numlayers = 1
        parameters.cp_disto_alloc = 1
        parameters.numresolution = Int32(resolutions)
        parameters.tile_size_on = 1
        parameters.cp_tdx = Int32(tileWidth)
        parameters.cp_tdy = Int32(tileHeight)
        parameters.irreversible = 0
        let codec = try XCTUnwrap(opj_create_compress(OPJ_CODEC_J2K))
        defer { opj_destroy_codec(codec) }
        XCTAssertNotEqual(opj_setup_encoder(codec, &parameters, image), 0)
        let stream = try XCTUnwrap(opj_stream_create_default_file_stream(url.path, 0))
        defer { opj_stream_destroy(stream) }
        XCTAssertNotEqual(opj_start_compress(codec, image, stream), 0)
        XCTAssertNotEqual(opj_encode(codec, stream), 0)
        XCTAssertNotEqual(opj_end_compress(codec, stream), 0)
    }

    /// A short edge tile makes the lower resolution levels zero rows high at
    /// an odd start: the 5/3 vertical pass then addressed rows outside its
    /// scratch buffer (opj_dwt_encode_and_deinterleave_v). DcmSwift's encoder
    /// never tiles, so its own frames cannot reach this case.
    func testReversibleEncodingOfEmptyResolutionLevelsStaysInBounds() throws {
        for (width, height, tileWidth, tileHeight, resolutions) in [
            (1, 6, 4, 5, 3), (33, 37, 32, 36, 5),
            // Controls without an empty resolution level.
            (8, 8, 4, 4, 3), (17, 16, 16, 16, 5),
        ] {
            let label = "\(width)x\(height), tiles \(tileWidth)x\(tileHeight), \(resolutions) resolutions"
            let url = directory.appendingPathComponent("tiled-\(width)x\(height).j2k")
            try encodeTiled(width: width, height: height, tileWidth: tileWidth, tileHeight: tileHeight,
                            resolutions: resolutions, to: url)
            let decoded = try DICOMJPEG2000Codec().decode(Data(contentsOf: url), description: DICOMPixelDescription(
                rows: height, columns: width, samplesPerPixel: 1, photometricInterpretation: .monochrome2,
                bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false, planarConfiguration: 0,
                numberOfFrames: 1, isEncapsulated: true))
            let expected = (0..<(width * height)).map { UInt8(sample($0 % width, $0 / width)) }
            XCTAssertEqual([UInt8](decoded.data), expected, label)
        }
    }

    // MARK: Tile-part headers (opj_j2k_read_sot, opj_j2k_read_sod)

    private struct TilePart {
        var index: UInt8
        var count: UInt8
        /// Psot; nil writes the actual length of the tile-part.
        var length: Int?
        var data: [UInt8] = [0x00]
    }

    private func u16(_ value: Int) -> [UInt8] { [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
    private func u32(_ value: Int) -> [UInt8] { u16(value >> 16 & 0xFFFF) + u16(value & 0xFFFF) }

    /// A 4x4 8-bit codestream with one tile, one resolution, and the given
    /// tile-parts of tile 0, optionally announced by a TLM segment
    /// (one-byte tile indices, four-byte lengths) and truncated.
    private func codestream(_ parts: [TilePart], tlm: [Int]? = nil, keeping prefix: Int? = nil) -> Data {
        var bytes: [UInt8] = [0xFF, 0x4F, 0xFF, 0x51]
        bytes += u16(41)
        bytes += u16(0)
        for value in [4, 4, 0, 0, 4, 4, 0, 0] { bytes += u32(value) }
        bytes += u16(1)
        bytes += [7, 1, 1]
        // COD: LRCP, one layer, no transform, no decomposition, 64x64 blocks, 5/3.
        bytes += [0xFF, 0x52]
        bytes += u16(12)
        bytes += [0, 0, 0, 1, 0, 0, 4, 4, 0, 1]
        // QCD: no quantization, one guard bit.
        bytes += [0xFF, 0x5C]
        bytes += u16(4)
        bytes += [0x20, 0x40]
        if let tlm {
            bytes += [0xFF, 0x55]
            bytes += u16(4 + 5 * tlm.count)
            bytes += [0, 0x50]
            for length in tlm {
                bytes += [0]
                bytes += u32(length)
            }
        }
        for part in parts {
            bytes += [0xFF, 0x90]
            bytes += u16(10)
            bytes += u16(0)
            bytes += u32(part.length ?? 14 + part.data.count)
            bytes += [part.index, part.count, 0xFF, 0x93]
            bytes += part.data
        }
        bytes += [0xFF, 0xD9]
        return Data(bytes.prefix(prefix ?? bytes.count))
    }

    private let tiny = DICOMPixelDescription(
        rows: 4, columns: 4, samplesPerPixel: 1, photometricInterpretation: .monochrome2, bitsAllocated: 8,
        bitsStored: 8, highBit: 7, isSigned: false, planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: true)

    func testForgedCodestreamDecodes() throws {
        // The control: one well-formed tile-part, then the same with a TLM.
        let decoded = try DICOMJPEG2000Codec().decode(codestream([TilePart(index: 0, count: 1)]), description: tiny)
        XCTAssertEqual(decoded.data.count, 16)
        XCTAssertNoThrow(try DICOMJPEG2000Codec().decode(
            codestream([TilePart(index: 0, count: 1)], tlm: [15]), description: tiny))
    }

    /// A TLM segment announces one tile-part of tile 0, but the codestream
    /// holds a second one whose SOT leaves the tile-part count unknown
    /// (TNsot = 0): the index of tile-parts, sized from TLM, was written past
    /// its end when the second SOD was read.
    func testTileIndexBuiltFromTLMIsNotOverrun() {
        let stream = codestream([TilePart(index: 0, count: 0), TilePart(index: 1, count: 0)], tlm: [15])
        // The decoder may accept or refuse the stream; it must stay in bounds.
        _ = try? DICOMJPEG2000Codec().decode(stream, description: tiny)
        let more = codestream((0..<4).map { TilePart(index: UInt8($0), count: 0) }, tlm: [15, 15])
        _ = try? DICOMJPEG2000Codec().decode(more, description: tiny)
    }

    /// Psot too large, too small, zero, a truncated last tile-part, repeated
    /// or out-of-order tile-part indices, and inconsistent TLM lengths are
    /// refused or tolerated, without reading or writing out of bounds.
    func testMalformedTilePartLengthsStayInBounds() {
        let cases: [(String, Data)] = [
            ("Psot beyond the end", codestream([TilePart(index: 0, count: 1, length: 4000)])),
            ("Psot beyond the end, last", codestream([TilePart(index: 0, count: 1, length: 0x7FFF_FFF0)])),
            ("Psot below 14", codestream([TilePart(index: 0, count: 1, length: 13)])),
            ("Psot of 12, empty", codestream([TilePart(index: 0, count: 1, length: 12)])),
            ("Psot of 0", codestream([TilePart(index: 0, count: 1, length: 0)])),
            ("Psot of 0 before another tile-part",
             codestream([TilePart(index: 0, count: 2, length: 0), TilePart(index: 1, count: 2)])),
            ("Psot shorter than the data", codestream([TilePart(index: 0, count: 1, length: 14, data: [0, 0, 0, 0])])),
            ("truncated in SOT", codestream([TilePart(index: 0, count: 1)], keeping: 64)),
            ("truncated after SOD", codestream([TilePart(index: 0, count: 1, data: [0, 0, 0, 0])], keeping: 76)),
            ("truncated with Psot of 0", codestream([TilePart(index: 0, count: 1, length: 0, data: [0, 0, 0])],
                                                    keeping: 75)),
            ("repeated tile-part", codestream([TilePart(index: 0, count: 2), TilePart(index: 0, count: 2)])),
            ("tile-part out of order", codestream([TilePart(index: 1, count: 2), TilePart(index: 0, count: 2)])),
            ("TPsot at TNsot", codestream([TilePart(index: 0, count: 1), TilePart(index: 1, count: 1)])),
            ("more tile-parts than TLM", codestream([TilePart(index: 0, count: 2), TilePart(index: 1, count: 2)],
                                                    tlm: [15])),
            ("TLM lengths beyond the end", codestream([TilePart(index: 0, count: 1)], tlm: [0x7FFF_0000])),
            ("TLM lengths of 0", codestream([TilePart(index: 0, count: 0), TilePart(index: 1, count: 0)],
                                            tlm: [0, 0])),
        ]
        for (name, stream) in cases {
            // Refused or tolerated; never out of bounds (see openjpeg_asan.sh).
            if let decoded = try? DICOMJPEG2000Codec().decode(stream, description: tiny) {
                XCTAssertEqual(decoded.data.count, 16, name)
            }
        }
    }
}
