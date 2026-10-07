import Foundation

/// A frame decoded from encapsulated Pixel Data: native little endian
/// samples and the description that applies to them, which may differ from
/// the encoded image (for example YBR_FULL_422 decoded to RGB).
public struct DICOMDecodedFrame {
    public let description: DICOMPixelDescription
    public let data: Data

    public init(description: DICOMPixelDescription, data: Data) {
        self.description = description
        self.data = data
    }
}

/// Decodes the frames of one or more encapsulated Transfer Syntaxes.
public protocol DICOMPixelDataDecoder: Sendable {
    var transferSyntaxUIDs: Set<String> { get }

    /// Decodes one frame: the bytes of all its Fragments, concatenated.
    /// `description` is the encoded image's description with one frame.
    func decode(_ encodedFrame: Data, description: DICOMPixelDescription) throws -> DICOMDecodedFrame
}

/// Errors raised by codecs while decoding a frame.
public enum DICOMCodecError: Error, Equatable, CustomStringConvertible {
    case unsupportedTransferSyntax(String)
    case unsupportedImage(String)
    case corruptedData(String)

    public var description: String {
        switch self {
        case .unsupportedTransferSyntax(let uid): return "No decoder for Transfer Syntax \(uid)"
        case .unsupportedImage(let reason): return "Unsupported encoded image: \(reason)"
        case .corruptedData(let reason): return "Corrupted encoded data: \(reason)"
        }
    }
}

/// The decoders available to `DICOMEncapsulatedPixelData`. Applications may
/// register additional decoders, which take precedence over the built-in
/// ones for the Transfer Syntaxes they declare.
public enum DICOMCodecRegistry {
    private static let lock = NSLock()
    private static var registered: [any DICOMPixelDataDecoder] = []
    private static let builtIn: [any DICOMPixelDataDecoder] = [DICOMRLECodec(), DICOMDeflatedFrameCodec()]

    public static func register(_ decoder: any DICOMPixelDataDecoder) {
        lock.lock()
        defer { lock.unlock() }
        registered.insert(decoder, at: 0)
    }

    public static func decoder(for transferSyntaxUID: String) -> (any DICOMPixelDataDecoder)? {
        lock.lock()
        defer { lock.unlock() }
        return (registered + builtIn).first { $0.transferSyntaxUIDs.contains(transferSyntaxUID) }
    }
}
