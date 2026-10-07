import Foundation
import CJPEGXL

/// JPEG XL (ISO/IEC 18181-1) decoding through the vendored libjxl 0.12.0.
///
/// DICOM defines lossless, reversible JPEG recompression, and general JPEG XL
/// Transfer Syntaxes. All three yield native interleaved pixels here; JPEG
/// reconstruction metadata is deliberately not exposed by this pixel codec.
public struct DICOMJPEGXLCodec: DICOMPixelDataDecoder {
    public static let lossless = "1.2.840.10008.1.2.4.110"
    public static let jpegRecompression = "1.2.840.10008.1.2.4.111"
    public static let general = "1.2.840.10008.1.2.4.112"

    public var transferSyntaxUIDs: Set<String> {
        [Self.lossless, Self.jpegRecompression, Self.general]
    }

    public init() {}

    public func decode(_ encodedFrame: Data, description: DICOMPixelDescription) throws -> DICOMDecodedFrame {
        guard encodedFrame.count >= 2 else {
            throw DICOMCodecError.corruptedData("truncated JPEG XL frame")
        }
        let signature = encodedFrame.withUnsafeBytes {
            JxlSignatureCheck($0.bindMemory(to: UInt8.self).baseAddress, encodedFrame.count)
        }
        guard signature == JXL_SIG_CODESTREAM || signature == JXL_SIG_CONTAINER else {
            throw DICOMCodecError.corruptedData("invalid JPEG XL signature")
        }
        guard let decoder = JxlDecoderCreate(nil) else {
            throw DICOMCodecError.unsupportedImage("libjxl cannot allocate a decoder")
        }
        defer { JxlDecoderDestroy(decoder) }
        guard JxlDecoderSubscribeEvents(decoder, Int32(JXL_DEC_BASIC_INFO.rawValue | JXL_DEC_FULL_IMAGE.rawValue))
                == JXL_DEC_SUCCESS else {
            throw DICOMCodecError.unsupportedImage("libjxl cannot configure the decoder")
        }
        guard JxlDecoderSetKeepOrientation(decoder, JXL_TRUE) == JXL_DEC_SUCCESS else {
            throw DICOMCodecError.unsupportedImage("libjxl cannot preserve the encoded orientation")
        }

        var allocation: UnsafeMutableRawPointer?
        var allocationSize = 0
        var transferredAllocation = false
        defer {
            if !transferredAllocation { allocation?.deallocate() }
        }
        var basicInfo: JxlBasicInfo?
        var pixelFormat: JxlPixelFormat?
        var sawFullImage = false

        return try encodedFrame.withUnsafeBytes { input in
            guard let inputAddress = input.bindMemory(to: UInt8.self).baseAddress else {
                throw DICOMCodecError.corruptedData("empty JPEG XL frame")
            }
            guard JxlDecoderSetInput(decoder, inputAddress, input.count) == JXL_DEC_SUCCESS else {
                throw DICOMCodecError.corruptedData("libjxl rejected the input buffer")
            }
            JxlDecoderCloseInput(decoder)

            while true {
                let status = JxlDecoderProcessInput(decoder)
                switch status {
                case JXL_DEC_BASIC_INFO:
                    var info = JxlBasicInfo()
                    guard JxlDecoderGetBasicInfo(decoder, &info) == JXL_DEC_SUCCESS else {
                        throw DICOMCodecError.corruptedData("libjxl did not provide basic image information")
                    }
                    try Self.validate(info, description: description)
                    basicInfo = info
                    pixelFormat = JxlPixelFormat(
                        num_channels: info.num_color_channels,
                        data_type: description.bitsAllocated == 8 ? JXL_TYPE_UINT8 : JXL_TYPE_UINT16,
                        endianness: JXL_LITTLE_ENDIAN,
                        align: 0)

                case JXL_DEC_NEED_IMAGE_OUT_BUFFER:
                    guard var format = pixelFormat, let info = basicInfo else {
                        throw DICOMCodecError.corruptedData("JPEG XL requested pixels before its header")
                    }
                    var size = 0
                    guard JxlDecoderImageOutBufferSize(decoder, &format, &size) == JXL_DEC_SUCCESS,
                          size > 0 else {
                        throw DICOMCodecError.corruptedData("invalid JPEG XL output size")
                    }
                    let expected = description.rows * description.columns
                        * Int(info.num_color_channels) * (description.bitsAllocated / 8)
                    guard size == expected else {
                        throw DICOMCodecError.corruptedData(
                            "JPEG XL output needs \(size) bytes, DICOM attributes describe \(expected)")
                    }
                    allocation = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
                    allocationSize = size
                    guard JxlDecoderSetImageOutBuffer(decoder, &format, allocation, size) == JXL_DEC_SUCCESS else {
                        throw DICOMCodecError.corruptedData("libjxl rejected the pixel buffer")
                    }
                    var bitDepth = JxlBitDepth(
                        type: JXL_BIT_DEPTH_FROM_CODESTREAM,
                        bits_per_sample: 0,
                        exponent_bits_per_sample: 0)
                    guard JxlDecoderSetImageOutBitDepth(decoder, &bitDepth) == JXL_DEC_SUCCESS else {
                        throw DICOMCodecError.unsupportedImage("libjxl cannot preserve the codestream bit depth")
                    }

                case JXL_DEC_FULL_IMAGE:
                    sawFullImage = true

                case JXL_DEC_SUCCESS:
                    guard sawFullImage, let pointer = allocation, let info = basicInfo else {
                        throw DICOMCodecError.corruptedData("JPEG XL ended before producing a complete image")
                    }
                    transferredAllocation = true
                    let data = Data(bytesNoCopy: pointer, count: allocationSize, deallocator: .custom { pointer, _ in
                        pointer.deallocate()
                    })
                    let photometric: DICOMPhotometricInterpretation = info.num_color_channels == 3
                        ? .rgb : description.photometricInterpretation
                    return DICOMDecodedFrame(
                        description: description.decodedFrame(
                            photometricInterpretation: photometric, planarConfiguration: 0),
                        data: data)

                case JXL_DEC_NEED_MORE_INPUT:
                    throw DICOMCodecError.corruptedData("truncated JPEG XL frame")

                case JXL_DEC_ERROR:
                    throw DICOMCodecError.corruptedData("libjxl failed to decode the frame")

                default:
                    continue
                }
            }
        }
    }

    private static func validate(_ info: JxlBasicInfo, description: DICOMPixelDescription) throws {
        // libjxl's public pixel-buffer API exposes unsigned integer and float
        // output types, but not the codestream's signed integer representation.
        // Do not silently reinterpret those samples as two's-complement DICOM.
        guard !description.isSigned else {
            throw DICOMCodecError.unsupportedImage("signed JPEG XL Pixel Data")
        }
        guard info.have_animation == JXL_FALSE else {
            throw DICOMCodecError.unsupportedImage("animated JPEG XL inside one DICOM frame")
        }
        guard info.orientation == JXL_ORIENT_IDENTITY else {
            throw DICOMCodecError.unsupportedImage("JPEG XL orientation \(info.orientation.rawValue)")
        }
        guard info.exponent_bits_per_sample == 0 else {
            throw DICOMCodecError.unsupportedImage("floating-point JPEG XL Pixel Data")
        }
        guard info.num_extra_channels == 0 else {
            throw DICOMCodecError.unsupportedImage("JPEG XL extra channels")
        }
        guard info.xsize == description.columns, info.ysize == description.rows else {
            throw DICOMCodecError.corruptedData(
                "JPEG XL is \(info.xsize)x\(info.ysize), DICOM attributes are \(description.columns)x\(description.rows)")
        }
        guard info.num_color_channels == description.samplesPerPixel,
              info.num_color_channels == 1 || info.num_color_channels == 3 else {
            throw DICOMCodecError.corruptedData(
                "JPEG XL has \(info.num_color_channels) color channels, DICOM attributes have \(description.samplesPerPixel)")
        }
        guard info.bits_per_sample == description.bitsStored,
              info.bits_per_sample > 0,
              info.bits_per_sample <= description.bitsAllocated,
              description.bitsAllocated == 8 || description.bitsAllocated == 16 else {
            throw DICOMCodecError.unsupportedImage(
                "\(info.bits_per_sample)-bit JPEG XL in \(description.bitsAllocated)-bit DICOM cells")
        }
    }
}
