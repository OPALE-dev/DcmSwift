import Foundation
import CJPEGXL

extension DICOMJPEGXLCodec {
    /// The JPEG XL Transfer Syntax and rate control to encode for (PS3.5
    /// 8.2.15).
    public enum Mode: Sendable, Equatable {
        /// Mathematically lossless: 1.2.840.10008.1.2.4.110.
        case lossless
        /// Lossy at a Butteraugli distance from 0.01 to 25, where 1 is
        /// visually lossless: 1.2.840.10008.1.2.4.112.
        case distance(Float)

        public var transferSyntaxUID: String {
            self == .lossless ? DICOMJPEGXLCodec.lossless : DICOMJPEGXLCodec.general
        }
    }

    /// Encodes one native little endian frame (as described) to a JPEG XL
    /// codestream with libjxl. Frames are unsigned MONOCHROME1, MONOCHROME2
    /// (1 to 16 bits), or RGB (8 to 16 bits) in 8 or 16-bit cells, as PS3.5
    /// Table 8.2.15-1 allows; `effort` trades speed for size (1 to 10). The
    /// photometric interpretation is unchanged.
    public func encode(
        _ frame: Data, description: DICOMPixelDescription, mode: Mode = .lossless, effort: Int = 7
    ) throws -> (data: Data, photometric: DICOMPhotometricInterpretation) {
        let samples = description.samplesPerPixel
        let bits = description.bitsStored
        let monochrome = samples == 1 && description.photometricInterpretation.isMonochrome
        let color = samples == 3 && description.photometricInterpretation == .rgb
        guard description.sampleFormat == .integer, !description.isSigned,
              description.bitsAllocated == 8 || description.bitsAllocated == 16, bits <= description.bitsAllocated,
              (monochrome && bits >= 1) || (color && bits >= 8) else {
            throw DICOMCodecError.unsupportedImage(
                "JPEG XL encoding needs unsigned MONOCHROME1/2 (1 to 16 bits) or RGB (8 to 16 bits) frames")
        }
        guard (1...10).contains(effort) else { throw DICOMCodecError.unsupportedImage("JPEG XL effort \(effort)") }
        if case .distance(let distance) = mode, !(0.01...25).contains(distance) {
            throw DICOMCodecError.unsupportedImage("JPEG XL distance \(distance)")
        }

        // Interleaved samples, masked to Bits Stored.
        let stored = try DICOMNativePixelData(description: description.decodedFrame(), decodedFrames: frame)
            .storedValues(frame: 0)
        let wide = description.bitsAllocated == 16
        let mask = (Int64(1) << bits) - 1
        var pixels = [UInt8](repeating: 0, count: stored.count * (wide ? 2 : 1))
        for (index, value) in stored.enumerated() {
            let sample = value & mask
            if wide {
                pixels[2 * index] = UInt8(truncatingIfNeeded: sample)
                pixels[2 * index + 1] = UInt8(truncatingIfNeeded: sample >> 8)
            } else {
                pixels[index] = UInt8(truncatingIfNeeded: sample)
            }
        }

        let data = try Self.withEncoder { encoder in
            var info = JxlBasicInfo()
            JxlEncoderInitBasicInfo(&info)
            info.xsize = UInt32(description.columns)
            info.ysize = UInt32(description.rows)
            info.bits_per_sample = UInt32(bits)
            info.exponent_bits_per_sample = 0
            info.num_color_channels = UInt32(samples)
            info.uses_original_profile = mode == .lossless ? JXL_TRUE : JXL_FALSE
            try Self.check(JxlEncoderSetBasicInfo(encoder, &info), encoder, "set the basic information")
            var colorEncoding = JxlColorEncoding()
            JxlColorEncodingSetToSRGB(&colorEncoding, monochrome ? JXL_TRUE : JXL_FALSE)
            try Self.check(JxlEncoderSetColorEncoding(encoder, &colorEncoding), encoder, "set the color encoding")

            let settings = try Self.frameSettings(encoder, effort: effort)
            switch mode {
            case .lossless:
                try Self.check(JxlEncoderSetFrameLossless(settings, JXL_TRUE), encoder, "select lossless coding")
            case .distance(let distance):
                try Self.check(JxlEncoderSetFrameDistance(settings, distance), encoder, "set the distance")
            }
            // Samples hold Bits Stored bits, not the full cell range.
            var depth = JxlBitDepth(type: JXL_BIT_DEPTH_FROM_CODESTREAM, bits_per_sample: 0, exponent_bits_per_sample: 0)
            try Self.check(JxlEncoderSetFrameBitDepth(settings, &depth), encoder, "set the sample bit depth")
            var format = JxlPixelFormat(
                num_channels: UInt32(samples), data_type: wide ? JXL_TYPE_UINT16 : JXL_TYPE_UINT8,
                endianness: JXL_LITTLE_ENDIAN, align: 0)
            try pixels.withUnsafeBytes { buffer in
                try Self.check(
                    JxlEncoderAddImageFrame(settings, &format, buffer.baseAddress, buffer.count), encoder, "add the frame")
            }
        }
        return (data, description.photometricInterpretation)
    }

    /// Losslessly recompresses a JPEG bitstream (an 8-bit JPEG Baseline or
    /// Extended frame) for 1.2.840.10008.1.2.4.111, keeping the JPEG
    /// reconstruction data so that the original bitstream can be recovered
    /// (PS3.5 10.19). The image keeps its photometric interpretation.
    public func recompressJPEG(_ jpeg: Data, effort: Int = 7) throws -> Data {
        guard jpeg.count > 4, jpeg.starts(with: [0xFF, 0xD8]) else {
            throw DICOMCodecError.corruptedData("JPEG data does not start with SOI")
        }
        guard (1...10).contains(effort) else { throw DICOMCodecError.unsupportedImage("JPEG XL effort \(effort)") }
        // DICOM may pad the frame to an even length after EOI.
        var bytes = [UInt8](jpeg)
        if bytes.count >= 3, bytes[bytes.count - 1] == 0, bytes[bytes.count - 3] == 0xFF,
           bytes[bytes.count - 2] == 0xD9 {
            bytes.removeLast()
        }
        return try Self.withEncoder { encoder in
            try Self.check(JxlEncoderStoreJPEGMetadata(encoder, JXL_TRUE), encoder, "keep the JPEG metadata")
            let settings = try Self.frameSettings(encoder, effort: effort)
            let status = bytes.withUnsafeBufferPointer { buffer in
                JxlEncoderAddJPEGFrame(settings, buffer.baseAddress, buffer.count)
            }
            guard status == JXL_ENC_SUCCESS else {
                throw DICOMCodecError.unsupportedImage(
                    "libjxl cannot recompress this JPEG bitstream: JPEG XL keeps 8-bit Huffman-coded JPEG "
                        + "with 4:4:4, 4:2:2, 4:2:0, or 4:4:0 chroma")
            }
        }
    }

    /// Runs `configure` on a new encoder, then collects its output.
    private static func withEncoder(_ configure: (OpaquePointer) throws -> Void) throws -> Data {
        guard let encoder = JxlEncoderCreate(nil) else {
            throw DICOMCodecError.unsupportedImage("libjxl cannot allocate an encoder")
        }
        defer { JxlEncoderDestroy(encoder) }
        let workers = min(JxlThreadParallelRunnerDefaultNumWorkerThreads(), 16)
        guard let runner = JxlThreadParallelRunnerCreate(nil, workers) else {
            throw DICOMCodecError.unsupportedImage("libjxl cannot allocate its threads")
        }
        defer { JxlThreadParallelRunnerDestroy(runner) }
        try check(JxlEncoderSetParallelRunner(encoder, JxlThreadParallelRunner, runner), encoder, "set the threads")

        try configure(encoder)
        JxlEncoderCloseInput(encoder)

        var output = [UInt8](repeating: 0, count: 1 << 16)
        var written = 0
        while true {
            var next: UnsafeMutablePointer<UInt8>?
            var available = 0
            let status = output.withUnsafeMutableBufferPointer { buffer -> JxlEncoderStatus in
                next = buffer.baseAddress! + written
                available = buffer.count - written
                return JxlEncoderProcessOutput(encoder, &next, &available)
            }
            written = output.count - available
            switch status {
            case JXL_ENC_SUCCESS:
                var result = Array(output[0..<written])
                // Fragments have an even length (PS3.5 A.4).
                if result.count % 2 == 1 { result.append(0) }
                return Data(result)
            case JXL_ENC_NEED_MORE_OUTPUT:
                output.append(contentsOf: [UInt8](repeating: 0, count: output.count))
            default:
                throw error(encoder, "encode")
            }
        }
    }

    private static func frameSettings(_ encoder: OpaquePointer, effort: Int) throws -> OpaquePointer {
        guard let settings = JxlEncoderFrameSettingsCreate(encoder, nil) else {
            throw error(encoder, "create the frame settings")
        }
        try check(JxlEncoderFrameSettingsSetOption(settings, JXL_ENC_FRAME_SETTING_EFFORT, Int64(effort)),
                  encoder, "set the effort")
        return settings
    }

    private static func check(_ status: JxlEncoderStatus, _ encoder: OpaquePointer, _ step: String) throws {
        guard status == JXL_ENC_SUCCESS else { throw error(encoder, step) }
    }

    private static func error(_ encoder: OpaquePointer, _ step: String) -> DICOMCodecError {
        let code = JxlEncoderGetError(encoder)
        let reason: String
        switch code {
        case JXL_ENC_ERR_BAD_INPUT: reason = "invalid input"
        case JXL_ENC_ERR_JBRD: reason = "the JPEG reconstruction data cannot be represented"
        case JXL_ENC_ERR_NOT_SUPPORTED: reason = "not supported"
        case JXL_ENC_ERR_OOM: reason = "out of memory"
        default: reason = "error \(code.rawValue)"
        }
        return code == JXL_ENC_ERR_BAD_INPUT || code == JXL_ENC_ERR_JBRD
            ? .corruptedData("libjxl cannot \(step): \(reason)")
            : .unsupportedImage("libjxl cannot \(step): \(reason)")
    }
}
