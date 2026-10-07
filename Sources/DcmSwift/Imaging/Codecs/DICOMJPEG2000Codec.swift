import Foundation
import COpenJPEG

/// JPEG 2000 (ISO/IEC 15444-1) and High-Throughput JPEG 2000 (ISO/IEC
/// 15444-15) Image Compression through the vendored OpenJPEG 2.5.4.
///
/// Decoding covers the Part 1 syntaxes .90 and .91 and the HTJ2K syntaxes
/// .201, .202, and .203, from raw codestreams or JP2 files. When the
/// codestream applies the multiple-component transform (YBR_RCT or YBR_ICT),
/// OpenJPEG inverts it and frames are returned as RGB. Encoding writes Part 1
/// codestreams, reversible or irreversible.
public struct DICOMJPEG2000Codec: DICOMPixelDataDecoder {
    public static let lossless = "1.2.840.10008.1.2.4.90"
    public static let lossy = "1.2.840.10008.1.2.4.91"
    public static let htj2kLossless = "1.2.840.10008.1.2.4.201"
    public static let htj2kLosslessRPCL = "1.2.840.10008.1.2.4.202"
    public static let htj2k = "1.2.840.10008.1.2.4.203"
    public var transferSyntaxUIDs: Set<String> {
        [Self.lossless, Self.lossy, Self.htj2kLossless, Self.htj2kLosslessRPCL, Self.htj2k]
    }

    /// The rate control of the encoder.
    public enum Quality: Sendable, Equatable {
        /// Reversible 5/3 wavelet: 1.2.840.10008.1.2.4.90.
        case lossless
        /// Irreversible 9/7 wavelet targeting a compression ratio, such as 10
        /// for 10:1: 1.2.840.10008.1.2.4.91.
        case compressionRatio(Double)
        /// Irreversible 9/7 wavelet targeting a peak signal-to-noise ratio in
        /// decibels: 1.2.840.10008.1.2.4.91.
        case peakSignalToNoiseRatio(Double)
    }

    public init() {}

    // MARK: Decoding

    public func decode(_ encodedFrame: Data, description: DICOMPixelDescription) throws -> DICOMDecodedFrame {
        let bytes = [UInt8](encodedFrame)
        let format: OPJ_CODEC_FORMAT
        if bytes.starts(with: [0xFF, 0x4F, 0xFF, 0x51]) {
            format = OPJ_CODEC_J2K
        } else if bytes.starts(with: [0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20]) {
            format = OPJ_CODEC_JP2
        } else {
            throw DICOMCodecError.corruptedData("JPEG 2000 data starts with neither SOC nor a JP2 signature")
        }

        let messages = OpenJPEGMessages()
        let source = OpenJPEGBuffer(bytes)
        // OpenJPEG holds unretained pointers to both until the codec and
        // stream are destroyed.
        defer { withExtendedLifetime((messages, source)) {} }
        guard let codec = opj_create_decompress(format) else {
            throw DICOMCodecError.unsupportedImage("OpenJPEG cannot create a decoder")
        }
        defer { opj_destroy_codec(codec) }
        messages.install(on: codec)
        var parameters = opj_dparameters_t()
        opj_set_default_decoder_parameters(&parameters)
        guard opj_setup_decoder(codec, &parameters) != 0, let stream = source.makeInputStream() else {
            throw messages.error("cannot set up the decoder")
        }
        defer { opj_stream_destroy(stream) }

        var imagePointer: UnsafeMutablePointer<opj_image_t>?
        guard opj_read_header(stream, codec, &imagePointer) != 0, let image = imagePointer else {
            throw messages.error("cannot read the codestream header")
        }
        defer { opj_image_destroy(image) }
        guard opj_decode(codec, stream, image) != 0, opj_end_decompress(codec, stream) != 0 else {
            throw messages.error("cannot decode the codestream")
        }

        let count = Int(image.pointee.numcomps)
        guard count == description.samplesPerPixel, let components = image.pointee.comps else {
            throw DICOMCodecError.corruptedData(
                "JPEG 2000 frame has \(count) components, image has \(description.samplesPerPixel)")
        }
        let cellBytes = description.bitsAllocated / 8
        guard cellBytes == 1 || cellBytes == 2 else {
            throw DICOMCodecError.unsupportedImage("JPEG 2000 in \(description.bitsAllocated) bits allocated")
        }
        let width = description.columns, height = description.rows
        for index in 0..<count {
            let component = components[index]
            guard Int(component.w) == width, Int(component.h) == height, component.data != nil else {
                throw DICOMCodecError.corruptedData(
                    "JPEG 2000 component \(index) is \(component.w)x\(component.h), image is \(width)x\(height)")
            }
            guard component.dx == 1, component.dy == 1 else {
                throw DICOMCodecError.unsupportedImage("subsampled JPEG 2000 components")
            }
            guard Int(component.prec) <= description.bitsAllocated else {
                throw DICOMCodecError.unsupportedImage(
                    "\(component.prec)-bit JPEG 2000 in \(description.bitsAllocated) bits allocated")
            }
        }

        let pixels = width * height
        var output = [UInt8](repeating: 0, count: pixels * count * cellBytes)
        output.withUnsafeMutableBufferPointer { out in
            for index in 0..<count {
                let data = components[index].data!
                for pixel in 0..<pixels {
                    let value = data[pixel]
                    let offset = (pixel * count + index) * cellBytes
                    out[offset] = UInt8(truncatingIfNeeded: value)
                    if cellBytes == 2 { out[offset + 1] = UInt8(truncatingIfNeeded: value >> 8) }
                }
            }
        }

        var photometric = description.photometricInterpretation
        if count == 3, Self.usesMultipleComponentTransform(bytes) {
            photometric = .rgb
        }
        return DICOMDecodedFrame(
            description: description.decodedFrame(photometricInterpretation: photometric, planarConfiguration: 0),
            data: Data(output))
    }

    /// Whether the main header's COD segment enables the multiple-component
    /// transform (ISO/IEC 15444-1 A.6.1), which OpenJPEG inverts.
    static func usesMultipleComponentTransform(_ bytes: [UInt8]) -> Bool {
        guard let start = codestreamStart(bytes) else { return false }
        var position = start + 2
        while position + 4 <= bytes.count, bytes[position] == 0xFF {
            let marker = bytes[position + 1]
            if marker == 0x90 || marker == 0x93 { return false }
            let length = Int(bytes[position + 2]) << 8 | Int(bytes[position + 3])
            if marker == 0x52 {
                // Lcod (2), Scod (1), progression order (1), layers (2), then
                // the multiple component transformation byte.
                return position + 8 < bytes.count && bytes[position + 8] != 0
            }
            guard length >= 2 else { return false }
            position += 2 + length
        }
        return false
    }

    /// The SOC marker of a raw codestream or of the JP2 contiguous
    /// codestream box.
    private static func codestreamStart(_ bytes: [UInt8]) -> Int? {
        if bytes.starts(with: [0xFF, 0x4F]) { return 0 }
        var position = 0
        while position + 8 <= bytes.count {
            var length = Int(bytes[position]) << 24 | Int(bytes[position + 1]) << 16
                | Int(bytes[position + 2]) << 8 | Int(bytes[position + 3])
            let type = bytes[(position + 4)..<(position + 8)]
            var header = 8
            if length == 1, position + 16 <= bytes.count {
                length = (0..<8).reduce(0) { $0 << 8 | Int(bytes[position + 8 + $1]) }
                header = 16
            }
            if type.elementsEqual(Array("jp2c".utf8)) { return position + header }
            guard length >= header else { return nil }
            position += length
        }
        return nil
    }

    // MARK: Encoding

    /// Encodes one native little endian frame (as described) to a JPEG 2000
    /// Part 1 codestream. Three-component frames use the multiple-component
    /// transform; the returned photometric interpretation is then YBR_RCT
    /// (lossless) or YBR_ICT (lossy), as PS3.5 8.2.4 requires.
    public func encode(
        _ frame: Data, description: DICOMPixelDescription, quality: Quality = .lossless,
        multipleComponentTransform: Bool = true
    ) throws -> (data: Data, photometric: DICOMPhotometricInterpretation) {
        let precision = description.bitsStored
        let samples = description.samplesPerPixel
        guard description.sampleFormat == .integer, (1...16).contains(precision),
              description.bitsAllocated == 8 || description.bitsAllocated == 16,
              samples == 1 || samples == 3,
              description.photometricInterpretation != .ybrFull422 else {
            throw DICOMCodecError.unsupportedImage(
                "JPEG 2000 encoding needs 1 to 16-bit integer samples in 8 or 16 bits, one or three per pixel")
        }
        let width = description.columns, height = description.rows
        let transform = samples == 3 && multipleComponentTransform

        var parameters = opj_cparameters_t()
        opj_set_default_encoder_parameters(&parameters)
        parameters.tcp_numlayers = 1
        parameters.tcp_mct = transform ? 1 : 0
        var resolutions = 1
        while resolutions < 6, (1 << resolutions) <= min(width, height) { resolutions += 1 }
        parameters.numresolution = Int32(resolutions)
        switch quality {
        case .lossless:
            parameters.irreversible = 0
            parameters.cp_disto_alloc = 1
            parameters.tcp_rates.0 = 0
        case .compressionRatio(let ratio):
            guard ratio >= 1 else { throw DICOMCodecError.unsupportedImage("compression ratio \(ratio)") }
            parameters.irreversible = 1
            parameters.cp_disto_alloc = 1
            parameters.tcp_rates.0 = Float(ratio)
        case .peakSignalToNoiseRatio(let psnr):
            guard psnr > 0 else { throw DICOMCodecError.unsupportedImage("PSNR \(psnr)") }
            parameters.irreversible = 1
            parameters.cp_fixed_quality = 1
            parameters.tcp_distoratio.0 = Float(psnr)
        }

        let stored = try DICOMNativePixelData(description: description.decodedFrame(), decodedFrames: frame)
            .storedValues(frame: 0)
        let mask = (Int64(1) << precision) - 1
        let signBit = Int64(1) << (precision - 1)

        var componentParameters = (0..<samples).map { _ -> opj_image_cmptparm_t in
            var component = opj_image_cmptparm_t()
            component.dx = 1
            component.dy = 1
            component.w = OPJ_UINT32(width)
            component.h = OPJ_UINT32(height)
            component.prec = OPJ_UINT32(precision)
            component.sgnd = description.isSigned ? 1 : 0
            return component
        }
        guard let image = opj_image_create(
            OPJ_UINT32(samples), &componentParameters, samples == 3 ? OPJ_CLRSPC_SRGB : OPJ_CLRSPC_GRAY) else {
            throw DICOMCodecError.unsupportedImage("OpenJPEG cannot allocate the image")
        }
        defer { opj_image_destroy(image) }
        image.pointee.x0 = 0
        image.pointee.y0 = 0
        image.pointee.x1 = OPJ_UINT32(width)
        image.pointee.y1 = OPJ_UINT32(height)
        for component in 0..<samples {
            let data = image.pointee.comps[component].data!
            for pixel in 0..<(width * height) {
                var value = stored[pixel * samples + component] & mask
                if description.isSigned, value & signBit != 0 { value -= mask + 1 }
                data[pixel] = OPJ_INT32(value)
            }
        }

        let messages = OpenJPEGMessages()
        let destination = OpenJPEGBuffer([])
        defer { withExtendedLifetime((messages, destination)) {} }
        guard let codec = opj_create_compress(OPJ_CODEC_J2K) else {
            throw DICOMCodecError.unsupportedImage("OpenJPEG cannot create an encoder")
        }
        defer { opj_destroy_codec(codec) }
        messages.install(on: codec)
        guard opj_setup_encoder(codec, &parameters, image) != 0 else {
            throw messages.error("cannot set up the encoder")
        }
        guard let stream = destination.makeOutputStream() else {
            throw DICOMCodecError.unsupportedImage("OpenJPEG cannot create an output stream")
        }
        defer { opj_stream_destroy(stream) }
        guard opj_start_compress(codec, image, stream) != 0, opj_encode(codec, stream) != 0,
              opj_end_compress(codec, stream) != 0 else {
            throw messages.error("cannot encode the frame")
        }
        var output = destination.bytes
        // Fragments have an even length (PS3.5 A.4).
        if output.count % 2 == 1 { output.append(0) }
        let photometric: DICOMPhotometricInterpretation = transform
            ? (quality == .lossless ? .ybrRCT : .ybrICT)
            : description.photometricInterpretation
        return (Data(output), photometric)
    }
}

/// Collects OpenJPEG's error messages for the thrown error.
private final class OpenJPEGMessages {
    var errors: [String] = []

    func install(on codec: UnsafeMutablePointer<opj_codec_t?>) {
        let context = Unmanaged.passUnretained(self).toOpaque()
        opj_set_error_handler(codec, { message, context in
            guard let message, let context else { return }
            let messages = Unmanaged<OpenJPEGMessages>.fromOpaque(context).takeUnretainedValue()
            messages.errors.append(String(cString: message).trimmingCharacters(in: .whitespacesAndNewlines))
        }, context)
        opj_set_warning_handler(codec, { _, _ in }, nil)
        opj_set_info_handler(codec, { _, _ in }, nil)
    }

    func error(_ step: String) -> DICOMCodecError {
        let detail = errors.isEmpty ? "" : ": " + errors.joined(separator: "; ")
        return .corruptedData("OpenJPEG \(step)\(detail)")
    }
}

/// An in-memory OpenJPEG stream. The instance must outlive the stream.
private final class OpenJPEGBuffer {
    var bytes: [UInt8]
    var position = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    private static func buffer(_ context: UnsafeMutableRawPointer?) -> OpenJPEGBuffer {
        Unmanaged<OpenJPEGBuffer>.fromOpaque(context!).takeUnretainedValue()
    }

    func makeInputStream() -> UnsafeMutablePointer<opj_stream_t?>? {
        guard let stream = opj_stream_create(OPJ_SIZE_T(1 << 16), 1) else { return nil }
        opj_stream_set_user_data(stream, Unmanaged.passUnretained(self).toOpaque(), nil)
        opj_stream_set_user_data_length(stream, OPJ_UINT64(bytes.count))
        opj_stream_set_read_function(stream) { destination, count, context in
            let buffer = OpenJPEGBuffer.buffer(context)
            let available = buffer.bytes.count - buffer.position
            // size_t imports as Int: (OPJ_SIZE_T)-1 signals the end of the data.
            guard available > 0, let destination else { return -1 }
            let length = min(Int(count), available)
            buffer.bytes.withUnsafeBytes { source in
                destination.copyMemory(from: source.baseAddress! + buffer.position, byteCount: length)
            }
            buffer.position += length
            return OPJ_SIZE_T(length)
        }
        opj_stream_set_skip_function(stream) { count, context in
            let buffer = OpenJPEGBuffer.buffer(context)
            let target = max(0, min(buffer.bytes.count, buffer.position + Int(count)))
            let skipped = target - buffer.position
            buffer.position = target
            return OPJ_OFF_T(skipped)
        }
        opj_stream_set_seek_function(stream) { offset, context in
            let buffer = OpenJPEGBuffer.buffer(context)
            guard offset >= 0, Int(offset) <= buffer.bytes.count else { return 0 }
            buffer.position = Int(offset)
            return 1
        }
        return stream
    }

    func makeOutputStream() -> UnsafeMutablePointer<opj_stream_t?>? {
        guard let stream = opj_stream_create(OPJ_SIZE_T(1 << 16), 0) else { return nil }
        opj_stream_set_user_data(stream, Unmanaged.passUnretained(self).toOpaque(), nil)
        opj_stream_set_write_function(stream) { source, count, context in
            let buffer = OpenJPEGBuffer.buffer(context)
            guard let source else { return -1 }
            let length = Int(count)
            let end = buffer.position + length
            if end > buffer.bytes.count { buffer.bytes += [UInt8](repeating: 0, count: end - buffer.bytes.count) }
            buffer.bytes.withUnsafeMutableBytes { destination in
                (destination.baseAddress! + buffer.position).copyMemory(from: source, byteCount: length)
            }
            buffer.position = end
            return OPJ_SIZE_T(length)
        }
        opj_stream_set_skip_function(stream) { count, context in
            let buffer = OpenJPEGBuffer.buffer(context)
            let target = max(0, buffer.position + Int(count))
            if target > buffer.bytes.count { buffer.bytes += [UInt8](repeating: 0, count: target - buffer.bytes.count) }
            let skipped = target - buffer.position
            buffer.position = target
            return OPJ_OFF_T(skipped)
        }
        opj_stream_set_seek_function(stream) { offset, context in
            let buffer = OpenJPEGBuffer.buffer(context)
            guard offset >= 0 else { return 0 }
            if Int(offset) > buffer.bytes.count {
                buffer.bytes += [UInt8](repeating: 0, count: Int(offset) - buffer.bytes.count)
            }
            buffer.position = Int(offset)
            return 1
        }
        return stream
    }
}
