import XCTest
import COpenJPEG
@testable import DcmSwift

/// Non-regression tests of the vendored C codecs, for geometries and streams
/// that DcmSwift's own APIs do not produce. Run them under AddressSanitizer
/// (`swift test --sanitize=address`) to see memory errors.
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
}
