import Foundation

/// Character repertoire selected by Specific Character Set (0008,0005).
///
/// Every Defined Term of PS3.3 2026d C.12.1.1.2 is supported: the single-byte
/// repertoires, ISO 2022 Code Extensions (Japanese, Korean, Chinese, and
/// single-byte sets), UTF-8, GB18030 (2022 edition), and GBK. Decoding uses
/// DcmSwift's own mapping tables, so results are identical on every
/// platform. Unknown or invalid declarations remain observable as
/// unsupported and are never decoded as UTF-8.
public struct DICOMCharacterSet: Equatable, Sendable {
    /// The declared Values, trimmed; empty for the Default Character
    /// Repertoire.
    public let identifiers: [String]
    private let codec: Codec?

    private enum Codec: Equatable, Sendable {
        case iso2022(DICOMISO2022Codec)
        case utf8
        case gb18030(DICOMGB18030Codec)
    }

    public static let defaultRepertoire = DICOMCharacterSet(specificCharacterSet: nil)
    public static let latin1 = DICOMCharacterSet(specificCharacterSet: "ISO_IR 100")
    public static let utf8 = DICOMCharacterSet(specificCharacterSet: "ISO_IR 192")

    public init(specificCharacterSet value: String?) {
        var identifiers = (value ?? "")
            .components(separatedBy: "\\")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if identifiers.count == 1 && Self.defaultTerms.contains(identifiers[0]) {
            identifiers = []
        }
        self.identifiers = identifiers
        self.codec = Self.makeCodec(for: identifiers)
    }

    public var isSupported: Bool { codec != nil }

    /// True when the declaration has several Values, so ISO 2022 escape
    /// sequences may switch character sets within a value.
    public var usesCodeExtensions: Bool {
        if case .iso2022(let codec)? = codec { return codec.allowsCodeExtensions }
        return false
    }

    /// Decodes a text Value Field. The VR decides whether a single-byte 05/12
    /// separates values (all VRs except ST, LT and UT) and, for PN, that "^"
    /// and "=" restore the Value 1 character sets. Returns nil for bytes that
    /// the declared repertoire cannot represent.
    public func decode(_ data: Data, vr: VR.VR? = nil) -> String? {
        let bytes = [UInt8](data)
        let decoded: String?
        switch codec {
        case .iso2022(let codec)?:
            decoded = codec.decode(bytes, context: DICOMTextContext(vr: vr))
        case .utf8?:
            decoded = String(data: data, encoding: .utf8)
        case .gb18030(let codec)?:
            decoded = codec.decode(bytes)
        case nil:
            decoded = nil
        }
        return decoded?.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }

    /// Encodes text, inserting the escape sequences required by PS3.5
    /// 6.1.2.5.3 when Code Extensions are declared. Returns nil when a
    /// character cannot be represented.
    public func encode(_ string: String, vr: VR.VR? = nil) -> Data? {
        switch codec {
        case .iso2022(let codec)?:
            return codec.encode(string, context: DICOMTextContext(vr: vr)).map { Data($0) }
        case .utf8?:
            return string.data(using: .utf8)
        case .gb18030(let codec)?:
            return codec.encode(string).map { Data($0) }
        case nil:
            return nil
        }
    }

    // MARK: Defined Terms

    /// Single Values meaning the Default Character Repertoire. "ISO_IR 6" is
    /// not a Defined Term but is accepted for compatibility.
    private static let defaultTerms: Set<String> = ["", "ISO_IR 6", "ISO 2022 IR 6"]

    /// Character sets that prohibit Code Extensions (PS3.3 Table C.12-5).
    private static let nonExtensibleTerms: Set<String> = ["ISO_IR 192", "GB18030", "GBK"]

    /// Multi-byte sets usable only through Code Extensions (Table C.12-4).
    private static let multiByteTerms: [Int: DICOMGraphicCharacterSet] = [
        87: .jisX0208, 159: .jisX0212, 149: .ksX1001, 58: .gb2312
    ]

    private enum Term {
        /// A single-byte repertoire: its G0 set and optional G1 set.
        case singleByte(g0: DICOMGraphicCharacterSet, g1: DICOMGraphicCharacterSet?)
        case multiByte(DICOMGraphicCharacterSet)
    }

    /// Parses "ISO_IR n" (no Code Extensions) or "ISO 2022 IR n".
    private static func term(_ identifier: String) -> (term: Term, isISO2022: Bool)? {
        let isISO2022: Bool
        let number: Substring
        if identifier.hasPrefix("ISO 2022 IR ") {
            isISO2022 = true
            number = identifier.dropFirst("ISO 2022 IR ".count)
        } else if identifier.hasPrefix("ISO_IR ") {
            isISO2022 = false
            number = identifier.dropFirst("ISO_IR ".count)
        } else {
            return nil
        }
        guard let registration = Int(number), String(registration) == number else { return nil }

        if registration == 6 {
            return (.singleByte(g0: .ascii, g1: nil), isISO2022)
        }
        if registration == 13 {
            return (.singleByte(g0: .jisRomaji, g1: .singleByte(registration: 13)), isISO2022)
        }
        if DICOMGraphicCharacterSet.singleByteSetExists(registration: registration) {
            return (.singleByte(g0: .ascii, g1: .singleByte(registration: registration)), isISO2022)
        }
        if isISO2022, let set = multiByteTerms[registration] {
            return (.multiByte(set), true)
        }
        return nil
    }

    private static func makeCodec(for identifiers: [String]) -> Codec? {
        if identifiers.isEmpty {
            return .iso2022(DICOMISO2022Codec(initialG0: .ascii, initialG1: nil, extensions: []))
        }
        if identifiers.count == 1 {
            switch identifiers[0] {
            case "ISO_IR 192": return .utf8
            case "GB18030": return .gb18030(DICOMGB18030Codec(allowsFourByteSequences: true))
            case "GBK": return .gb18030(DICOMGB18030Codec(allowsFourByteSequences: false))
            default: break
            }
            // A single Value designates G0 and G1 once; no Code Extensions.
            guard case (.singleByte(let g0, let g1), _)? = term(identifiers[0]) else { return nil }
            return .iso2022(DICOMISO2022Codec(initialG0: g0, initialG1: g1, extensions: []))
        }

        // Multi-valued: Code Extensions (PS3.5 6.1.2.5.1). An empty Value 1
        // means ISO 2022 IR 6. Value 1 must be a single-byte repertoire;
        // Values 2 to n use the "ISO 2022" Defined Terms.
        guard !identifiers.contains(where: nonExtensibleTerms.contains) else { return nil }
        let value1 = identifiers[0].isEmpty ? "ISO 2022 IR 6" : identifiers[0]
        guard case (.singleByte(let initialG0, let initialG1), _)? = term(value1) else { return nil }

        var extensions: [DICOMGraphicCharacterSet] = [initialG0] + (initialG1.map { [$0] } ?? [])
        for identifier in identifiers.dropFirst() {
            guard let (term, isISO2022) = term(identifier), isISO2022 else { return nil }
            switch term {
            case .singleByte(let g0, let g1):
                extensions.append(g0)
                if let g1 { extensions.append(g1) }
            case .multiByte(let set):
                extensions.append(set)
            }
        }
        var seen: Set<DICOMGraphicCharacterSet> = []
        extensions = extensions.filter { seen.insert($0).inserted }
        return .iso2022(DICOMISO2022Codec(initialG0: initialG0, initialG1: initialG1, extensions: extensions))
    }
}
