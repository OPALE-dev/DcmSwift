import Foundation

/// Declares what DcmSwift actually does with a Transfer Syntax.
/// Being present in the PS3.6 UID registry is deliberately not considered support.
public struct TransferSyntaxCapability: Equatable {
    public let uid: String
    public let canReadDataset: Bool
    public let canWriteDataset: Bool
    public let canPreservePixelData: Bool
    public let canDecodePixelData: Bool
    public let canEncodePixelData: Bool
    /// Can be negotiated on DIMSE associations: data sets are sent and
    /// received as encoded, and converted only between uncompressed syntaxes.
    public let canNegotiateForDIMSE: Bool

    public var isImplemented: Bool { canReadDataset || canWriteDataset }
}

public enum DICOMCapabilities {
    /// The High-Throughput JPEG 2000 Transfer Syntaxes (PS3.5 A.4.4, A.12):
    /// HTJ2K Image Compression (.201, .202, .203) and JPIP HTJ2K Referenced
    /// (.204, .205).
    public static let htj2kTransferSyntaxUIDs: Set<String> = [
        DICOMJPEG2000Codec.htj2kLossless, DICOMJPEG2000Codec.htj2kLosslessRPCL, DICOMJPEG2000Codec.htj2k,
        TransferSyntax.jpipHTJ2KReferenced, TransferSyntax.jpipHTJ2KReferencedDeflate,
    ]

    /// The initial value of ``isHTJ2KEnabled``: `false`, so that the HTJ2K
    /// codec runs only for applications that enable it. This is the only
    /// place that sets the default.
    public static let isHTJ2KEnabledByDefault = false

    private static let htj2kLock = NSLock()
    private static var htj2kEnabled = isHTJ2KEnabledByDefault

    /// Whether the built-in High-Throughput JPEG 2000 codec may run; it
    /// starts as ``isHTJ2KEnabledByDefault``.
    ///
    /// The HTJ2K codec relies on two vendored C libraries:
    /// - encoding uses OpenJPH 0.32.0, through its encoder only; DcmSwift
    ///   never calls the OpenJPH decoder;
    /// - decoding uses the HT block decoder of OpenJPEG 2.5.4, as for any
    ///   JPEG 2000 codestream.
    ///
    /// OpenJPH has a publicly reported heap out-of-bounds write in its HTJ2K
    /// decoder, without a corrected release. That decoder is not reachable
    /// from DcmSwift; the switch keeps the HTJ2K code of both libraries out of
    /// reach of the application's data until it opts in, typically once at
    /// startup.
    ///
    /// While `false`, for the syntaxes of ``htj2kTransferSyntaxUIDs``:
    /// - ``transferSyntax(_:)`` reports neither decoding nor encoding;
    /// - ``DICOMCodecRegistry`` returns no built-in decoder, so decoding,
    ///   rendering (``DICOMImageRenderer``), DICOMweb transcoding to Explicit
    ///   VR Little Endian, and JPIP HTJ2K resolution fail with
    ///   ``DICOMPixelDataError/encapsulatedPixelData(transferSyntax:)`` or
    ///   ``DICOMCodecError/unsupportedTransferSyntax(_:)``;
    /// - ``DICOMJPEG2000Codec`` refuses, before calling OpenJPEG or OpenJPH,
    ///   to encode HTJ2K and to decode any codestream that uses HT
    ///   code-blocks, whatever the Transfer Syntax it was labelled with, with
    ///   ``DICOMCodecError/unsupportedTransferSyntax(_:)``.
    ///
    /// Data sets in these syntaxes are still read, written, stored, and sent
    /// with their Pixel Data preserved as encoded, over DIMSE and as stored
    /// compressed frames (`image/jphc`) over DICOMweb. Decoders that the
    /// application registers itself are not affected. Reading and writing
    /// the property is thread-safe.
    public static var isHTJ2KEnabled: Bool {
        get {
            htj2kLock.lock()
            defer { htj2kLock.unlock() }
            return htj2kEnabled
        }
        set {
            htj2kLock.lock()
            defer { htj2kLock.unlock() }
            htj2kEnabled = newValue
        }
    }

    /// Whether `uid` is an HTJ2K Transfer Syntax while HTJ2K is disabled.
    static func isDisabledHTJ2K(_ uid: String) -> Bool {
        htj2kTransferSyntaxUIDs.contains(uid) && !isHTJ2KEnabled
    }

    private static let nativeUIDs: Set<String> = [
        TransferSyntax.implicitVRLittleEndian,
        TransferSyntax.explicitVRLittleEndian,
        TransferSyntax.explicitVRBigEndian
    ]

    /// Encapsulated syntaxes whose Data Set and fragment structure can be preserved.
    /// This does not imply that the compressed frames can be decoded or encoded.
    private static func isEncapsulatedPixelSyntax(_ uid: String) -> Bool {
        uid.hasPrefix("1.2.840.10008.1.2.4.") || uid == DICOMRLECodec.transferSyntaxUID
            || uid == DICOMDeflatedFrameCodec.transferSyntaxUID
    }

    /// Syntaxes with a built-in frame encoder.
    private static let encodableUIDs: Set<String> = [
        DICOMRLECodec.transferSyntaxUID, DICOMDeflatedFrameCodec.transferSyntaxUID,
        DICOMJPEGLosslessCodec.processFourteen, DICOMJPEGLosslessCodec.firstOrderPrediction,
        DICOMJPEGBaselineCodec.baseline, DICOMJPEGBaselineCodec.extended,
        DICOMJPEGLSCodec.lossless, DICOMJPEGLSCodec.nearLossless,
        DICOMJPEG2000Codec.lossless, DICOMJPEG2000Codec.lossy,
        DICOMJPEG2000Codec.partTwoLossless, DICOMJPEG2000Codec.partTwo,
        DICOMJPEGXLCodec.lossless, DICOMJPEGXLCodec.jpegRecompression, DICOMJPEGXLCodec.general,
        DICOMJPEG2000Codec.htj2kLossless, DICOMJPEG2000Codec.htj2kLosslessRPCL, DICOMJPEG2000Codec.htj2k
    ]

    public static func transferSyntax(_ uid: String) -> TransferSyntaxCapability {
        if uid == TransferSyntax.deflatedExplicitVRLittleEndian {
            return TransferSyntaxCapability(
                uid: uid,
                canReadDataset: true,
                canWriteDataset: true,
                canPreservePixelData: true,
                canDecodePixelData: false,
                canEncodePixelData: false,
                canNegotiateForDIMSE: true
            )
        }

        if nativeUIDs.contains(uid) {
            return TransferSyntaxCapability(
                uid: uid,
                canReadDataset: true,
                canWriteDataset: true,
                canPreservePixelData: true,
                canDecodePixelData: false,
                canEncodePixelData: false,
                canNegotiateForDIMSE: true
            )
        }

        if isEncapsulatedPixelSyntax(uid) {
            return TransferSyntaxCapability(
                uid: uid,
                canReadDataset: true,
                canWriteDataset: true,
                canPreservePixelData: true,
                // Includes decoders registered by the application.
                canDecodePixelData: DICOMCodecRegistry.decoder(for: uid) != nil,
                canEncodePixelData: encodableUIDs.contains(uid) && !isDisabledHTJ2K(uid),
                canNegotiateForDIMSE: DICOMTransferSyntaxes.storage.contains(uid)
            )
        }

        return TransferSyntaxCapability(
            uid: uid,
            canReadDataset: false,
            canWriteDataset: false,
            canPreservePixelData: false,
            canDecodePixelData: false,
            canEncodePixelData: false,
            canNegotiateForDIMSE: false
        )
    }
}
