import Foundation

/// A data set that cannot be represented in, or read from, the DICOM JSON
/// Model.
public struct DICOMJSONError: Error, Equatable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) { self.message = message }

    public var description: String { "DICOM JSON: \(message)" }
}

/// The DICOM JSON Model (PS3.18 Annex F): media type
/// `application/dicom+json`, UTF-8.
///
/// Attributes are keyed by their uppercase tag in ascending order, Group
/// Length attributes are left out, empty Values become `null`, empty
/// attributes have no `Value`, binary Value Fields are `InlineBinary` in
/// Little Endian unless a Bulk Data URI is given, and encapsulated Pixel
/// Data is its Item sequence without the Sequence Delimitation Item.
public enum DICOMJSON {
    public struct EncodingOptions {
        /// Includes the File Meta Information (group 0002).
        public var includesFileMetaInformation = false
        /// A Bulk Data URI for an attribute, used instead of its Value or
        /// InlineBinary (F.2.6); nil keeps the value inline.
        public var bulkDataURI: ((DataElement) -> String?)?
        /// IS and DS Values as JSON strings, keeping their original text,
        /// rather than numbers (F.2.3).
        public var numbersAsStrings = false
        /// An UN attribute whose tag has a single, non-SQ VR in the 2026d
        /// dictionary is written with that VR and its decoded Values, as
        /// PS3.5 6.2.2 permits; otherwise it stays UN.
        public var resolvesUnknownVRs = true
        public var prettyPrinted = false

        public init(
            includesFileMetaInformation: Bool = false, bulkDataURI: ((DataElement) -> String?)? = nil,
            numbersAsStrings: Bool = false, resolvesUnknownVRs: Bool = true, prettyPrinted: Bool = false
        ) {
            self.includesFileMetaInformation = includesFileMetaInformation
            self.bulkDataURI = bulkDataURI
            self.numbersAsStrings = numbersAsStrings
            self.resolvesUnknownVRs = resolvesUnknownVRs
            self.prettyPrinted = prettyPrinted
        }
    }

    public struct DecodingOptions {
        /// Fetches the Value Field a Bulk Data URI designates; without it,
        /// a BulkDataURI is an error.
        public var loadBulkData: ((String) throws -> Data)?

        public init(loadBulkData: ((String) throws -> Data)? = nil) {
            self.loadBulkData = loadBulkData
        }
    }

    // MARK: Encoding

    /// One data set as a DICOM JSON Model object.
    public static func encode(_ dataSet: DataSet, options: EncodingOptions = EncodingOptions()) throws -> Data {
        try serialize(object(dataSet, options: options), options: options)
    }

    /// Several data sets as the top-level array of F.2.1.
    public static func encode(_ dataSets: [DataSet], options: EncodingOptions = EncodingOptions()) throws -> Data {
        try serialize(dataSets.map { try object($0, options: options) }, options: options)
    }

    /// The JSON object of a data set, as Foundation values.
    public static func object(_ dataSet: DataSet, options: EncodingOptions = EncodingOptions()) throws -> [String: Any] {
        let elements = options.includesFileMetaInformation
            ? dataSet.metaInformationHeaderElements + dataSet.datasetElements : dataSet.datasetElements
        return try attributes(elements, options: options)
    }

    /// Writes JSON with keys in plain lexicographic order (F.2), which
    /// `JSONSerialization.sortedKeys` does not guarantee.
    private static func serialize(_ object: Any, options: EncodingOptions) throws -> Data {
        var output = ""
        try write(object, to: &output, indent: options.prettyPrinted ? 0 : nil)
        return Data(output.utf8)
    }

    private static func write(_ value: Any, to output: inout String, indent: Int?) throws {
        func newline(_ level: Int) {
            if let indent { output += "\n" + String(repeating: "  ", count: indent + level) }
        }
        switch value {
        case let object as [String: Any]:
            output += "{"
            for (index, key) in object.keys.sorted(by: { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) })
                .enumerated() {
                if index > 0 { output += "," }
                newline(1)
                writeString(key, to: &output)
                output += indent == nil ? ":" : ": "
                try write(object[key]!, to: &output, indent: indent.map { $0 + 1 })
            }
            if !object.isEmpty { newline(0) }
            output += "}"
        case let array as [Any]:
            output += "["
            for (index, element) in array.enumerated() {
                if index > 0 { output += "," }
                newline(1)
                try write(element, to: &output, indent: indent.map { $0 + 1 })
            }
            if !array.isEmpty { newline(0) }
            output += "]"
        case let text as String:
            writeString(text, to: &output)
        case is NSNull:
            output += "null"
        case let number as Double:
            guard number.isFinite else { throw DICOMJSONError("non-finite number") }
            output += number == number.rounded() && abs(number) < 1e15 ? String(Int64(number)) : "\(number)"
        case let number as Int:
            output += String(number)
        case let number as NSNumber:
            output += number.stringValue
        default:
            throw DICOMJSONError("cannot write \(type(of: value))")
        }
    }

    private static func writeString(_ text: String, to output: inout String) {
        output += "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case _ where scalar.value < 0x20:
                output += String(format: "\\u%04x", scalar.value)
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }

    private static func attributes(_ elements: [DataElement], options: EncodingOptions) throws -> [String: Any] {
        var object: [String: Any] = [:]
        for element in elements where element.tag.element.lowercased() != "0000" {
            let key = (element.tag.group + element.tag.element).uppercased()
            object[key] = try attribute(element, options: options)
        }
        return object
    }

    /// The element with its dictionary VR, when it is UN and that VR is
    /// unambiguous. UN Values are encoded as in Implicit VR Little Endian.
    static func resolvingUnknownVR(_ element: DataElement) -> DataElement {
        guard element.vr == .UN, !(element is DataSequence), let data = element.data else { return element }
        // Private Creators are LO (PS3.5 7.8.1).
        let candidates = element.tag.isPrivateCreator ? [.LO] : DicomSpec.shared.vrsForTag(withCode: element.tag.code)
        guard candidates.count == 1, let vr = candidates.first, vr != .UN else { return element }
        if vr == .SQ {
            // The Items, as encoded in Implicit VR Little Endian.
            var bytes = element.tag.data(withByteOrder: .LittleEndian)
            bytes.append(uint32: UInt32(data.count), bigEndian: false)
            bytes.append(data)
            guard let parsed = try? DICOMDataSetCoding.decode(bytes, transferSyntax: TransferSyntax.implicitVRLittleEndian),
                  let sequence = parsed.allElements.first as? DataSequence else { return element }
            return sequence
        }
        let resolved = DataElement(withTag: element.tag, dataset: element.dataset, parent: element.parent)
        resolved.vr = vr
        resolved.byteOrder = .LittleEndian
        resolved.characterSet = element.characterSet
        resolved.data = data
        resolved.length = data.count
        return resolved
    }

    private static func attribute(_ element: DataElement, options: EncodingOptions) throws -> [String: Any] {
        let element = options.resolvesUnknownVRs ? resolvingUnknownVR(element) : element
        let vr = "\(element.vr)"
        var attribute: [String: Any] = ["vr": vr]
        let tag = "(\(element.tag.group),\(element.tag.element))"

        if let pixels = element as? PixelSequence {
            if let uri = options.bulkDataURI?(element) {
                attribute["BulkDataURI"] = uri
            } else {
                var bytes = Data()
                for item in pixels.items {
                    bytes.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
                    bytes.append(uint32: UInt32(item.data?.count ?? 0), bigEndian: false)
                    if let data = item.data { bytes.append(data) }
                }
                attribute["InlineBinary"] = bytes.base64EncodedString()
            }
            return attribute
        }
        if let sequence = element as? DataSequence {
            if !sequence.items.isEmpty {
                attribute["Value"] = try sequence.items.map { try attributes($0.elements, options: options) }
            }
            return attribute
        }
        guard element.length > 0, let data = element.data, !data.isEmpty else { return attribute }
        if let uri = options.bulkDataURI?(element) {
            attribute["BulkDataURI"] = uri
            return attribute
        }

        func numbers<T>(_ values: [T]?, _ convert: (T) -> Any) throws -> [Any] {
            guard let values else { throw DICOMJSONError("\(tag) \(vr) has a length that is not a multiple of its size") }
            return values.map(convert)
        }
        func floating(_ value: Double) -> Any {
            // JSON has no NaN or infinities.
            value.isFinite ? value : (value.isNaN ? "NaN" : (value > 0 ? "Infinity" : "-Infinity"))
        }
        switch element.vr {
        case .OB, .OD, .OF, .OL, .OV, .OW, .UN:
            attribute["InlineBinary"] = element.encodedValueData(byteOrder: .LittleEndian).base64EncodedString()
        case .US: attribute["Value"] = try numbers(element.uint16Values) { Int($0) }
        case .SS: attribute["Value"] = try numbers(element.int16Values) { Int($0) }
        case .UL: attribute["Value"] = try numbers(element.uint32Values) { Int($0) }
        case .SL: attribute["Value"] = try numbers(element.int32Values) { Int($0) }
        case .UV: attribute["Value"] = try numbers(element.uint64Values) { NSNumber(value: $0) }
        case .SV: attribute["Value"] = try numbers(element.int64Values) { NSNumber(value: $0) }
        case .FL: attribute["Value"] = try numbers(element.float32Values) { floating(Double($0)) }
        case .FD: attribute["Value"] = try numbers(element.float64Values) { floating($0) }
        case .AT:
            attribute["Value"] = try numbers(element.attributeTagValues) { ($0.group + $0.element).uppercased() }
        case .SQ:
            break
        default:
            guard let values = element.textValues else {
                throw DICOMJSONError("\(tag) cannot be decoded in its Specific Character Set")
            }
            attribute["Value"] = values.map { value -> Any in
                switch element.vr {
                case .PN:
                    return personName(value)
                case .IS where !options.numbersAsStrings:
                    let trimmed = value.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty { return NSNull() }
                    return Int64(trimmed).map { NSNumber(value: $0) } ?? trimmed
                case .DS where !options.numbersAsStrings:
                    let trimmed = value.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty { return NSNull() }
                    if let number = Double(trimmed), number.isFinite { return number }
                    return trimmed
                case .IS, .DS:
                    // Leading and trailing spaces are not significant.
                    let trimmed = value.trimmingCharacters(in: .whitespaces)
                    return trimmed.isEmpty ? NSNull() : trimmed
                default:
                    return value.isEmpty ? NSNull() : value
                }
            }
        }
        return attribute
    }

    /// A PN Value as its non-empty component groups (F.2.2).
    private static func personName(_ value: String) -> Any {
        let groups = value.split(separator: "=", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        var name: [String: String] = [:]
        for (index, key) in ["Alphabetic", "Ideographic", "Phonetic"].enumerated() where index < groups.count {
            if !groups[index].isEmpty { name[key] = groups[index] }
        }
        return name.isEmpty ? NSNull() : name
    }

    // MARK: Decoding

    /// The data sets of a DICOM JSON Model object or array.
    public static func decode(_ data: Data, options: DecodingOptions = DecodingOptions()) throws -> [DataSet] {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw DICOMJSONError("invalid JSON: \(error.localizedDescription)")
        }
        if let object = json as? [String: Any] { return [try dataSet(object, options: options)] }
        if let array = json as? [Any] {
            return try array.map { entry in
                guard let object = entry as? [String: Any] else { throw DICOMJSONError("array entry is not an object") }
                return try dataSet(object, options: options)
            }
        }
        throw DICOMJSONError("the top level is neither an object nor an array")
    }

    /// A data set from a DICOM JSON Model object, in Explicit VR Little
    /// Endian, its strings encoded in its Specific Character Set.
    public static func dataSet(_ object: [String: Any], options: DecodingOptions = DecodingOptions()) throws -> DataSet {
        let dataSet = DataSet()
        dataSet.vrMethod = .Explicit
        dataSet.byteOrder = .LittleEndian
        let elements = try decodeAttributes(object, dataSet: dataSet, parent: nil, characterSet: nil, options: options)
        for element in elements { dataSet.add(element: element) }
        dataSet.sortElements()
        return dataSet
    }

    private static func decodeAttributes(
        _ object: [String: Any], dataSet: DataSet, parent: DataItem?, characterSet: DICOMCharacterSet?,
        options: DecodingOptions
    ) throws -> [DataElement] {
        // The Specific Character Set first: it decides how strings encode.
        var characterSet = characterSet
        if let declared = object["00080005"] as? [String: Any] {
            let values = (declared["Value"] as? [Any])?.map { ($0 as? String) ?? "" } ?? []
            characterSet = DICOMCharacterSet(specificCharacterSet: values.joined(separator: "\\"))
        }
        var elements: [DataElement] = []
        for key in object.keys.sorted() {
            guard key.count == 8, key.allSatisfy(\.isHexDigit) else { throw DICOMJSONError("invalid attribute name \(key)") }
            guard let attribute = object[key] as? [String: Any] else { throw DICOMJSONError("\(key) is not an object") }
            let element = try decodeAttribute(
                key, attribute, dataSet: dataSet, parent: parent, characterSet: characterSet, options: options)
            elements.append(element)
        }
        return elements
    }

    private static func decodeAttribute(
        _ key: String, _ attribute: [String: Any], dataSet: DataSet, parent: DataItem?,
        characterSet: DICOMCharacterSet?, options: DecodingOptions
    ) throws -> DataElement {
        let lower = key.lowercased()
        let tag = DataTag(withGroup: String(lower.prefix(4)), element: String(lower.suffix(4)))
        guard let vrName = attribute["vr"] as? String, let vr = DicomSpec.vr(for: vrName) else {
            throw DICOMJSONError("\(key) has no valid vr")
        }
        let present = ["Value", "InlineBinary", "BulkDataURI"].filter { attribute[$0] != nil }
        guard present.count <= 1 else { throw DICOMJSONError("\(key) has \(present.joined(separator: " and "))") }

        if vr == .SQ {
            let sequence = DataSequence(withTag: tag, parent: parent)
            sequence.dataset = dataSet
            sequence.vr = .SQ
            guard let items = attribute["Value"] as? [Any] ?? (attribute["Value"] == nil ? [] : nil) else {
                throw DICOMJSONError("\(key) Value is not an array")
            }
            for entry in items {
                guard let object = entry as? [String: Any] else { throw DICOMJSONError("\(key) item is not an object") }
                let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
                item.dataset = dataSet
                item.characterSet = characterSet
                item.elements = try decodeAttributes(
                    object, dataSet: dataSet, parent: item, characterSet: characterSet, options: options)
                sequence.items.append(item)
            }
            return sequence
        }

        // Binary Value Fields, inline or by reference.
        var binary: Data?
        if let base64 = attribute["InlineBinary"] {
            guard let text = base64 as? String, let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else {
                throw DICOMJSONError("\(key) InlineBinary is not base64")
            }
            binary = data
        } else if let uri = attribute["BulkDataURI"] {
            guard let text = uri as? String else { throw DICOMJSONError("\(key) BulkDataURI is not a string") }
            guard let load = options.loadBulkData else { throw DICOMJSONError("\(key) refers to bulk data \(text)") }
            binary = try load(text)
        }

        if tag.code == "7fe00010", let bytes = binary, let pixels = try encapsulatedPixels(bytes, tag: tag) {
            pixels.dataset = dataSet
            pixels.vr = vr
            pixels.length = -1
            return pixels
        }

        let element = DataElement(withTag: tag, dataset: dataSet, parent: parent)
        element.vr = vr
        element.characterSet = characterSet
        if let binary {
            if [.OB, .OD, .OF, .OL, .OV, .OW, .UN].contains(vr) {
                guard element.setValue(binary) else { throw DICOMJSONError("\(key) cannot hold binary data") }
            } else {
                // Bulk data of a non-binary VR is its Little Endian Value Field.
                element.data = binary
                element.length = binary.count
            }
            return element
        }
        guard let rawValues = attribute["Value"] else { return element }
        guard let values = rawValues as? [Any] else { throw DICOMJSONError("\(key) Value is not an array") }
        guard !values.isEmpty else { return element }

        func numbers() throws -> [NSNumber] {
            try values.map {
                guard let number = $0 as? NSNumber else {
                    throw DICOMJSONError("\(key) \(vrName) Value is not a number")
                }
                return number
            }
        }
        var stored = false
        switch vr {
        case .US: stored = element.setValue(try numbers().map { UInt16(truncating: $0) })
        case .SS: stored = element.setValue(try numbers().map { Int16(truncating: $0) })
        case .UL: stored = element.setValue(try numbers().map { UInt32(truncating: $0) })
        case .SL: stored = element.setValue(try numbers().map { Int32(truncating: $0) })
        case .UV: stored = element.setValue(try values.map { try unsigned64($0, key) })
        case .SV: stored = element.setValue(try values.map { try signed64($0, key) })
        case .FL: stored = element.setValue(try values.map { Float32(try floating($0, key)) })
        case .FD: stored = element.setValue(try values.map { try floating($0, key) })
        case .AT:
            let tags = try values.map { value -> DataTag in
                guard let text = (value as? String)?.lowercased(), text.count == 8, text.allSatisfy(\.isHexDigit) else {
                    throw DICOMJSONError("\(key) AT Value is not a tag")
                }
                return DataTag(withGroup: String(text.prefix(4)), element: String(text.suffix(4)))
            }
            stored = element.setValue(tags)
        default:
            let strings = try values.map { value -> String in
                switch value {
                case is NSNull: return ""
                case let text as String: return text
                case let number as NSNumber where vr == .IS || vr == .DS: return formatNumber(number, vr: vr)
                case let name as [String: Any] where vr == .PN:
                    var groups = ["Alphabetic", "Ideographic", "Phonetic"].map { (name[$0] as? String) ?? "" }
                    while groups.last == "" { groups.removeLast() }
                    return groups.joined(separator: "=")
                default: throw DICOMJSONError("\(key) \(vrName) Value has the wrong type")
                }
            }
            if strings.count > 1, strings.contains(where: { $0.contains("\\") }) {
                throw DICOMJSONError("\(key) Value contains the value delimiter")
            }
            stored = element.setValue(strings.joined(separator: "\\"))
        }
        guard stored else { throw DICOMJSONError("\(key) \(vrName) Value cannot be encoded") }
        return element
    }

    private static func unsigned64(_ value: Any, _ key: String) throws -> UInt64 {
        if let text = value as? String, let number = UInt64(text) { return number }
        if let number = value as? NSNumber { return number.uint64Value }
        throw DICOMJSONError("\(key) UV Value is not a number")
    }

    private static func signed64(_ value: Any, _ key: String) throws -> Int64 {
        if let text = value as? String, let number = Int64(text) { return number }
        if let number = value as? NSNumber { return number.int64Value }
        throw DICOMJSONError("\(key) SV Value is not a number")
    }

    private static func floating(_ value: Any, _ key: String) throws -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        switch value as? String {
        case "NaN"?: return .nan
        case "Infinity"?: return .infinity
        case "-Infinity"?: return -.infinity
        default: throw DICOMJSONError("\(key) floating point Value is not a number")
        }
    }

    /// An IS or DS Value from a JSON number, within the 12 and 16 bytes of
    /// PS3.5 Table 6.2-1.
    static func formatNumber(_ number: NSNumber, vr: VR.VR) -> String {
        let double = number.doubleValue
        if vr == .IS || (double == double.rounded() && abs(double) < 1e15) {
            return String(Int64(double))
        }
        var text = "\(double)"
        if text.count > 16 {
            for digits in stride(from: 15, through: 1, by: -1) {
                text = String(format: "%.\(digits)G", double)
                if text.count <= 16 { break }
            }
        }
        return text
    }

    /// The Items of encapsulated Pixel Data, or nil when the bytes are not
    /// an Item sequence.
    private static func encapsulatedPixels(_ bytes: Data, tag: DataTag) throws -> PixelSequence? {
        let raw = [UInt8](bytes)
        guard raw.count >= 8, raw[0] == 0xFE, raw[1] == 0xFF, raw[2] == 0x00, raw[3] == 0xE0 else { return nil }
        let sequence = PixelSequence(withTag: tag)
        var offset = 0
        while offset + 8 <= raw.count {
            guard raw[offset] == 0xFE, raw[offset + 1] == 0xFF, raw[offset + 2] == 0x00, raw[offset + 3] == 0xE0 else {
                if raw[offset..<(offset + 4)].elementsEqual([0xFE, 0xFF, 0xDD, 0xE0]) { break }
                throw DICOMJSONError("encapsulated Pixel Data holds a non-Item at \(offset)")
            }
            let length = Int(raw[(offset + 4)..<(offset + 8)].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
            guard offset + 8 + length <= raw.count else { throw DICOMJSONError("encapsulated Pixel Data is truncated") }
            let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
            item.data = Data(raw[(offset + 8)..<(offset + 8 + length)])
            item.length = length
            sequence.items.append(item)
            offset += 8 + length
        }
        return sequence
    }
}
