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
    public let canNegotiateForDIMSE: Bool

    public var isImplemented: Bool { canReadDataset || canWriteDataset }
}

public enum DICOMCapabilities {
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
        DICOMRLECodec.transferSyntaxUID, DICOMDeflatedFrameCodec.transferSyntaxUID
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
                canNegotiateForDIMSE: false
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
                canEncodePixelData: encodableUIDs.contains(uid),
                canNegotiateForDIMSE: false
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
