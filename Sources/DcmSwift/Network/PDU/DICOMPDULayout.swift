//
//  DICOMPDULayout.swift
//  DcmSwift
//
//  Where each field of a PDU lies in its bytes, and what it holds, as
//  PS3.8 9.3 lays them out: for a hexadecimal view of the traffic.
//

/// A field of a PDU's bytes: a leaf (a type, a length, a value…) or an item
/// whose fields are its children.
public struct DICOMPDUField: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The type of the PDU, or of an item.
        case type
        /// Bytes the standard reserves.
        case reserved
        /// The length of the PDU, an item or a value.
        case length
        /// A value: an AE title, a UID, a parameter.
        case value
        /// An item, its header included: its fields are the children.
        case item
        /// The fragment of a presentation data value: command or data set bytes.
        case fragment
    }

    /// The name the standard gives the field: `Called-AE-title`, `Item-length`…
    public var name: String
    /// Its bytes, as offsets in the PDU, header included.
    public var range: Range<Int>
    public var kind: Kind
    /// What the field holds, for display: `"STORESCP"`, `1.2.840.10008.1.1`, `16384`…
    public var value: String?
    /// The fields of an item, in order.
    public var children: [DICOMPDUField]

    public init(name: String, range: Range<Int>, kind: Kind, value: String? = nil, children: [DICOMPDUField] = []) {
        self.name = name
        self.range = range
        self.kind = kind
        self.value = value
        self.children = children
    }

    /// The leaves of the field, in order: itself if it has no children.
    public var leaves: [DICOMPDUField] {
        children.isEmpty ? [self] : children.flatMap(\.leaves)
    }
}


/// The fields of a PDU's bytes (PS3.8 9.3).
///
/// The bytes may be the first ones of a PDU, or deviate from the standard:
/// the layout then stops where they end or stop making sense, and the bytes
/// after the last field are those it could not account for.
public enum DICOMPDULayout {
    /// The fields of a PDU, header included, in order.
    public static func fields<Bytes: Collection>(of bytes: Bytes) -> [DICOMPDUField] where Bytes.Element == UInt8 {
        var reader = Reader(bytes: Array(bytes))
        guard let type = reader.uint(1, "PDU-type", kind: .type, format: { pduName($0) }) else { return reader.fields }
        reader.reserved(1)
        guard let length = reader.uint(4, "PDU-length", kind: .length) else { return reader.fields }
        let end = min(reader.bytes.count, 6 + Int(length))
        switch type {
        case 0x01, 0x02:
            reader.uint(2, "Protocol-version", kind: .value, format: { "\($0)" })
            reader.reserved(2)
            reader.text(16, "Called-AE-title", quoted: true)
            reader.text(16, "Calling-AE-title", quoted: true)
            reader.reserved(32)
            while reader.position + 4 <= end {
                guard reader.item(end: end, content: { reader, type, end in associationItem(&reader, type: type, end: end) }) else { break }
            }
        case 0x03:
            reader.reserved(1)
            reader.uint(1, "Result", kind: .value, format: hex)
            reader.uint(1, "Source", kind: .value, format: hex)
            reader.uint(1, "Reason/Diag.", kind: .value, format: hex)
        case 0x04:
            while reader.position + 6 <= end {
                let start = reader.position
                var item = Reader(bytes: reader.bytes, position: start)
                guard let itemLength = item.uint(4, "Item-length", kind: .length) else { break }
                let itemEnd = min(end, start + 4 + Int(itemLength))
                let context = item.uint(1, "Presentation-context-ID", kind: .value, format: { "\($0)" })
                let header = item.uint(1, "Message Control Header", kind: .value, format: messageControlHeader)
                if item.position < itemEnd {
                    let name = (header ?? 0) & 0x01 == 1 ? "Command fragment" : "Data set fragment"
                    item.fields.append(DICOMPDUField(name: name, range: item.position..<itemEnd, kind: .fragment,
                                                     value: "\(itemEnd - item.position) bytes"))
                    item.position = itemEnd
                }
                reader.fields.append(DICOMPDUField(name: "Presentation-data-value Item", range: start..<item.position, kind: .item,
                                                   value: context.map { "context \($0)" }, children: item.fields))
                reader.position = item.position
                if item.position < start + 4 + Int(itemLength) { break }
            }
        case 0x05, 0x06:
            reader.reserved(4)
        case 0x07:
            reader.reserved(1)
            reader.reserved(1)
            reader.uint(1, "Source", kind: .value, format: hex)
            reader.uint(1, "Reason/Diag.", kind: .value, format: hex)
        default:
            break
        }
        return reader.fields
    }

    /// The name of a PDU type (PS3.8 Table 9-11 and following).
    public static func pduName(_ type: UInt64) -> String {
        let names: [UInt64: String] = [0x01: "A-ASSOCIATE-RQ", 0x02: "A-ASSOCIATE-AC", 0x03: "A-ASSOCIATE-RJ",
                                       0x04: "P-DATA-TF", 0x05: "A-RELEASE-RQ", 0x06: "A-RELEASE-RP", 0x07: "A-ABORT"]
        return hex(type) + (names[type].map { " " + $0 } ?? "")
    }

    // MARK: - Items of an association

    private static let itemNames: [UInt8: String] = [
        0x10: "Application Context Item", 0x20: "Presentation Context Item", 0x21: "Presentation Context Item",
        0x30: "Abstract Syntax Sub-item", 0x40: "Transfer Syntax Sub-item", 0x50: "User Information Item",
        0x51: "Maximum Length Sub-item", 0x52: "Implementation Class UID Sub-item",
        0x53: "Asynchronous Operations Window Sub-item", 0x54: "SCP/SCU Role Selection Sub-item",
        0x55: "Implementation Version Name Sub-item", 0x56: "SOP Class Extended Negotiation Sub-item",
        0x57: "SOP Class Common Extended Negotiation Sub-item", 0x58: "User Identity Sub-item",
        0x59: "User Identity Sub-item",
    ]

    static func itemName(_ type: UInt8) -> String { itemNames[type] ?? "Unknown Item" }

    /// The content of an item of an A-ASSOCIATE-RQ or -AC, after its header.
    private static func associationItem(_ reader: inout Reader, type: UInt8, end: Int) {
        switch type {
        case 0x10:
            reader.text(end - reader.position, "Application-context-name")
        case 0x20, 0x21:
            reader.uint(1, "Presentation-context-ID", kind: .value, format: { "\($0)" })
            reader.reserved(1)
            if type == 0x21 { reader.uint(1, "Result/Reason", kind: .value, format: hex) } else { reader.reserved(1) }
            reader.reserved(1)
            while reader.position + 4 <= end {
                guard reader.item(end: end, content: { reader, _, end in reader.text(end - reader.position, "Syntax-name") }) else { break }
            }
        case 0x50:
            while reader.position + 4 <= end {
                guard reader.item(end: end, content: { reader, type, end in userInformationItem(&reader, type: type, end: end) }) else { break }
            }
        default:
            reader.value(end - reader.position, "Item value")
        }
    }

    /// The content of a sub-item of the User Information Item (PS3.7 D.3.3).
    private static func userInformationItem(_ reader: inout Reader, type: UInt8, end: Int) {
        switch type {
        case 0x51:
            reader.uint(4, "Maximum-length-received", kind: .value, format: { "\($0)" })
        case 0x52:
            reader.text(end - reader.position, "Implementation-class-uid")
        case 0x53:
            reader.uint(2, "Maximum-number-operations-invoked", kind: .value, format: { "\($0)" })
            reader.uint(2, "Maximum-number-operations-performed", kind: .value, format: { "\($0)" })
        case 0x54:
            if let length = reader.uint(2, "UID-length", kind: .length) { reader.text(Int(length), "SOP-class-uid") }
            reader.uint(1, "SCU-role", kind: .value, format: { "\($0)" })
            reader.uint(1, "SCP-role", kind: .value, format: { "\($0)" })
        case 0x55:
            reader.text(end - reader.position, "Implementation-version-name", quoted: true)
        case 0x56:
            if let length = reader.uint(2, "SOP-class-uid-length", kind: .length) { reader.text(Int(length), "SOP-class-uid") }
            reader.value(end - reader.position, "Service-class-application-information")
        case 0x57:
            if let length = reader.uint(2, "SOP-class-uid-length", kind: .length) { reader.text(Int(length), "SOP-class-uid") }
            if let length = reader.uint(2, "Service-class-uid-length", kind: .length) { reader.text(Int(length), "Service-class-uid") }
            if let length = reader.uint(2, "Related-general-sop-class-identification-length", kind: .length) {
                let listEnd = min(end, reader.position + Int(length))
                while reader.position + 2 <= listEnd {
                    guard let uidLength = reader.uint(2, "Related-general-sop-class-uid-length", kind: .length) else { break }
                    reader.text(Int(uidLength), "Related-general-sop-class-uid")
                }
            }
        case 0x58:
            reader.uint(1, "User-Identity-Type", kind: .value, format: { "\($0)" })
            reader.uint(1, "Positive-response-requested", kind: .value, format: { "\($0)" })
            if let length = reader.uint(2, "Primary-field-length", kind: .length) { reader.value(Int(length), "Primary-field") }
            // The secondary field is a passcode: its bytes are in the PDU, its value is not repeated.
            if let length = reader.uint(2, "Secondary-field-length", kind: .length) {
                reader.value(Int(length), "Secondary-field", describe: { "\($0.count) bytes" })
            }
        case 0x59:
            if let length = reader.uint(2, "Server-response-length", kind: .length) { reader.value(Int(length), "Server-response") }
        default:
            break
        }
        if reader.position < end { reader.value(end - reader.position, "Item value") }
    }

    // MARK: - Formats

    static func hex(_ value: UInt64) -> String {
        let text = String(value, radix: 16, uppercase: true)
        return (text.count % 2 == 1 ? "0" + text : text) + "H"
    }

    static func messageControlHeader(_ value: UInt64) -> String {
        let kind = value & 0x01 == 1 ? "command" : "data set"
        let last = value & 0x02 == 2 ? "last fragment" : "not last"
        return "\(hex(value)) \(kind), \(last)"
    }

    // MARK: - Reader

    /// Reads fields in order, and stops at the end of the bytes.
    struct Reader {
        let bytes: [UInt8]
        var position = 0
        var fields: [DICOMPDUField] = []

        init(bytes: [UInt8], position: Int = 0) {
            self.bytes = bytes
            self.position = position
        }

        /// A big-endian unsigned integer, or nil past the end of the bytes.
        @discardableResult
        mutating func uint(_ count: Int, _ name: String, kind: DICOMPDUField.Kind, format: ((UInt64) -> String)? = nil) -> UInt64? {
            guard position + count <= bytes.count else { return nil }
            let value = bytes[position..<position + count].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            fields.append(DICOMPDUField(name: name, range: position..<position + count, kind: kind,
                                        value: format.map { $0(value) } ?? "\(value)"))
            position += count
            return value
        }

        mutating func reserved(_ count: Int) {
            let end = min(bytes.count, position + count)
            guard position < end else { return }
            fields.append(DICOMPDUField(name: "Reserved", range: position..<end, kind: .reserved))
            position = end
        }

        /// Text of a fixed length: an AE title, a UID, a name; trailing spaces and NULs dropped.
        mutating func text(_ count: Int, _ name: String, quoted: Bool = false) {
            value(count, name) { bytes in
                let text = String(decoding: bytes, as: UTF8.self)
                let trimmed = String(text.reversed().drop(while: { $0 == " " || $0 == "\0" }).reversed())
                return quoted ? "\"\(trimmed)\"" : trimmed
            }
        }

        /// Bytes of a value, those that are there.
        mutating func value(_ count: Int, _ name: String, describe: (([UInt8]) -> String)? = nil) {
            let end = min(bytes.count, position + max(0, count))
            guard position < end else { return }
            let slice = Array(bytes[position..<end])
            let text = describe?(slice) ?? slice.map { DICOMPDULayout.hex(UInt64($0)).dropLast() }.joined(separator: " ")
            fields.append(DICOMPDUField(name: name, range: position..<end, kind: .value, value: text))
            position = end
        }

        /// An item: its header, then its content read by `content` up to its
        /// end. False when its header or its length runs past `end`.
        mutating func item(end: Int, content: (inout Reader, UInt8, Int) -> Void) -> Bool {
            let start = position
            var item = Reader(bytes: bytes, position: start)
            guard let type = item.uint(1, "Item-type", kind: .type, format: { DICOMPDULayout.hex($0) }) else { return false }
            item.reserved(1)
            guard let length = item.uint(2, "Item-length", kind: .length) else { return false }
            let declaredEnd = item.position + Int(length)
            let itemEnd = min(end, declaredEnd)
            content(&item, UInt8(type), itemEnd)
            fields.append(DICOMPDUField(name: DICOMPDULayout.itemName(UInt8(type)), range: start..<item.position, kind: .item,
                                        value: item.fields.first(where: { $0.name.hasSuffix("uid") || $0.name.hasSuffix("name") || $0.name == "Presentation-context-ID" })?.value,
                                        children: item.fields))
            position = item.position
            return declaredEnd <= end
        }
    }
}
