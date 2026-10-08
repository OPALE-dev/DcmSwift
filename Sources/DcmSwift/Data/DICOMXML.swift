import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// The Native DICOM Model (PS3.19 A.1), the XML representation PS3.18
/// uses as `application/dicom+xml`.
///
/// Built on the DICOM JSON Model through the mapping of PS3.18 F.3, so both
/// share their value rules. Specific to XML: private elements carry their
/// creator as `privateCreator` with a `gggg00ee` tag, the Private Creator
/// elements themselves are implied, and Person Names are split into their
/// components.
public enum DICOMXML {
    public static let namespace = "http://dicom.nema.org/PS3.19/models/NativeDICOM"

    // MARK: Encoding

    /// One data set as a NativeDicomModel document, in UTF-8.
    public static func encode(_ dataSet: DataSet, options: DICOMJSON.EncodingOptions = .init()) throws -> Data {
        var options = options
        // Text keeps IS and DS as written.
        options.numbersAsStrings = true
        let object = try DICOMJSON.object(dataSet, options: options)
        var output = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        output += "<NativeDicomModel xmlns=\"\(namespace)\" xml:space=\"preserve\">"
        try writeDataSet(object, to: &output, depth: 1, pretty: options.prettyPrinted)
        if options.prettyPrinted { output += "\n" }
        output += "</NativeDicomModel>\n"
        return Data(output.utf8)
    }

    private static func writeDataSet(_ object: [String: Any], to output: inout String, depth: Int, pretty: Bool) throws {
        func isCreator(_ key: String) -> Bool {
            let group = UInt16(key.prefix(4), radix: 16) ?? 0, element = UInt16(key.suffix(4), radix: 16) ?? 0
            return group % 2 == 1 && (0x10...0xFF).contains(element)
        }
        for key in object.keys.sorted() where !isCreator(key) {
            guard let attribute = object[key] as? [String: Any], let vr = attribute["vr"] as? String else { continue }
            let group = UInt16(key.prefix(4), radix: 16) ?? 0, element = UInt16(key.suffix(4), radix: 16) ?? 0
            var tag = key, creator: String?
            if group % 2 == 1, element >> 8 >= 0x10 {
                let creatorKey = String(format: "%04X%04X", group, element >> 8)
                if let reservation = object[creatorKey] as? [String: Any],
                   let name = (reservation["Value"] as? [Any])?.first as? String {
                    creator = name
                    tag = String(format: "%04X00%02X", group, element & 0xFF)
                }
            }
            newline(&output, depth, pretty)
            output += "<DicomAttribute tag=\"\(tag)\" vr=\"\(vr)\""
            if creator == nil, let keyword = DicomSpec.shared.nameForTag(withCode: key.lowercased()), !keyword.isEmpty {
                output += " keyword=\"\(escape(keyword))\""
            }
            if let creator { output += " privateCreator=\"\(escape(creator))\"" }
            output += ">"
            let start = output.utf8.count
            if let uri = attribute["BulkDataURI"] as? String {
                output += "<BulkData uri=\"\(escape(uri))\"/>"
            } else if let binary = attribute["InlineBinary"] as? String {
                output += "<InlineBinary>\(binary)</InlineBinary>"
            } else if let values = attribute["Value"] as? [Any] {
                for (index, value) in values.enumerated() {
                    let number = index + 1
                    switch vr {
                    case "SQ":
                        newline(&output, depth + 1, pretty)
                        output += "<Item number=\"\(number)\">"
                        try writeDataSet(value as? [String: Any] ?? [:], to: &output, depth: depth + 2, pretty: pretty)
                        newline(&output, depth + 1, pretty)
                        output += "</Item>"
                    case "PN":
                        output += "<PersonName number=\"\(number)\">"
                        for group in ["Alphabetic", "Ideographic", "Phonetic"] {
                            guard let text = (value as? [String: Any])?[group] as? String else { continue }
                            output += "<\(group)>"
                            let components = text.split(separator: "^", omittingEmptySubsequences: false)
                            for (name, component) in zip(["FamilyName", "GivenName", "MiddleName", "NamePrefix", "NameSuffix"],
                                                         components) where !component.isEmpty {
                                output += "<\(name)>\(escape(String(component)))</\(name)>"
                            }
                            output += "</\(group)>"
                        }
                        output += "</PersonName>"
                    default:
                        if value is NSNull {
                            output += "<Value number=\"\(number)\"/>"
                        } else {
                            output += "<Value number=\"\(number)\">\(escape(text(value)))</Value>"
                        }
                    }
                }
                if vr == "SQ", !values.isEmpty { newline(&output, depth, pretty) }
            }
            if output.utf8.count == start {
                output.removeLast()
                output += "/>"
            } else {
                output += "</DicomAttribute>"
            }
        }
    }

    private static func newline(_ output: inout String, _ depth: Int, _ pretty: Bool) {
        if pretty { output += "\n" + String(repeating: "  ", count: depth) }
    }

    private static func text(_ value: Any) -> String {
        switch value {
        case let text as String: return text
        case let number as Double:
            return number == number.rounded() && abs(number) < 1e15 ? String(Int64(number)) : "\(number)"
        case let number as Int: return String(number)
        case let number as NSNumber: return number.stringValue
        default: return "\(value)"
        }
    }

    /// Escapes text and attribute values; characters XML 1.0 cannot carry
    /// become U+FFFD.
    static func escape(_ text: String) -> String {
        var output = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": output += "&amp;"
            case "<": output += "&lt;"
            case ">": output += "&gt;"
            case "\"": output += "&quot;"
            case "\r": output += "&#13;"
            case _ where scalar.value < 0x20 && scalar != "\n" && scalar != "\t":
                output.unicodeScalars.append("\u{FFFD}")
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        return output
    }

    // MARK: Decoding

    /// A data set from a NativeDicomModel document.
    public static func decode(_ data: Data, options: DICOMJSON.DecodingOptions = .init()) throws -> DataSet {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldProcessNamespaces = true
        guard parser.parse(), reader.isComplete, let root = reader.root else {
            throw DICOMJSONError(reader.error ?? "invalid XML: \(parser.parserError?.localizedDescription ?? "no NativeDicomModel")")
        }
        guard root.name == "NativeDicomModel" else { throw DICOMJSONError("the root element is \(root.name)") }
        return try DICOMJSON.dataSet(jsonObject(root), options: options)
    }

    /// An XML element, as parsed.
    final class Node {
        let name: String
        let attributes: [String: String]
        var children: [Node] = []
        var text = ""

        init(name: String, attributes: [String: String]) {
            self.name = name
            self.attributes = attributes
        }

        func children(_ name: String) -> [Node] { children.filter { $0.name == name } }
    }

    final class Reader: NSObject, XMLParserDelegate {
        var root: Node?
        var stack: [Node] = []
        var error: String?
        /// The root element ended: libxml2 (Linux) reports success on some
        /// truncated documents.
        var isComplete = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if stack.isEmpty, namespaceURI != nil, namespaceURI != DICOMXML.namespace, !(namespaceURI ?? "").isEmpty {
                error = "unexpected namespace \(namespaceURI ?? "")"
                parser.abortParsing()
                return
            }
            let node = Node(name: name, attributes: attributes)
            stack.last?.children.append(node)
            if stack.isEmpty { root = node }
            stack.append(node)
            if stack.count > 512 {
                error = "nesting is too deep"
                parser.abortParsing()
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            stack.removeLast()
            if stack.isEmpty { isComplete = true }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, foundCDATA data: Data) {
            stack.last?.text += String(decoding: data, as: UTF8.self)
        }
    }

    /// The DICOM JSON object of a data set node (PS3.18 F.3).
    private static func jsonObject(_ node: Node) throws -> [String: Any] {
        var object: [String: Any] = [:]
        var blocks: [String: [String: UInt16]] = [:]  // group -> creator -> block
        for attribute in node.children("DicomAttribute") {
            guard var tag = attribute.attributes["tag"]?.uppercased(), tag.count == 8, tag.allSatisfy(\.isHexDigit) else {
                throw DICOMJSONError("DicomAttribute without a valid tag")
            }
            guard let vr = attribute.attributes["vr"] else { throw DICOMJSONError("\(tag) has no vr") }
            if let creator = attribute.attributes["privateCreator"] {
                // Reserve one block per creator and group, as the binary
                // encoding needs.
                let group = String(tag.prefix(4))
                guard let groupNumber = UInt16(group, radix: 16), groupNumber % 2 == 1 else {
                    throw DICOMJSONError("\(tag) has a privateCreator but is not private")
                }
                var groupBlocks = blocks[group, default: [:]]
                let block = groupBlocks[creator] ?? UInt16(0x10 + groupBlocks.count)
                guard block <= 0xFF else { throw DICOMJSONError("too many private creators in group \(group)") }
                groupBlocks[creator] = block
                blocks[group] = groupBlocks
                object[String(format: "%@%04X", group, block)] = ["vr": "LO", "Value": [creator]]
                tag = String(format: "%@%02X%@", group, block, String(tag.suffix(2)))
            }
            var json: [String: Any] = ["vr": vr]
            if let bulk = attribute.children("BulkData").first {
                guard let uri = bulk.attributes["uri"] ?? bulk.attributes["uuid"] else {
                    throw DICOMJSONError("\(tag) BulkData has no uri")
                }
                json["BulkDataURI"] = uri
            } else if let inline = attribute.children("InlineBinary").first {
                json["InlineBinary"] = inline.text.filter { !$0.isWhitespace }
            } else if vr == "SQ" {
                let items = try numbered(attribute.children("Item"), tag)
                if !items.isEmpty {
                    json["Value"] = try items.map { item -> [String: Any] in
                        guard let item else { return [:] }
                        return try jsonObject(item)
                    }
                }
            } else if vr == "PN" {
                let names = try numbered(attribute.children("PersonName"), tag)
                if !names.isEmpty { json["Value"] = names.map { $0.map(personName) ?? NSNull() } }
            } else {
                let values = try numbered(attribute.children("Value"), tag)
                if !values.isEmpty { json["Value"] = try values.map { try value($0?.text, vr: vr, tag: tag) } }
            }
            object[tag] = json
        }
        return object
    }

    /// Nodes ordered by their `number`, with nil for missing numbers.
    private static func numbered(_ nodes: [Node], _ tag: String) throws -> [Node?] {
        var byNumber: [Int: Node] = [:]
        for node in nodes {
            guard let number = node.attributes["number"].flatMap(Int.init), number >= 1, number <= 1 << 20,
                  byNumber[number] == nil else {
                throw DICOMJSONError("\(tag) has an invalid or repeated number")
            }
            byNumber[number] = node
        }
        guard let last = byNumber.keys.max() else { return [] }
        return (1...last).map { byNumber[$0] }
    }

    private static func value(_ text: String?, vr: String, tag: String) throws -> Any {
        guard let text, !text.isEmpty else { return NSNull() }
        switch vr {
        case "US", "SS", "UL", "SL", "UV", "SV":
            if let number = Int64(text.trimmingCharacters(in: .whitespaces)) { return NSNumber(value: number) }
            if let number = UInt64(text.trimmingCharacters(in: .whitespaces)) { return NSNumber(value: number) }
            throw DICOMJSONError("\(tag) Value \(text) is not an integer")
        case "FL", "FD":
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if let number = Double(trimmed), number.isFinite { return number }
            if ["NaN", "Infinity", "-Infinity"].contains(trimmed) { return trimmed }
            throw DICOMJSONError("\(tag) Value \(text) is not a number")
        default:
            return text
        }
    }

    private static func personName(_ node: Node) -> Any {
        var name: [String: String] = [:]
        for group in ["Alphabetic", "Ideographic", "Phonetic"] {
            guard let element = node.children(group).first else { continue }
            var components = ["FamilyName", "GivenName", "MiddleName", "NamePrefix", "NameSuffix"].map {
                element.children($0).first?.text ?? ""
            }
            while components.last == "" { components.removeLast() }
            name[group] = components.joined(separator: "^")
        }
        return name
    }
}
