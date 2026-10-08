import Foundation

/// A DIMSE command set (PS3.7 6.3, Annex E), always encoded in Implicit VR
/// Little Endian.
public struct DICOMCommand: Equatable, Sendable {
    /// Command Field values (PS3.7 E.1-1 and 9.3, 10.3).
    public struct Field: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }

        public static let cStoreRequest = Self(rawValue: 0x0001)
        public static let cStoreResponse = Self(rawValue: 0x8001)
        public static let cGetRequest = Self(rawValue: 0x0010)
        public static let cGetResponse = Self(rawValue: 0x8010)
        public static let cFindRequest = Self(rawValue: 0x0020)
        public static let cFindResponse = Self(rawValue: 0x8020)
        public static let cMoveRequest = Self(rawValue: 0x0021)
        public static let cMoveResponse = Self(rawValue: 0x8021)
        public static let cEchoRequest = Self(rawValue: 0x0030)
        public static let cEchoResponse = Self(rawValue: 0x8030)
        public static let nEventReportRequest = Self(rawValue: 0x0100)
        public static let nEventReportResponse = Self(rawValue: 0x8100)
        public static let nGetRequest = Self(rawValue: 0x0110)
        public static let nGetResponse = Self(rawValue: 0x8110)
        public static let nSetRequest = Self(rawValue: 0x0120)
        public static let nSetResponse = Self(rawValue: 0x8120)
        public static let nActionRequest = Self(rawValue: 0x0130)
        public static let nActionResponse = Self(rawValue: 0x8130)
        public static let nCreateRequest = Self(rawValue: 0x0140)
        public static let nCreateResponse = Self(rawValue: 0x8140)
        public static let nDeleteRequest = Self(rawValue: 0x0150)
        public static let nDeleteResponse = Self(rawValue: 0x8150)
        public static let cCancelRequest = Self(rawValue: 0x0FFF)

        public var isResponse: Bool { rawValue & 0x8000 != 0 }
        /// The response to this request.
        public var response: Field { Self(rawValue: rawValue | 0x8000) }

        public var description: String {
            let names: [UInt16: String] = [
                0x0001: "C-STORE-RQ", 0x8001: "C-STORE-RSP", 0x0010: "C-GET-RQ", 0x8010: "C-GET-RSP",
                0x0020: "C-FIND-RQ", 0x8020: "C-FIND-RSP", 0x0021: "C-MOVE-RQ", 0x8021: "C-MOVE-RSP",
                0x0030: "C-ECHO-RQ", 0x8030: "C-ECHO-RSP", 0x0100: "N-EVENT-REPORT-RQ", 0x8100: "N-EVENT-REPORT-RSP",
                0x0110: "N-GET-RQ", 0x8110: "N-GET-RSP", 0x0120: "N-SET-RQ", 0x8120: "N-SET-RSP",
                0x0130: "N-ACTION-RQ", 0x8130: "N-ACTION-RSP", 0x0140: "N-CREATE-RQ", 0x8140: "N-CREATE-RSP",
                0x0150: "N-DELETE-RQ", 0x8150: "N-DELETE-RSP", 0x0FFF: "C-CANCEL-RQ",
            ]
            return names[rawValue] ?? String(format: "command 0x%04X", rawValue)
        }
    }

    /// Priority (PS3.7 9.1.1.1.5).
    public enum Priority: UInt16, Sendable {
        case medium = 0
        case high = 1
        case low = 2
    }

    public var field: Field
    public var messageID: UInt16?
    public var messageIDBeingRespondedTo: UInt16?
    public var affectedSOPClassUID: String?
    public var requestedSOPClassUID: String?
    public var affectedSOPInstanceUID: String?
    public var requestedSOPInstanceUID: String?
    public var priority: UInt16?
    /// A data set follows the command (Command Data Set Type other than
    /// 0101H).
    public var hasDataSet: Bool
    public var status: UInt16?
    public var moveDestination: String?
    public var moveOriginatorAETitle: String?
    public var moveOriginatorMessageID: UInt16?
    public var remainingSuboperations: UInt16?
    public var completedSuboperations: UInt16?
    public var failedSuboperations: UInt16?
    public var warningSuboperations: UInt16?
    /// Offending Element: data element tags (group << 16 | element).
    public var offendingElements: [UInt32]?
    public var errorComment: String?
    public var errorID: UInt16?
    public var eventTypeID: UInt16?
    public var actionTypeID: UInt16?
    public var attributeIdentifierList: [UInt32]?
    /// Other command elements (retired or unknown), as encoded values.
    public var otherElements: [UInt32: [UInt8]]

    public init(field: Field, hasDataSet: Bool = false) {
        self.field = field
        self.hasDataSet = hasDataSet
        otherElements = [:]
    }

    /// The status of a response.
    public var statusValue: DICOMStatus? { status.map(DICOMStatus.init(code:)) }
}

/// A malformed command set.
public struct DICOMCommandError: Error, Equatable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) { self.message = message }

    public var description: String { "DIMSE command error: \(message)" }
}

extension DICOMCommand {
    private enum Kind { case ul, us, ui, ae, lo, at }

    /// The command elements this type models (PS3.7 E.1-1).
    private static let elements: [(UInt16, Kind)] = [
        (0x0002, .ui), (0x0003, .ui), (0x0100, .us), (0x0110, .us), (0x0120, .us), (0x0600, .ae), (0x0700, .us),
        (0x0800, .us), (0x0900, .us), (0x0901, .at), (0x0902, .lo), (0x0903, .us), (0x1000, .ui), (0x1001, .ui),
        (0x1002, .us), (0x1005, .at), (0x1008, .us), (0x1020, .us), (0x1021, .us), (0x1022, .us), (0x1023, .us),
        (0x1030, .ae), (0x1031, .us),
    ]
    private static let kinds = Dictionary(uniqueKeysWithValues: elements)

    /// The Implicit VR Little Endian encoding, Command Group Length first.
    public func encoded() throws -> Data {
        var body = Data()
        func element(_ number: UInt16, _ value: [UInt8]) {
            body.append(contentsOf: [0, 0, UInt8(number & 0xFF), UInt8(number >> 8)])
            body.append(contentsOf: withUnsafeBytes(of: UInt32(value.count).littleEndian, Array.init))
            body.append(contentsOf: value)
        }
        func us(_ value: UInt16) -> [UInt8] { withUnsafeBytes(of: value.littleEndian, Array.init) }
        func text(_ value: String, pad: UInt8) throws -> [UInt8] {
            var bytes = Array(value.utf8)
            guard bytes.count <= 0xFFFE else { throw DICOMCommandError("value too long") }
            if bytes.count % 2 == 1 { bytes.append(pad) }
            return bytes
        }
        func tags(_ values: [UInt32]) -> [UInt8] {
            values.flatMap { us(UInt16($0 >> 16)) + us(UInt16($0 & 0xFFFF)) }
        }

        var values: [UInt16: [UInt8]] = [:]
        func set(_ number: UInt16, _ value: [UInt8]?) { if let value { values[number] = value } }
        func uid(_ value: String?) throws -> [UInt8]? {
            guard let value else { return nil }
            guard DICOMUniqueIdentifier.isValid(value) else { throw DICOMCommandError("invalid UID \"\(value)\"") }
            return try text(value, pad: 0)
        }
        func ae(_ value: String?) throws -> [UInt8]? {
            guard let value else { return nil }
            guard DICOMApplicationEntityTitle.isValid(value) else { throw DICOMCommandError("invalid AE title \"\(value)\"") }
            return try text(value, pad: 0x20)
        }
        set(0x0002, try uid(affectedSOPClassUID))
        set(0x0003, try uid(requestedSOPClassUID))
        set(0x0100, us(field.rawValue))
        set(0x0110, messageID.map(us))
        set(0x0120, messageIDBeingRespondedTo.map(us))
        set(0x0600, try ae(moveDestination))
        set(0x0700, priority.map(us))
        set(0x0800, us(hasDataSet ? 0x0001 : 0x0101))
        set(0x0900, status.map(us))
        set(0x0901, offendingElements.map(tags))
        set(0x0902, try errorComment.map { try text($0, pad: 0x20) })
        set(0x0903, errorID.map(us))
        set(0x1000, try uid(affectedSOPInstanceUID))
        set(0x1001, try uid(requestedSOPInstanceUID))
        set(0x1002, eventTypeID.map(us))
        set(0x1005, attributeIdentifierList.map(tags))
        set(0x1008, actionTypeID.map(us))
        set(0x1020, remainingSuboperations.map(us))
        set(0x1021, completedSuboperations.map(us))
        set(0x1022, failedSuboperations.map(us))
        set(0x1023, warningSuboperations.map(us))
        set(0x1030, try ae(moveOriginatorAETitle))
        set(0x1031, moveOriginatorMessageID.map(us))
        for (tag, value) in otherElements where tag >> 16 == 0 && tag & 0xFFFF != 0 && Self.kinds[UInt16(tag)] == nil {
            values[UInt16(tag & 0xFFFF)] = value
        }
        for number in values.keys.sorted() { element(number, values[number]!) }

        var data = Data([0, 0, 0, 0, 4, 0, 0, 0])
        data.append(contentsOf: withUnsafeBytes(of: UInt32(body.count).littleEndian, Array.init))
        data.append(body)
        return data
    }

    /// Decodes a command set; `maximumLength` bounds the encoding.
    public init(encoded data: Data, maximumLength: Int = 1 << 16) throws {
        guard data.count <= maximumLength else { throw DICOMCommandError("command set of \(data.count) bytes") }
        let bytes = [UInt8](data)
        var values: [UInt16: [UInt8]] = [:]
        var position = 0
        while position < bytes.count {
            guard position + 8 <= bytes.count else { throw DICOMCommandError("truncated element") }
            let group = UInt16(bytes[position]) | UInt16(bytes[position + 1]) << 8
            let number = UInt16(bytes[position + 2]) | UInt16(bytes[position + 3]) << 8
            let length = Int(bytes[(position + 4)..<(position + 8)].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
            position += 8
            guard group == 0 else { throw DICOMCommandError(String(format: "element (%04X,%04X) outside group 0000", group, number)) }
            guard length <= bytes.count - position else { throw DICOMCommandError("element length \(length) overruns") }
            guard values[number] == nil else { throw DICOMCommandError(String(format: "repeated element (0000,%04X)", number)) }
            values[number] = Array(bytes[position..<(position + length)])
            position += length
        }

        func us(_ number: UInt16) throws -> UInt16? {
            guard let value = values[number] else { return nil }
            guard value.count == 2 else { throw DICOMCommandError(String(format: "(0000,%04X) is not US", number)) }
            return UInt16(value[0]) | UInt16(value[1]) << 8
        }
        func text(_ number: UInt16) -> String? {
            guard let value = values[number] else { return nil }
            return String(decoding: value, as: UTF8.self).trimmingCharacters(in: [" ", "\0"])
        }
        func tags(_ number: UInt16) throws -> [UInt32]? {
            guard let value = values[number] else { return nil }
            guard value.count % 4 == 0 else { throw DICOMCommandError(String(format: "(0000,%04X) is not AT", number)) }
            return stride(from: 0, to: value.count, by: 4).map { index -> UInt32 in
                let group = UInt32(value[index]) | UInt32(value[index + 1]) << 8
                let element = UInt32(value[index + 2]) | UInt32(value[index + 3]) << 8
                return group << 16 | element
            }
        }

        guard let field = try us(0x0100) else { throw DICOMCommandError("no Command Field") }
        guard let dataSetType = try us(0x0800) else { throw DICOMCommandError("no Command Data Set Type") }
        self.init(field: Field(rawValue: field), hasDataSet: dataSetType != 0x0101)
        affectedSOPClassUID = text(0x0002)
        requestedSOPClassUID = text(0x0003)
        messageID = try us(0x0110)
        messageIDBeingRespondedTo = try us(0x0120)
        moveDestination = text(0x0600)
        priority = try us(0x0700)
        status = try us(0x0900)
        offendingElements = try tags(0x0901)
        errorComment = text(0x0902)
        errorID = try us(0x0903)
        affectedSOPInstanceUID = text(0x1000)
        requestedSOPInstanceUID = text(0x1001)
        eventTypeID = try us(0x1002)
        attributeIdentifierList = try tags(0x1005)
        actionTypeID = try us(0x1008)
        remainingSuboperations = try us(0x1020)
        completedSuboperations = try us(0x1021)
        failedSuboperations = try us(0x1022)
        warningSuboperations = try us(0x1023)
        moveOriginatorAETitle = text(0x1030)
        moveOriginatorMessageID = try us(0x1031)
        for (number, value) in values where number != 0 && Self.kinds[number] == nil {
            otherElements[UInt32(number)] = value
        }
    }
}
