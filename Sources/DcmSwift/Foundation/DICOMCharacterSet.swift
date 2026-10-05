import Foundation

/// Character repertoire selected by Specific Character Set (0008,0005).
///
/// DICOM code extensions and multi-valued ISO 2022 declarations require a
/// stateful decoder. They remain explicitly unsupported until that decoder is
/// available, rather than being interpreted as UTF-8.
public enum DICOMCharacterSet: Equatable {
    case defaultRepertoire
    case latin1
    case utf8
    case unsupported([String])

    public init(specificCharacterSet value: String?) {
        let identifiers = (value ?? "")
            .components(separatedBy: "\\")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard identifiers.count == 1 else {
            self = .unsupported(identifiers)
            return
        }

        switch identifiers[0] {
        case "", "ISO_IR 6", "ISO 2022 IR 6":
            self = .defaultRepertoire
        case "ISO_IR 100":
            self = .latin1
        case "ISO_IR 192":
            self = .utf8
        default:
            self = .unsupported(identifiers)
        }
    }

    public var identifiers: [String] {
        switch self {
        case .defaultRepertoire: return []
        case .latin1: return ["ISO_IR 100"]
        case .utf8: return ["ISO_IR 192"]
        case .unsupported(let identifiers): return identifiers
        }
    }

    public var isSupported: Bool {
        if case .unsupported = self { return false }
        return true
    }

    public func decode(_ data: Data) -> String? {
        let encoding: String.Encoding
        switch self {
        case .defaultRepertoire: encoding = .ascii
        case .latin1: encoding = .isoLatin1
        case .utf8: encoding = .utf8
        case .unsupported: return nil
        }
        return String(data: data, encoding: encoding)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }

    public func encode(_ string: String) -> Data? {
        switch self {
        case .defaultRepertoire: return string.data(using: .ascii)
        case .latin1: return string.data(using: .isoLatin1)
        case .utf8: return string.data(using: .utf8)
        case .unsupported: return nil
        }
    }
}
