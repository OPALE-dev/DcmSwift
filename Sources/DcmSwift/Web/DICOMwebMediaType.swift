import Foundation

/// A media type with its parameters (PS3.18 8.7, RFC 9110 8.3.1), such as
/// `multipart/related; type="application/dicom"; transfer-syntax=*`.
///
/// Type, subtype, and parameter names compare without regard to case.
/// Parameter values keep their case; the values of `type` compare without
/// regard to case, since they are media types themselves.
public struct DICOMwebMediaType: Hashable, Sendable, CustomStringConvertible {
    /// The type, lowercased (`application`, `image`, `multipart`, or `*`).
    public var type: String
    /// The subtype, lowercased.
    public var subtype: String
    /// Parameters in their order of appearance, names lowercased.
    public var parameters: [Parameter]

    public struct Parameter: Hashable, Sendable {
        public var name: String
        public var value: String

        public init(_ name: String, _ value: String) {
            self.name = name.lowercased()
            self.value = value
        }
    }

    public init(type: String, subtype: String, parameters: [Parameter] = []) {
        self.type = type.lowercased()
        self.subtype = subtype.lowercased()
        self.parameters = parameters
    }

    /// Parses a media type or media range; returns nil when malformed.
    public init?(_ string: String) {
        let fields = Self.split(string, on: ";")
        guard let essence = fields.first?.trimmingCharacters(in: .whitespaces),
              let slash = essence.firstIndex(of: "/") else { return nil }
        let type = String(essence[..<slash]), subtype = String(essence[essence.index(after: slash)...])
        guard Self.isToken(type), Self.isToken(subtype) else { return nil }
        var parameters: [Parameter] = []
        for field in fields.dropFirst() {
            let field = field.trimmingCharacters(in: .whitespaces)
            if field.isEmpty { continue }
            guard let equal = field.firstIndex(of: "=") else { return nil }
            let name = field[..<equal].trimmingCharacters(in: .whitespaces)
            var value = field[field.index(after: equal)...].trimmingCharacters(in: .whitespaces)
            guard Self.isToken(name) else { return nil }
            if value.hasPrefix("\"") {
                guard value.count >= 2, value.hasSuffix("\"") else { return nil }
                value = Self.unquote(String(value.dropFirst().dropLast()))
            } else if value.isEmpty {
                return nil
            }
            parameters.append(Parameter(name, value))
        }
        self.init(type: type, subtype: subtype, parameters: parameters)
    }

    /// `type/subtype`.
    public var essence: String { "\(type)/\(subtype)" }

    /// The value of a parameter, by case-insensitive name.
    public subscript(parameter name: String) -> String? {
        get { parameters.first { $0.name == name.lowercased() }?.value }
        set {
            let name = name.lowercased()
            if let value = newValue {
                if let index = parameters.firstIndex(where: { $0.name == name }) {
                    parameters[index].value = value
                } else {
                    parameters.append(Parameter(name, value))
                }
            } else {
                parameters.removeAll { $0.name == name }
            }
        }
    }

    /// A copy with a parameter set, replaced, or removed.
    public func with(_ name: String, _ value: String?) -> DICOMwebMediaType {
        var copy = self
        copy[parameter: name] = value
        return copy
    }

    /// Whether this is `multipart/related`.
    public var isMultipartRelated: Bool { type == "multipart" && subtype == "related" }

    /// The media type of the parts of a `multipart/related` payload (its
    /// `type` parameter), or nil.
    public var relatedType: DICOMwebMediaType? {
        guard isMultipartRelated, let value = self[parameter: "type"] else { return nil }
        return DICOMwebMediaType(value)
    }

    /// The `transfer-syntax` parameter (PS3.18 8.7.3.5.2).
    public var transferSyntax: String? { self[parameter: "transfer-syntax"] }

    /// The `boundary` parameter of a multipart media type.
    public var boundary: String? { self[parameter: "boundary"] }

    /// Whether a wildcard is used in the type or subtype.
    public var isRange: Bool { type == "*" || subtype == "*" }

    public var description: String {
        var string = essence
        for parameter in parameters {
            string += "; \(parameter.name)=\(Self.quoteIfNeeded(parameter.value, always: parameter.name == "type"))"
        }
        return string
    }

    public static func == (lhs: DICOMwebMediaType, rhs: DICOMwebMediaType) -> Bool {
        lhs.type == rhs.type && lhs.subtype == rhs.subtype
            && Set(lhs.parameters.map(\.comparable)) == Set(rhs.parameters.map(\.comparable))
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(subtype)
        hasher.combine(Set(parameters.map(\.comparable)))
    }

    // MARK: Well-known media types (PS3.18 8.7.3.5)

    public static let dicom = DICOMwebMediaType(type: "application", subtype: "dicom")
    public static let dicomJSON = DICOMwebMediaType(type: "application", subtype: "dicom+json")
    public static let dicomXML = DICOMwebMediaType(type: "application", subtype: "dicom+xml")
    public static let octetStream = DICOMwebMediaType(type: "application", subtype: "octet-stream")
    public static let json = DICOMwebMediaType(type: "application", subtype: "json")
    public static let jpeg = DICOMwebMediaType(type: "image", subtype: "jpeg")
    public static let png = DICOMwebMediaType(type: "image", subtype: "png")
    public static let gif = DICOMwebMediaType(type: "image", subtype: "gif")
    public static let html = DICOMwebMediaType(type: "text", subtype: "html")
    public static let plainText = DICOMwebMediaType(type: "text", subtype: "plain")

    /// `multipart/related` whose parts have the media type `part`, with a
    /// boundary when given.
    public static func multipartRelated(_ part: DICOMwebMediaType, boundary: String? = nil) -> DICOMwebMediaType {
        var parameters = [Parameter("type", part.essence)]
        // Part parameters such as transfer-syntax apply to the multipart
        // media type (PS3.18 8.7.3.5.1).
        parameters += part.parameters
        if let boundary { parameters.append(Parameter("boundary", boundary)) }
        return DICOMwebMediaType(type: "multipart", subtype: "related", parameters: parameters)
    }

    /// The media type of compressed Bulk Data in `transferSyntaxUID`
    /// (PS3.18 Table 8.7.3-5), or nil for uncompressed or unknown syntaxes.
    public static func compressedBulkData(for transferSyntaxUID: String) -> DICOMwebMediaType? {
        let subtype: (String, String)?
        switch transferSyntaxUID {
        case "1.2.840.10008.1.2.4.50", "1.2.840.10008.1.2.4.51", "1.2.840.10008.1.2.4.57",
             "1.2.840.10008.1.2.4.70":
            subtype = ("image", "jpeg")
        case "1.2.840.10008.1.2.8.1": subtype = ("application", "x-deflate")
        case "1.2.840.10008.1.2.5": subtype = ("image", "dicom-rle")
        case "1.2.840.10008.1.2.4.80", "1.2.840.10008.1.2.4.81": subtype = ("image", "jls")
        case "1.2.840.10008.1.2.4.90", "1.2.840.10008.1.2.4.91": subtype = ("image", "jp2")
        case "1.2.840.10008.1.2.4.92", "1.2.840.10008.1.2.4.93": subtype = ("image", "jpx")
        case "1.2.840.10008.1.2.4.201", "1.2.840.10008.1.2.4.202", "1.2.840.10008.1.2.4.203":
            subtype = ("image", "jphc")
        case "1.2.840.10008.1.2.4.110", "1.2.840.10008.1.2.4.111", "1.2.840.10008.1.2.4.112":
            subtype = ("image", "jxl")
        case "1.2.840.10008.1.2.4.100", "1.2.840.10008.1.2.4.100.1", "1.2.840.10008.1.2.4.101",
             "1.2.840.10008.1.2.4.101.1":
            subtype = ("video", "mpeg")
        case "1.2.840.10008.1.2.4.102", "1.2.840.10008.1.2.4.102.1", "1.2.840.10008.1.2.4.103",
             "1.2.840.10008.1.2.4.103.1", "1.2.840.10008.1.2.4.104", "1.2.840.10008.1.2.4.104.1",
             "1.2.840.10008.1.2.4.105", "1.2.840.10008.1.2.4.105.1", "1.2.840.10008.1.2.4.106",
             "1.2.840.10008.1.2.4.106.1":
            subtype = ("video", "mp4")
        case "1.2.840.10008.1.2.4.107", "1.2.840.10008.1.2.4.108": subtype = ("video", "h265")
        default: subtype = nil
        }
        return subtype.map {
            DICOMwebMediaType(type: $0.0, subtype: $0.1, parameters: [Parameter("transfer-syntax", transferSyntaxUID)])
        }
    }

    // MARK: Lexical helpers

    /// Splits on a separator outside quoted strings.
    static func split(_ string: String, on separator: Character) -> [String] {
        var fields: [String] = [], current = "", quoted = false, escaped = false
        for character in string {
            if escaped {
                current.append(character)
                escaped = false
            } else if quoted && character == "\\" {
                current.append(character)
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
                current.append(character)
            } else if character == separator && !quoted {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }

    static func isToken(_ string: some StringProtocol) -> Bool {
        !string.isEmpty && string.allSatisfy { character in
            guard character.isASCII, let scalar = character.unicodeScalars.first, scalar.value > 0x20,
                  scalar.value < 0x7F else { return false }
            return !"()<>@,;:\\\"/[]?={}".contains(character)
        }
    }

    private static func unquote(_ string: String) -> String {
        var result = "", escaped = false
        for character in string {
            if escaped {
                result.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static func quoteIfNeeded(_ value: String, always: Bool) -> String {
        if !always && isToken(value) { return value }
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

extension DICOMwebMediaType.Parameter {
    /// The parameter as compared: `type` values without regard to case.
    fileprivate var comparable: String {
        name + "=" + (name == "type" ? value.lowercased() : value)
    }
}

/// One member of an Accept header or `accept` Query Parameter: a media range
/// and its weight (PS3.18 8.4.1.1, 8.7.5).
public struct DICOMwebAcceptRange: Hashable, Sendable, CustomStringConvertible {
    /// The media range, without its `q` parameter.
    public var range: DICOMwebMediaType
    /// The qvalue, 0 to 1; 1 when absent.
    public var quality: Double

    public init(_ range: DICOMwebMediaType, quality: Double = 1) {
        self.range = range
        self.quality = quality
    }

    /// Parses a comma-separated list; malformed members are ignored, as
    /// PS3.18 8.7.7 requires of origin servers.
    public static func parse(_ list: String) -> [DICOMwebAcceptRange] {
        DICOMwebMediaType.split(list, on: ",").compactMap { member in
            let member = member.trimmingCharacters(in: .whitespaces)
            guard !member.isEmpty, var range = DICOMwebMediaType(member) else { return nil }
            var quality = 1.0
            if let q = range[parameter: "q"] {
                guard let value = Double(q), (0...1).contains(value) else { return nil }
                quality = value
                range[parameter: "q"] = nil
            }
            return DICOMwebAcceptRange(range, quality: quality)
        }
    }

    public var description: String {
        quality == 1 ? range.description : "\(range); q=\(quality)"
    }

    /// How specifically this range matches `candidate`, or nil when it does
    /// not match. A range parameter must be present with the same value in
    /// the candidate, except `boundary`; `transfer-syntax=*` matches any
    /// Transfer Syntax, and an absent `transfer-syntax` selects
    /// `defaultTransferSyntax` (PS3.18 8.7.8.2).
    func specificity(for candidate: DICOMwebMediaType, defaultTransferSyntax: String?) -> Int? {
        if range.type != "*" && range.type != candidate.type { return nil }
        if range.subtype != "*" && range.subtype != candidate.subtype { return nil }
        if range.type == "*" && range.subtype != "*" { return nil }
        var score = (range.type == "*" ? 0 : 1) + (range.subtype == "*" ? 0 : 1)
        if range.isMultipartRelated {
            guard let wanted = range.relatedType, let offered = candidate.relatedType else { return nil }
            if wanted.type != "*" && wanted.type != offered.type { return nil }
            if wanted.subtype != "*" && wanted.subtype != offered.subtype { return nil }
            score += (wanted.subtype == "*" ? 0 : 1)
        }
        let candidateSyntax = candidate.transferSyntax
        switch range.transferSyntax {
        case "*"?:
            score += 1
        case let syntax?:
            guard syntax == candidateSyntax else { return nil }
            score += 2
        case nil:
            // Wildcard ranges such as image/* leave the choice to the server.
            if !range.isRange && (range.relatedType?.isRange ?? false) == false,
               let candidateSyntax, let defaultTransferSyntax, candidateSyntax != defaultTransferSyntax {
                return nil
            }
        }
        for parameter in range.parameters where !["type", "boundary", "transfer-syntax"].contains(parameter.name) {
            guard candidate[parameter: parameter.name] == parameter.value else { return nil }
            score += 1
        }
        return score
    }
}

/// The negotiation of PS3.18 8.7.8: chooses the Selected Media Type among
/// the representations an origin server can produce for a resource.
public enum DICOMwebContentNegotiation {
    public enum Outcome: Equatable, Sendable {
        case selected(DICOMwebMediaType)
        /// 406 (Not Acceptable).
        case notAcceptable
        /// 400 (Bad Request): DICOM and rendered media types were mixed.
        case badRequest(String)
    }

    /// Selects a representation.
    ///
    /// - Parameters:
    ///   - query: the media types of the `accept` Query Parameter.
    ///   - header: the media ranges of the Accept header field; nil when the
    ///     request has none, which yields 406.
    ///   - supported: the representations the server can produce, in its
    ///     order of preference; ties go to the earlier one.
    ///   - defaultType: the default representation of the resource category,
    ///     used when a wildcard range of the header matches it.
    ///   - defaultTransferSyntax: the Transfer Syntax selected by a DICOM
    ///     media type without a `transfer-syntax` parameter.
    public static func select(
        query: [DICOMwebAcceptRange] = [], header: [DICOMwebAcceptRange]?,
        supported: [DICOMwebMediaType], defaultType: DICOMwebMediaType?,
        defaultTransferSyntax: String? = TransferSyntax.explicitVRLittleEndian
    ) -> Outcome {
        guard let header else { return .notAcceptable }
        let requested = (query + header).map(\.range).filter { !$0.isRange || $0.isMultipartRelated }
        if requested.contains(where: isDICOM) && requested.contains(where: { !isDICOM($0) && !isGeneric($0) }) {
            return .badRequest("DICOM and rendered media types cannot be requested together")
        }
        for list in [query, header] {
            if let best = best(in: list, supported: supported, defaultTransferSyntax: defaultTransferSyntax) {
                return .selected(best)
            }
        }
        if let defaultType, header.contains(where: { $0.quality > 0 && $0.range.isRange
            && $0.specificity(for: defaultType, defaultTransferSyntax: defaultTransferSyntax) != nil }) {
            return .selected(defaultType)
        }
        return .notAcceptable
    }

    private static func best(
        in list: [DICOMwebAcceptRange], supported: [DICOMwebMediaType], defaultTransferSyntax: String?
    ) -> DICOMwebMediaType? {
        var best: (type: DICOMwebMediaType, quality: Double)?
        for candidate in supported {
            // The qvalue of the most specific matching range (RFC 9110 12.5.1).
            var match: (specificity: Int, quality: Double)?
            // */* stands for the default media type of the category
            // (PS3.18 8.7.7); it is applied after the other ranges.
            for member in list where member.range.type != "*" {
                guard let specificity = member.specificity(for: candidate, defaultTransferSyntax: defaultTransferSyntax)
                else { continue }
                if match == nil || specificity > match!.specificity { match = (specificity, member.quality) }
            }
            guard let match, match.quality > 0 else { continue }
            if best == nil || match.quality > best!.quality { best = (candidate, match.quality) }
        }
        return best?.type
    }

    /// Whether a media type is a DICOM media type (PS3.18 8.7.3.5):
    /// application/dicom, its JSON and XML forms, or multipart thereof.
    static func isDICOM(_ type: DICOMwebMediaType) -> Bool {
        let part = type.relatedType ?? type
        return part.type == "application" && ["dicom", "dicom+json", "dicom+xml"].contains(part.subtype)
    }

    /// Media types that may be either Bulk Data or rendered.
    private static func isGeneric(_ type: DICOMwebMediaType) -> Bool {
        let part = type.relatedType ?? type
        return part.isRange || part.type == "image" || part.type == "video" || part == .octetStream
    }
}
