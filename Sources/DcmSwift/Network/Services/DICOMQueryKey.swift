//
//  DICOMQueryKey.swift
//  DcmSwift
//
//  A matching or return key of a C-FIND, as an expert types it: a keyword
//  or a tag, inside the Items of sequences if need be, and its value.
//

import Foundation

/// Why a query key cannot be read.
public struct DICOMQueryKeyError: Error, Sendable, Equatable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) { self.description = description }
}

/// A matching or return key of a query (PS3.4 C.2.2.1): an attribute,
/// possibly inside sequence Items, and its value.
///
/// A key is written `Keyword[=value]` or `gggg,eeee[=value]`; a key inside a
/// sequence is written `Sequence[0].Keyword`, the index naming the Item. An
/// empty value makes a return key, or a universal match (PS3.4 C.2.2.2.3);
/// a sequence without Item index asks for the whole sequence (C.2.2.2.6).
public struct DICOMQueryKey: Sendable, Hashable {
    /// One step of the path of a key.
    public struct Component: Sendable, Hashable {
        /// The tag, as eight uppercase hexadecimal digits.
        public let tag: String
        /// The keyword of the attribute.
        public let keyword: String
        /// The Item of the sequence the path goes into, if any.
        public let item: Int?
    }

    /// The attributes from the top-level data set down to the key.
    public let path: [Component]
    /// The matching value; empty for a return key.
    public let value: String

    /// Reads a key written `path[=value]`.
    ///
    /// - Parameter text: The key, as `PatientName=DOE*`, `0010,0020` or
    ///   `ScheduledProcedureStepSequence[0].Modality=CT`.
    /// - Throws: ``DICOMQueryKeyError`` for an unknown keyword or tag, an
    ///   invalid Item index, or an index on an attribute that is not a sequence.
    public init(_ text: String) throws {
        let parts = text.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        try self.init(path: String(parts[0]), value: parts.count > 1 ? String(parts[1]) : "")
    }

    /// Reads a key from its path and its value.
    ///
    /// - Parameters:
    ///   - path: The path, as `Keyword`, `gggg,eeee` or `Sequence[0].Keyword`.
    ///   - value: The matching value; empty for a return key.
    /// - Throws: ``DICOMQueryKeyError`` when the path cannot be read.
    public init(path: String, value: String) throws {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw DICOMQueryKeyError("empty key") }
        let components = try trimmed.split(separator: ".", omittingEmptySubsequences: false).map { try Self.component(String($0)) }
        for component in components.dropLast() where component.item == nil {
            throw DICOMQueryKeyError("\(component.keyword) needs an Item index")
        }
        for component in components where component.item != nil && Self.vr(of: component.tag) != "SQ" {
            throw DICOMQueryKeyError("\(component.keyword) is not a sequence")
        }
        self.path = components
        self.value = value
    }

    /// The path, written with keywords: `Sequence[0].Keyword`.
    public var pathDescription: String {
        path.map { component in component.item.map { "\(component.keyword)[\($0)]" } ?? component.keyword }.joined(separator: ".")
    }

    /// The Value Representation of the attribute the key names.
    public var vr: String { path.last.map { Self.vr(of: $0.tag) } ?? "UN" }

    /// Builds the identifier of a query: the Query/Retrieve Level, if given,
    /// then every key, the Items on their paths created as needed.
    ///
    /// - Parameters:
    ///   - keys: The matching and return keys.
    ///   - level: The Query/Retrieve Level (0008,0052), as `STUDY`; nil for a
    ///     query without level, as a worklist query.
    /// - Returns: The identifier, ready for a C-FIND.
    /// - Throws: ``DICOMQueryKeyError`` when a value does not suit its VR.
    public static func identifier(_ keys: [DICOMQueryKey], level: String?) throws -> DataSet {
        var object: [String: Any] = [:]
        if let level { object["00080052"] = ["vr": "CS", "Value": [level]] }
        for key in keys { try insert(key.value, at: key.path[...], into: &object) }
        do {
            return try DICOMJSON.dataSet(object)
        } catch {
            throw DICOMQueryKeyError("invalid keys: \(error)")
        }
    }

    // MARK: - Reading

    private static func vr(of tag: String) -> String {
        DicomSpec.shared.vrForTag(withCode: tag.lowercased()).map { "\($0)" } ?? "UN"
    }

    private static func component(_ text: String) throws -> Component {
        var name = text.trimmingCharacters(in: .whitespaces)
        var item: Int?
        if let open = name.firstIndex(of: "["), name.hasSuffix("]") {
            guard let index = Int(name[name.index(after: open)..<name.index(before: name.endIndex)]), index >= 0 else {
                throw DICOMQueryKeyError("invalid Item index in \(text)")
            }
            item = index
            name = String(name[..<open])
        }
        let keyword = try self.keyword(name)
        guard let tag = DicomSpec.shared.dataTag(forName: keyword) else { throw DICOMQueryKeyError("unknown keyword \(name)") }
        return Component(tag: tag.code.uppercased(), keyword: keyword, item: item)
    }

    /// A keyword, from a keyword or a `gggg,eeee` or `(gggg,eeee)` tag.
    private static func keyword(_ key: String) throws -> String {
        let hex = key.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        if hex.count == 8, hex.allSatisfy(\.isHexDigit) {
            guard let name = DicomSpec.shared.nameForTag(withCode: hex.lowercased()) else {
                throw DICOMQueryKeyError("unknown tag \(key)")
            }
            return name
        }
        guard !key.isEmpty, DicomSpec.shared.dataTag(forName: key) != nil else { throw DICOMQueryKeyError("unknown keyword \(key)") }
        return key
    }

    /// Sets a key in a DICOM JSON object, creating the Items on its path.
    private static func insert(_ value: String, at path: ArraySlice<Component>, into object: inout [String: Any]) throws {
        guard let component = path.first else { return }
        let vr = vr(of: component.tag)
        if let index = component.item {
            var attribute = object[component.tag] as? [String: Any] ?? ["vr": "SQ"]
            var items = attribute["Value"] as? [[String: Any]] ?? []
            while items.count <= index { items.append([:]) }
            try insert(value, at: path.dropFirst(), into: &items[index])
            attribute["Value"] = items
            object[component.tag] = attribute
            return
        }
        var attribute: [String: Any] = ["vr": vr]
        if !value.isEmpty, vr != "SQ" {
            switch vr {
            case "PN": attribute["Value"] = [["Alphabetic": value]]
            case "US", "SS", "UL", "SL", "UV", "SV", "FL", "FD":
                guard let number = Double(value) else { throw DICOMQueryKeyError("\(component.keyword) expects a number") }
                attribute["Value"] = [number]
            default: attribute["Value"] = value.components(separatedBy: "\\")
            }
        }
        object[component.tag] = attribute
    }
}
