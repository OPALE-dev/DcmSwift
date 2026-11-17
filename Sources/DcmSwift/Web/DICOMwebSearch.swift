import Foundation

/// The IE level searched by a Search Transaction (PS3.18 10.6).
public enum DICOMwebSearchLevel: String, Sendable, CaseIterable {
    case study = "STUDY"
    case series = "SERIES"
    case instance = "IMAGE"

    /// The attributes every match of this level carries when known
    /// (PS3.18 Tables 10.6.3-3, 10.6.3-4, and 10.6.3-5).
    public var responseKeywords: [String] {
        switch self {
        case .study:
            return ["StudyDate", "StudyTime", "AccessionNumber", "InstanceAvailability", "ModalitiesInStudy",
                    "ReferringPhysicianName", "TimezoneOffsetFromUTC", "RetrieveURL", "PatientName", "PatientID",
                    "PatientBirthDate", "PatientSex", "StudyInstanceUID", "StudyID", "NumberOfStudyRelatedSeries",
                    "NumberOfStudyRelatedInstances"]
        case .series:
            return ["Modality", "TimezoneOffsetFromUTC", "SeriesDescription", "RetrieveURL", "SeriesInstanceUID",
                    "SeriesNumber", "NumberOfSeriesRelatedInstances", "PerformedProcedureStepStartDate",
                    "PerformedProcedureStepStartTime"]
        case .instance:
            return ["SOPClassUID", "SOPInstanceUID", "InstanceAvailability", "TimezoneOffsetFromUTC", "RetrieveURL",
                    "InstanceNumber", "Rows", "Columns", "BitsAllocated", "NumberOfFrames"]
        }
    }
}

/// An attribute in a Query Parameter: a keyword or tag, or a path through
/// Sequences such as `OtherPatientIDsSequence.PatientID` (PS3.18 8.3.1).
public struct DICOMwebAttributePath: Hashable, Sendable, CustomStringConvertible {
    /// Keywords from the outermost Sequence to the attribute.
    public let keywords: [String]

    public init(_ keywords: [String]) {
        self.keywords = keywords
    }

    /// Parses keywords and 8-digit hexadecimal tags separated by dots; nil
    /// for unknown attributes or a malformed path. Every element but the last
    /// must be a Sequence; the last may be one only for a return key, such as
    /// `includefield=00081049` (PS3.18 10.6.1.2.1).
    public init?(parsing string: String, allowsSequence: Bool = false) {
        var keywords: [String] = []
        for component in string.split(separator: ".", omittingEmptySubsequences: false) {
            let component = String(component)
            if component.count == 8, component.allSatisfy(\.isHexDigit) {
                guard let keyword = DicomSpec.shared.nameForTag(withCode: component.lowercased()) else { return nil }
                keywords.append(keyword)
            } else {
                guard let first = component.first, first.isUppercase, component.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
                      DicomSpec.shared.dataTag(forName: component) != nil else { return nil }
                keywords.append(component)
            }
        }
        guard !keywords.isEmpty else { return nil }
        for (index, keyword) in keywords.enumerated() {
            guard let tag = DicomSpec.shared.dataTag(forName: keyword) else { return nil }
            let isSequence = DicomSpec.shared.vrForTag(withCode: tag.code) == .SQ
            let isLast = index == keywords.count - 1
            if isLast ? (isSequence && !allowsSequence) : !isSequence { return nil }
        }
        self.keywords = keywords
    }

    public var description: String { keywords.joined(separator: ".") }
}

/// The Query Parameters of a Search Transaction (PS3.18 8.3.4, 10.6.1.2).
public struct DICOMwebSearchQuery: Sendable, Equatable {
    /// Matching keys with their values; several values make a UID list.
    public var matches: [(attribute: DICOMwebAttributePath, values: [String])] = []
    /// Attributes to return (`includefield`).
    public var includeFields: [DICOMwebAttributePath] = []
    /// `includefield=all`.
    public var includeAllFields = false
    public var limit: Int?
    public var offset = 0
    public var fuzzyMatching = false
    public var emptyValueMatching = false
    public var multipleValueMatching = false
    /// Parameters that are not search parameters, such as `accept`, kept as
    /// received.
    public var otherParameters: [(name: String, values: [String])] = []

    public init() {}

    /// A query matching `attribute` with `value`.
    public mutating func match(_ keyword: String, _ value: String) {
        matches.append((DICOMwebAttributePath([keyword]), [value]))
    }

    public static func == (lhs: DICOMwebSearchQuery, rhs: DICOMwebSearchQuery) -> Bool {
        lhs.queryString == rhs.queryString
    }

    public struct ParseError: Error, Equatable, CustomStringConvertible {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var description: String { message }
    }

    /// Parses a query component (without "?"). Unknown parameter names are
    /// kept in `otherParameters`; invalid values of search parameters throw,
    /// which an origin server answers with 400 (PS3.18 8.3).
    public init(query: String) throws {
        guard !query.isEmpty else { return }
        for parameter in query.split(separator: "&", omittingEmptySubsequences: true) {
            let pair = parameter.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = String(pair[0]).removingPercentEncoding, !name.isEmpty else {
                throw ParseError("malformed query parameter \(parameter)")
            }
            let values: [String] = pair.count > 1
                ? try pair[1].split(separator: ",", omittingEmptySubsequences: false).map {
                    guard let value = String($0).removingPercentEncoding else {
                        throw ParseError("malformed percent-encoding in \(name)")
                    }
                    return value
                }
                : []
            try apply(name: name, values: values)
        }
    }

    private mutating func apply(name: String, values: [String]) throws {
        func flag() throws -> Bool {
            guard values.count == 1, ["true", "false"].contains(values[0]) else {
                throw ParseError("\(name) must be true or false")
            }
            return values[0] == "true"
        }
        func count() throws -> Int {
            guard values.count == 1, let value = Int(values[0]), value >= 0 else {
                throw ParseError("\(name) must be an unsigned integer")
            }
            return value
        }
        switch name {
        case "includefield":
            for value in values {
                if value == "all" {
                    includeAllFields = true
                } else {
                    guard let path = DICOMwebAttributePath(parsing: value, allowsSequence: true) else {
                        throw ParseError("unknown includefield attribute \(value)")
                    }
                    includeFields.append(path)
                }
            }
        case "limit": limit = try count()
        case "offset": offset = try count()
        case "fuzzymatching": fuzzyMatching = try flag()
        case "emptyvaluematching": emptyValueMatching = try flag()
        case "multiplevaluematching": multipleValueMatching = try flag()
        default:
            if let first = name.first, first.isUppercase || name.count == 8 || name.contains(".") {
                guard let path = DICOMwebAttributePath(parsing: name) else {
                    throw ParseError("unknown attribute \(name)")
                }
                guard !matches.contains(where: { $0.attribute == path }) else {
                    throw ParseError("attribute \(name) is repeated")
                }
                matches.append((path, values.isEmpty ? [""] : values))
            } else {
                otherParameters.append((name, values))
            }
        }
    }

    /// The parameters, in a stable order.
    public var queryItems: [(name: String, value: String)] {
        var items: [(String, String)] = matches.map { ($0.attribute.description, $0.values.map(Self.encode).joined(separator: ",")) }
        if includeAllFields {
            items.append(("includefield", "all"))
        } else if !includeFields.isEmpty {
            items.append(("includefield", includeFields.map(\.description).joined(separator: ",")))
        }
        if fuzzyMatching { items.append(("fuzzymatching", "true")) }
        if emptyValueMatching { items.append(("emptyvaluematching", "true")) }
        if multipleValueMatching { items.append(("multiplevaluematching", "true")) }
        if let limit { items.append(("limit", String(limit))) }
        if offset > 0 { items.append(("offset", String(offset))) }
        for other in otherParameters { items.append((Self.encode(other.name), other.values.map(Self.encode).joined(separator: ","))) }
        return items
    }

    /// The query component, percent-encoded, without "?".
    public var queryString: String {
        queryItems.map { $0.value.isEmpty ? $0.name : "\($0.name)=\($0.value)" }.joined(separator: "&")
    }

    /// Percent-encodes a value: only unreserved characters and the
    /// qp-special characters other than "?" stay as they are (PS3.18 8.3.1).
    static func encode(_ value: String) -> String {
        var allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        allowed.insert(charactersIn: "!$'()*+;:@/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// The C-FIND identifier of this query at `level`: Query/Retrieve Level,
    /// matching keys (UID lists joined by backslashes), and empty return keys
    /// for `includefield` and the attributes of the level (PS3.4 C.4.1).
    public func identifier(level: DICOMwebSearchLevel, returnKeywords: [String]? = nil) -> DataSet {
        let identifier = DataSet()
        _ = identifier.set(value: level.rawValue, forTagName: "QueryRetrieveLevel")
        var present = Set<String>()
        for match in matches {
            if match.attribute.keywords.count == 1 {
                let keyword = match.attribute.keywords[0]
                _ = identifier.set(value: match.values.joined(separator: "\\"), forTagName: keyword)
                present.insert(keyword)
            } else {
                Self.appendSequenceKey(match.attribute.keywords, value: match.values.joined(separator: "\\"), to: identifier)
                present.insert(match.attribute.keywords[0])
            }
        }
        for keyword in (returnKeywords ?? level.responseKeywords) + includeFields.filter({ $0.keywords.count == 1 }).map({ $0.keywords[0] })
            where !present.contains(keyword) && keyword != "RetrieveURL" {
            if DicomSpec.shared.dataTag(forName: keyword).flatMap({ DicomSpec.shared.vrForTag(withCode: $0.code) }) == .SQ {
                continue
            }
            if identifier.set(value: "", forTagName: keyword) != nil { present.insert(keyword) }
        }
        return identifier
    }

    /// Adds a matching key inside one Item of each Sequence of the path.
    private static func appendSequenceKey(_ keywords: [String], value: String, to dataSet: DataSet) {
        guard let tag = DicomSpec.shared.dataTag(forName: keywords[0]) else { return }
        let sequence = DataSequence(withTag: tag, parent: nil)
        sequence.dataset = dataSet
        sequence.vr = .SQ
        sequence.vrMethod = .Explicit
        sequence.length = -1
        let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
        item.dataset = dataSet
        item.length = -1
        var parent: DataItem = item
        for keyword in keywords.dropFirst().dropLast() {
            guard let inner = DicomSpec.shared.dataTag(forName: keyword) else { return }
            let nested = DataSequence(withTag: inner, parent: parent)
            nested.dataset = dataSet
            nested.vr = .SQ
            nested.vrMethod = .Explicit
            nested.length = -1
            let nestedItem = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: nested)
            nestedItem.dataset = dataSet
            nestedItem.length = -1
            nested.items.append(nestedItem)
            parent.elements.append(nested)
            parent = nestedItem
        }
        guard let leafTag = DicomSpec.shared.dataTag(forName: keywords[keywords.count - 1]) else { return }
        let leaf = DataElement(withTag: leafTag, dataset: dataSet, parent: parent)
        leaf.vr = DicomSpec.shared.vrForTag(withCode: leafTag.code) ?? .UN
        guard leaf.setValue(value) else { return }
        parent.elements.append(leaf)
        sequence.items.append(item)
        dataSet.add(element: sequence)
    }
}
