import Foundation
import COpenJPEG
import COpenJPH

/// JPEG 2000 (ISO/IEC 15444-1) and High-Throughput JPEG 2000 (ISO/IEC
/// 15444-15) Image Compression through the vendored OpenJPEG 2.5.4 and
/// OpenJPH 0.32.0.
///
/// Decoding (OpenJPEG) covers the Part 1 syntaxes .90 and .91, the Part 2
/// multi-component syntaxes .92 and .93, and the HTJ2K syntaxes .201, .202,
/// and .203, from raw codestreams or JP2 files. When the codestream applies
/// the multiple-component transform (YBR_RCT or YBR_ICT), OpenJPEG inverts it
/// and frames are returned as RGB. Part 2 multiple component transformations
/// (ISO/IEC 15444-2 Annex J) are inverted by `JPEG2000ComponentTransform`
/// after OpenJPEG decoded the codestream components. `encode` writes Part 1
/// codestreams (OpenJPEG) and `encodeHTJ2K` HTJ2K codestreams (OpenJPH).
public struct DICOMJPEG2000Codec: DICOMPixelDataCollectionDecoder {
    public static let lossless = "1.2.840.10008.1.2.4.90"
    public static let lossy = "1.2.840.10008.1.2.4.91"
    public static let partTwoLossless = "1.2.840.10008.1.2.4.92"
    public static let partTwo = "1.2.840.10008.1.2.4.93"
    public static let htj2kLossless = "1.2.840.10008.1.2.4.201"
    public static let htj2kLosslessRPCL = "1.2.840.10008.1.2.4.202"
    public static let htj2k = "1.2.840.10008.1.2.4.203"
    public var transferSyntaxUIDs: Set<String> {
        [Self.lossless, Self.lossy, Self.partTwoLossless, Self.partTwo,
         Self.htj2kLossless, Self.htj2kLosslessRPCL, Self.htj2k]
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

    /// The HTJ2K Transfer Syntax to encode for (PS3.5 A.4.4).
    public enum HTJ2KMode: Sendable, Equatable {
        /// Reversible: 1.2.840.10008.1.2.4.201.
        case lossless
        /// Reversible, RPCL progression, TLM markers, and enough
        /// decompositions for a base resolution of at most 64:
        /// 1.2.840.10008.1.2.4.202.
        case losslessRPCL
        /// Irreversible with the given base quantization step (smaller is
        /// better, 0.005 is visually lossless for most images):
        /// 1.2.840.10008.1.2.4.203.
        case irreversible(quantizationStep: Float)

        public var transferSyntaxUID: String {
            switch self {
            case .lossless: return DICOMJPEG2000Codec.htj2kLossless
            case .losslessRPCL: return DICOMJPEG2000Codec.htj2kLosslessRPCL
            case .irreversible: return DICOMJPEG2000Codec.htj2k
            }
        }
    }

    public init() {}

    // MARK: Decoding

    /// Decodes a codestream holding one frame.
    public func decode(_ encodedFrame: Data, description: DICOMPixelDescription) throws -> DICOMDecodedFrame {
        let frames = try decodeCollection(encodedFrame, description: description)
        guard frames.count == 1 else {
            throw DICOMCodecError.corruptedData("JPEG 2000 codestream holds \(frames.count) frames, 1 expected")
        }
        return frames[0]
    }

    /// Decodes a codestream that may hold several frames: a JPEG 2000 Part 2
    /// component collection (PS3.5 A.4.4), whose reconstructed image
    /// components are the samples of consecutive frames.
    public func decodeCollection(_ encoded: Data, description: DICOMPixelDescription) throws -> [DICOMDecodedFrame] {
        var bytes = [UInt8](encoded)
        let format: OPJ_CODEC_FORMAT
        if bytes.starts(with: [0xFF, 0x4F, 0xFF, 0x51]) {
            format = OPJ_CODEC_J2K
        } else if bytes.starts(with: [0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20]) {
            format = OPJ_CODEC_JP2
        } else {
            throw DICOMCodecError.corruptedData("JPEG 2000 data starts with neither SOC nor a JP2 signature")
        }
        let partOneTransform = Self.usesMultipleComponentTransform(bytes)

        // A Part 2 codestream is decoded to its codestream components as a
        // Part 1 one, then the multiple component transformation is inverted.
        var codestream: JPEG2000Codestream?
        if let start = Self.codestreamStart(bytes), start + 8 <= bytes.count,
           bytes[start + 6] & 0x80 != 0 {
            let parsed = try JPEG2000Codestream(Array(bytes[start...]))
            let extensions = parsed.capabilities & ~(JPEG2000Codestream.partTwoCapability
                | JPEG2000Codestream.multipleComponentCapability)
            guard parsed.capabilities & 0x4000 == 0, extensions == 0 else {
                throw DICOMCodecError.unsupportedImage(String(
                    format: "JPEG 2000 Part 2 capabilities 0x%04X: DICOM allows only the multiple component "
                        + "transformation (PS3.5 A.4.4)", parsed.capabilities))
            }
            guard parsed.imageEnd.x - parsed.imageOrigin.x == description.columns,
                  parsed.imageEnd.y - parsed.imageOrigin.y == description.rows else {
                throw DICOMCodecError.corruptedData(
                    "JPEG 2000 image is \(parsed.imageEnd.x - parsed.imageOrigin.x)x"
                        + "\(parsed.imageEnd.y - parsed.imageOrigin.y), image is \(description.columns)x\(description.rows)")
            }
            bytes.replaceSubrange(start..., with: parsed.partOneBytes)
            codestream = parsed
        }

        let decoded = try Self.openJPEGDecode(bytes, format: format)
        let image = decoded.image
        let count = Int(image.pointee.numcomps)
        guard count > 0, let components = image.pointee.comps else {
            throw DICOMCodecError.corruptedData("JPEG 2000 image without components")
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
        }

        if let codestream, codestream.usesMultipleComponentTransformCapability {
            return try Self.inverseMultipleComponentTransform(
                components: components, codestream: codestream, description: description)
        }

        var assembler = try FrameAssembler(components: count, description: description)
        for index in 0..<count where Int(components[index].prec) > description.bitsAllocated {
            throw DICOMCodecError.unsupportedImage(
                "\(components[index].prec)-bit JPEG 2000 in \(description.bitsAllocated) bits allocated")
        }
        assembler.write { writer in
            for index in 0..<count {
                let data = components[index].data!
                for pixel in 0..<(width * height) {
                    writer.set(component: index, pixel: pixel, value: Int64(data[pixel]))
                }
            }
        }
        var photometric = description.photometricInterpretation
        if count == 3, partOneTransform {
            photometric = .rgb
        }
        return assembler.frames(photometric: photometric)
    }

    /// Inverts the JPEG 2000 Part 2 multiple component transformation
    /// (ISO/IEC 15444-2 Annex J) tile by tile, from codestream components
    /// that OpenJPEG decoded with the Part 2 markers neutralized.
    private static func inverseMultipleComponentTransform(
        components: UnsafeMutablePointer<opj_image_comp_t>, codestream: JPEG2000Codestream,
        description: DICOMPixelDescription
    ) throws -> [DICOMDecodedFrame] {
        let inputs = codestream.components
        guard let outputs = codestream.outputComponents else {
            throw DICOMCodecError.corruptedData("JPEG 2000 Part 2 codestream without a CBD segment (A.3.6)")
        }
        guard let widest = outputs.map(\.precision).max(), widest <= description.bitsAllocated else {
            throw DICOMCodecError.unsupportedImage(
                "JPEG 2000 Part 2 output components exceed \(description.bitsAllocated) bits allocated")
        }
        var assembler = try FrameAssembler(components: outputs.count, description: description)
        let width = description.columns
        let data = (0..<inputs.count).map { components[$0].data! }
        // Annex J applies no DC level shift, except in tiles without stages.
        let shifts = inputs.map { $0.isSigned ? 0.0 : Double(1 << ($0.precision - 1)) }
        let ranges = outputs.map { component -> ClosedRange<Double> in
            component.isSigned
                ? -Double(1 << (component.precision - 1))...Double((1 << (component.precision - 1)) - 1)
                : 0...Double((1 << component.precision) - 1)
        }

        // The transform of each tile (J.2.1: none where Nmco = 0 or where
        // COD does not signal a Part 2 transform).
        let main = try JPEG2000ComponentTransform.make(
            tile: nil, main: codestream.main, codestreamComponents: inputs.count, outputComponents: outputs.count)
        let tiles = try (0..<(codestream.tileColumns * codestream.tileRows)).map { tile in
            let segments = codestream.tiles[tile]
            guard (segments?.transformType ?? codestream.main.transformType ?? 0) & 0x06 != 0 else {
                return (tile: tile, transform: JPEG2000ComponentTransform?.none)
            }
            guard let segments, segments.definesTransform else { return (tile, main) }
            return (tile, try JPEG2000ComponentTransform.make(
                tile: segments, main: codestream.main,
                codestreamComponents: inputs.count, outputComponents: outputs.count))
        }

        assembler.write { writer in
            for (tile, transform) in tiles {
                let area = codestream.tileArea(tile)
                let scales = inputs.indices.map { 1 / codestream.decodedScale(tile: tile, component: $0) }
                func write(_ index: Int, _ pixel: Int, _ value: Double) {
                    // Irreversible arrays may hold NaN, which clamps to the minimum.
                    let rounded = value.isNaN ? ranges[index].lowerBound : value.rounded()
                    let clamped = min(max(rounded, ranges[index].lowerBound), ranges[index].upperBound)
                    writer.set(component: index, pixel: pixel, value: Int64(clamped))
                }
                // Rows are independent: each worker has its own evaluator.
                DispatchQueue.concurrentPerform(iterations: area.y.count) { row in
                    let y = area.y.lowerBound + row
                    guard let transform else {
                        // Level shifted codestream components (J.2.1).
                        for x in area.x {
                            let pixel = y * width + x
                            for index in outputs.indices {
                                let value = index < inputs.count
                                    ? Double(data[index][pixel]) * scales[index] + shifts[index] : 0
                                write(index, pixel, value)
                            }
                        }
                        return
                    }
                    let evaluator = JPEG2000ComponentTransform.Evaluator(transform)
                    for x in area.x {
                        let pixel = y * width + x
                        for index in inputs.indices {
                            evaluator.setInput(index, Double(data[index][pixel]) * scales[index])
                        }
                        evaluator.run()
                        let result = evaluator.output
                        for index in outputs.indices { write(index, pixel, result[index]) }
                    }
                }
            }
        }

        var photometric = description.photometricInterpretation
        if photometric == .ybrRCT || photometric == .ybrICT {
            photometric = .rgb
        }
        return assembler.frames(photometric: photometric)
    }

    /// Decodes with OpenJPEG; the image is destroyed with the result.
    private static func openJPEGDecode(_ bytes: [UInt8], format: OPJ_CODEC_FORMAT) throws -> OpenJPEGImage {
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
        // Code-blocks are decoded in parallel; the result does not depend on
        // the number of threads.
        if opj_has_thread_support() != 0 {
            _ = opj_codec_set_threads(codec, Int32(min(ProcessInfo.processInfo.activeProcessorCount, 16)))
        }

        var imagePointer: UnsafeMutablePointer<opj_image_t>?
        guard opj_read_header(stream, codec, &imagePointer) != 0, let image = imagePointer else {
            throw messages.error("cannot read the codestream header")
        }
        let decoded = OpenJPEGImage(image)
        guard opj_decode(codec, stream, image) != 0, opj_end_decompress(codec, stream) != 0 else {
            throw messages.error("cannot decode the codestream")
        }
        return decoded
    }

    /// Whether the main header's COD segment enables the Part 1
    /// multiple-component transform (ISO/IEC 15444-1 A.6.1), which OpenJPEG
    /// inverts.
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
                return position + 8 < bytes.count && bytes[position + 8] == 1
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

        let stored = try DICOMNativePixelData(description: description.decodedFrame(), decodedFrames: frame)
            .storedValues(frame: 0)
        let mask = (Int64(1) << precision) - 1
        let signBit = Int64(1) << (precision - 1)
        let planes = (0..<(samples * width * height)).map { index -> Int32 in
            let component = index / (width * height), pixel = index % (width * height)
            var value = stored[pixel * samples + component] & mask
            if description.isSigned, value & signBit != 0 { value -= mask + 1 }
            return Int32(value)
        }
        var output = try Self.openJPEGEncode(
            planes, width: width, height: height,
            components: Array(repeating: (precision, description.isSigned), count: samples),
            quality: quality, multipleComponentTransform: transform)
        // Fragments have an even length (PS3.5 A.4).
        if output.count % 2 == 1 { output.append(0) }
        let photometric: DICOMPhotometricInterpretation = transform
            ? (quality == .lossless ? .ybrRCT : .ybrICT)
            : description.photometricInterpretation
        return (Data(output), photometric)
    }
}

extension DICOMJPEG2000Codec {
    /// Encodes component planes (one after the other, row by row) to a JPEG
    /// 2000 codestream with OpenJPEG; the codestream is not padded.
    static func openJPEGEncode(
        _ planes: [Int32], width: Int, height: Int, components: [(precision: Int, isSigned: Bool)],
        quality: Quality, multipleComponentTransform: Bool
    ) throws -> [UInt8] {
        var parameters = opj_cparameters_t()
        opj_set_default_encoder_parameters(&parameters)
        parameters.tcp_numlayers = 1
        parameters.tcp_mct = multipleComponentTransform ? 1 : 0
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

        var componentParameters = components.map { component -> opj_image_cmptparm_t in
            var parameters = opj_image_cmptparm_t()
            parameters.dx = 1
            parameters.dy = 1
            parameters.w = OPJ_UINT32(width)
            parameters.h = OPJ_UINT32(height)
            parameters.prec = OPJ_UINT32(component.precision)
            parameters.sgnd = component.isSigned ? 1 : 0
            return parameters
        }
        guard let image = opj_image_create(
            OPJ_UINT32(components.count), &componentParameters,
            components.count == 3 ? OPJ_CLRSPC_SRGB : OPJ_CLRSPC_GRAY) else {
            throw DICOMCodecError.unsupportedImage("OpenJPEG cannot allocate the image")
        }
        defer { opj_image_destroy(image) }
        image.pointee.x0 = 0
        image.pointee.y0 = 0
        image.pointee.x1 = OPJ_UINT32(width)
        image.pointee.y1 = OPJ_UINT32(height)
        planes.withUnsafeBufferPointer { source in
            for index in components.indices {
                image.pointee.comps[index].data!.update(
                    from: source.baseAddress! + index * width * height, count: width * height)
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
        if opj_has_thread_support() != 0 {
            _ = opj_codec_set_threads(codec, Int32(min(ProcessInfo.processInfo.activeProcessorCount, 16)))
        }
        guard let stream = destination.makeOutputStream() else {
            throw DICOMCodecError.unsupportedImage("OpenJPEG cannot create an output stream")
        }
        defer { opj_stream_destroy(stream) }
        guard opj_start_compress(codec, image, stream) != 0, opj_encode(codec, stream) != 0,
              opj_end_compress(codec, stream) != 0 else {
            throw messages.error("cannot encode the frame")
        }
        return destination.bytes
    }
}

extension DICOMJPEG2000Codec {
    /// Encodes one native little endian frame (as described) to an HTJ2K
    /// codestream with OpenJPH. Three-component frames use the
    /// multiple-component transform; the returned photometric interpretation
    /// is then YBR_RCT (reversible) or YBR_ICT (irreversible).
    public func encodeHTJ2K(
        _ frame: Data, description: DICOMPixelDescription, mode: HTJ2KMode = .lossless,
        multipleComponentTransform: Bool = true
    ) throws -> (data: Data, photometric: DICOMPhotometricInterpretation) {
        let precision = description.bitsStored
        let samples = description.samplesPerPixel
        guard description.sampleFormat == .integer, (1...16).contains(precision),
              description.bitsAllocated == 8 || description.bitsAllocated == 16,
              samples == 1 || samples == 3,
              description.photometricInterpretation != .ybrFull422 else {
            throw DICOMCodecError.unsupportedImage(
                "HTJ2K encoding needs 1 to 16-bit integer samples in 8 or 16 bits, one or three per pixel")
        }
        let width = description.columns, height = description.rows
        let transform = samples == 3 && multipleComponentTransform
        let reversible: Bool
        var step: Float = 0
        switch mode {
        case .lossless, .losslessRPCL:
            reversible = true
        case .irreversible(let quantizationStep):
            guard quantizationStep > 0, quantizationStep.isFinite else {
                throw DICOMCodecError.unsupportedImage("quantization step \(quantizationStep)")
            }
            reversible = false
            step = quantizationStep
        }
        // Five decompositions, or more until the base resolution is at most
        // 64 samples wide and high (required for .202).
        var decompositions = 5
        while decompositions < 32, (max(width, height) + (1 << decompositions) - 1) >> decompositions > 64 {
            decompositions += 1
        }

        let stored = try DICOMNativePixelData(description: description.decodedFrame(), decodedFrames: frame)
            .storedValues(frame: 0)
        let mask = (Int64(1) << precision) - 1
        let signBit = Int64(1) << (precision - 1)
        let pixels = width * height
        var planes = [Int32](repeating: 0, count: pixels * samples)
        for component in 0..<samples {
            for pixel in 0..<pixels {
                var value = stored[pixel * samples + component] & mask
                if description.isSigned, value & signBit != 0 { value -= mask + 1 }
                planes[component * pixels + pixel] = Int32(value)
            }
        }

        var output: UnsafeMutablePointer<UInt8>?
        var size = 0
        var message = [CChar](repeating: 0, count: 512)
        let status = "RPCL".withCString { order -> Int32 in
            var parameters = copenjph_parameters(
                width: UInt32(width), height: UInt32(height), components: UInt32(samples),
                bit_depth: UInt32(precision), is_signed: description.isSigned ? 1 : 0,
                reversible: reversible ? 1 : 0, quantization_step: step,
                color_transform: transform ? 1 : 0, decompositions: UInt32(decompositions),
                progression_order: order, tlm_markers: mode == .losslessRPCL ? 1 : 0)
            return planes.withUnsafeBufferPointer { buffer in
                copenjph_encode(buffer.baseAddress, &parameters, &output, &size, &message, message.count)
            }
        }
        guard status == 0, let output else {
            throw DICOMCodecError.unsupportedImage(String(cString: message))
        }
        defer { copenjph_free(output) }
        var bytes = [UInt8](UnsafeBufferPointer(start: output, count: size))
        // Fragments have an even length (PS3.5 A.4).
        if bytes.count % 2 == 1 { bytes.append(0) }
        let photometric: DICOMPhotometricInterpretation = transform
            ? (reversible ? .ybrRCT : .ybrICT)
            : description.photometricInterpretation
        return (Data(bytes), photometric)
    }
}

/// Interleaves decoded components into frames of `samplesPerPixel`
/// consecutive components, as native little endian samples.
private struct FrameAssembler {
    let description: DICOMPixelDescription
    let cellBytes: Int
    let frameBytes: Int
    var storage: [UInt8]

    init(components: Int, description: DICOMPixelDescription) throws {
        let samples = description.samplesPerPixel
        guard components % samples == 0 else {
            throw DICOMCodecError.corruptedData(
                "JPEG 2000 image has \(components) components, frames have \(samples) samples")
        }
        cellBytes = description.bitsAllocated / 8
        guard cellBytes == 1 || cellBytes == 2 else {
            throw DICOMCodecError.unsupportedImage("JPEG 2000 in \(description.bitsAllocated) bits allocated")
        }
        self.description = description
        frameBytes = description.rows * description.columns * samples * cellBytes
        storage = [UInt8](repeating: 0, count: frameBytes * (components / samples))
    }

    /// Writes samples through `Writer`, which threads may share to write
    /// distinct samples.
    mutating func write(_ body: (Writer) throws -> Void) rethrows {
        let (samples, cellBytes, frameBytes) = (description.samplesPerPixel, cellBytes, frameBytes)
        try storage.withUnsafeMutableBufferPointer { buffer in
            try body(Writer(base: buffer.baseAddress!, samples: samples, cellBytes: cellBytes, frameBytes: frameBytes))
        }
    }

    struct Writer {
        let base: UnsafeMutablePointer<UInt8>
        let samples: Int
        let cellBytes: Int
        let frameBytes: Int

        func set(component: Int, pixel: Int, value: Int64) {
            let offset = component / samples * frameBytes + (pixel * samples + component % samples) * cellBytes
            base[offset] = UInt8(truncatingIfNeeded: value)
            if cellBytes == 2 { base[offset + 1] = UInt8(truncatingIfNeeded: value >> 8) }
        }
    }

    func frames(photometric: DICOMPhotometricInterpretation) -> [DICOMDecodedFrame] {
        let frameDescription = description.decodedFrame(photometricInterpretation: photometric, planarConfiguration: 0)
        return stride(from: 0, to: storage.count, by: frameBytes).map { start in
            DICOMDecodedFrame(description: frameDescription, data: Data(storage[start..<(start + frameBytes)]))
        }
    }
}

/// An image decoded by OpenJPEG, destroyed with the instance.
private final class OpenJPEGImage {
    let image: UnsafeMutablePointer<opj_image_t>

    init(_ image: UnsafeMutablePointer<opj_image_t>) {
        self.image = image
    }

    deinit {
        opj_image_destroy(image)
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
