import Foundation
import NIOCore

/// A malformed or unexpected PDU, with the A-ABORT reason that answers it
/// (PS3.8 9.3.8).
public struct DICOMPDUError: Error, Equatable, CustomStringConvertible {
    public let reason: DICOMAbort.Reason
    public let message: String

    public init(_ reason: DICOMAbort.Reason, _ message: String) {
        self.reason = reason
        self.message = message
    }

    public var description: String { "DICOM PDU error (\(reason)): \(message)" }

    static func invalid(_ message: String) -> Self { .init(.invalidPDUParameterValue, message) }
}

/// Encodes and decodes PDUs (PS3.8 9.3). Decoding is strict about lengths
/// and tolerant where PS3.8 says reserved fields shall not be tested.
public enum DICOMPDUCodec {
    /// The PDU header: type, reserved byte, and 32-bit length.
    public static let headerLength = 6

    // MARK: Encoding

    public static func encode(_ pdu: DICOMPDU) throws -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: 256)
        try encode(pdu, into: &buffer)
        return buffer
    }

    public static func encode(_ pdu: DICOMPDU, into buffer: inout ByteBuffer) throws {
        buffer.writeInteger(pdu.type)
        buffer.writeInteger(UInt8(0))
        let lengthIndex = buffer.writerIndex
        buffer.writeInteger(UInt32(0))
        let start = buffer.writerIndex

        switch pdu {
        case .associateRequest(let request):
            guard !request.presentationContexts.isEmpty else {
                throw DICOMPDUError.invalid("A-ASSOCIATE-RQ without presentation context")
            }
            try writeAssociateHeader(
                version: request.protocolVersion, called: request.calledAETitle, calling: request.callingAETitle,
                into: &buffer)
            try writeItem(0x10, into: &buffer) { try writeUID(request.applicationContextName, into: &$0) }
            for context in request.presentationContexts {
                try writeItem(0x20, into: &buffer) { body in
                    body.writeInteger(context.id)
                    body.writeBytes([0, 0, 0])
                    try writeItem(0x30, into: &body) { try writeUID(context.abstractSyntax, into: &$0) }
                    guard !context.transferSyntaxes.isEmpty else {
                        throw DICOMPDUError.invalid("presentation context \(context.id) proposes no transfer syntax")
                    }
                    for syntax in context.transferSyntaxes {
                        try writeItem(0x40, into: &body) { try writeUID(syntax, into: &$0) }
                    }
                }
            }
            try writeUserInformation(request.userInformation, into: &buffer)

        case .associateAccept(let accept):
            // The AE title fields are reserved in the A-ASSOCIATE-AC and are
            // returned as received (PS3.8 Table 9-17).
            buffer.writeInteger(accept.protocolVersion)
            buffer.writeInteger(UInt16(0))
            writeAETitleField(accept.calledAETitle, into: &buffer)
            writeAETitleField(accept.callingAETitle, into: &buffer)
            buffer.writeRepeatingByte(0, count: 32)
            try writeItem(0x10, into: &buffer) { try writeUID(accept.applicationContextName, into: &$0) }
            for context in accept.presentationContexts {
                try writeItem(0x21, into: &buffer) { body in
                    body.writeInteger(context.id)
                    body.writeInteger(UInt8(0))
                    body.writeInteger(context.result.rawValue)
                    body.writeInteger(UInt8(0))
                    try writeItem(0x40, into: &body) { try writeUID(context.transferSyntax, into: &$0, allowEmpty: true) }
                }
            }
            try writeUserInformation(accept.userInformation, into: &buffer)

        case .associateReject(let reject):
            buffer.writeBytes([0, reject.result.rawValue, reject.reason.source, reject.reason.reason])

        case .data(let values):
            guard !values.isEmpty else { throw DICOMPDUError.invalid("P-DATA-TF without PDV") }
            for value in values {
                guard value.data.readableBytes <= Int(UInt32.max) - 2 else {
                    throw DICOMPDUError.invalid("PDV too long")
                }
                buffer.writeInteger(UInt32(value.data.readableBytes + 2))
                buffer.writeInteger(value.presentationContextID)
                buffer.writeInteger(UInt8((value.isCommand ? 1 : 0) | (value.isLast ? 2 : 0)))
                var data = value.data
                buffer.writeBuffer(&data)
            }

        case .releaseRequest, .releaseResponse:
            buffer.writeInteger(UInt32(0))

        case .abort(let abort):
            buffer.writeBytes([0, 0, abort.source.rawValue, abort.source == .serviceProvider ? abort.reason.rawValue : 0])
        }

        let length = buffer.writerIndex - start
        guard length <= Int(UInt32.max) else { throw DICOMPDUError.invalid("PDU too long") }
        buffer.setInteger(UInt32(length), at: lengthIndex)
    }

    private static func writeAssociateHeader(
        version: UInt16, called: String, calling: String, into buffer: inout ByteBuffer
    ) throws {
        buffer.writeInteger(version)
        buffer.writeInteger(UInt16(0))
        try writeAETitle(called, into: &buffer)
        try writeAETitle(calling, into: &buffer)
        buffer.writeRepeatingByte(0, count: 32)
    }

    /// A 16-byte AE title field, space padded (PS3.5 6.2 AE).
    static func writeAETitle(_ title: String, into buffer: inout ByteBuffer) throws {
        guard DICOMApplicationEntityTitle.isValid(title) else {
            throw DICOMPDUError.invalid("invalid AE title \"\(title)\"")
        }
        writeAETitleField(title, into: &buffer)
    }

    private static func writeAETitleField(_ title: String, into buffer: inout ByteBuffer) {
        let bytes = Array(title.utf8.prefix(16))
        buffer.writeBytes(bytes)
        buffer.writeRepeatingByte(0x20, count: 16 - bytes.count)
    }

    private static func writeUID(_ uid: String, into buffer: inout ByteBuffer, allowEmpty: Bool = false) throws {
        guard (allowEmpty && uid.isEmpty) || DICOMUniqueIdentifier.isValid(uid) else {
            throw DICOMPDUError.invalid("invalid UID \"\(uid)\"")
        }
        buffer.writeString(uid)
    }

    /// An item: type, reserved byte, 16-bit length, then the body.
    private static func writeItem(
        _ type: UInt8, into buffer: inout ByteBuffer, _ body: (inout ByteBuffer) throws -> Void
    ) throws {
        buffer.writeInteger(type)
        buffer.writeInteger(UInt8(0))
        let lengthIndex = buffer.writerIndex
        buffer.writeInteger(UInt16(0))
        let start = buffer.writerIndex
        try body(&buffer)
        let length = buffer.writerIndex - start
        guard length <= Int(UInt16.max) else { throw DICOMPDUError.invalid("item 0x\(String(type, radix: 16)) too long") }
        buffer.setInteger(UInt16(length), at: lengthIndex)
    }

    private static func writeUserInformation(_ info: DICOMUserInformation, into buffer: inout ByteBuffer) throws {
        try writeItem(0x50, into: &buffer) { body in
            if let length = info.maximumLength {
                try writeItem(0x51, into: &body) { $0.writeInteger(length) }
            }
            if let uid = info.implementationClassUID {
                try writeItem(0x52, into: &body) { try writeUID(uid, into: &$0) }
            }
            if let window = info.asynchronousOperationsWindow {
                try writeItem(0x53, into: &body) {
                    $0.writeInteger(window.maximumInvoked)
                    $0.writeInteger(window.maximumPerformed)
                }
            }
            for role in info.roleSelections {
                try writeItem(0x54, into: &body) {
                    try writeLengthPrefixedUID(role.sopClassUID, into: &$0)
                    $0.writeInteger(UInt8(role.scuRole ? 1 : 0))
                    $0.writeInteger(UInt8(role.scpRole ? 1 : 0))
                }
            }
            if let name = info.implementationVersionName {
                let bytes = Array(name.utf8)
                guard (1...16).contains(bytes.count) else {
                    throw DICOMPDUError.invalid("implementation version name of \(bytes.count) bytes")
                }
                try writeItem(0x55, into: &body) { $0.writeBytes(bytes) }
            }
            for negotiation in info.extendedNegotiations {
                try writeItem(0x56, into: &body) {
                    try writeLengthPrefixedUID(negotiation.sopClassUID, into: &$0)
                    $0.writeBytes(negotiation.applicationInformation)
                }
            }
            for negotiation in info.commonExtendedNegotiations {
                try writeItem(0x57, into: &body) { item in
                    try writeLengthPrefixedUID(negotiation.sopClassUID, into: &item)
                    try writeLengthPrefixedUID(negotiation.serviceClassUID, into: &item)
                    var related = ByteBufferAllocator().buffer(capacity: 64)
                    for uid in negotiation.relatedGeneralSOPClassUIDs {
                        try writeLengthPrefixedUID(uid, into: &related)
                    }
                    guard related.readableBytes <= Int(UInt16.max) else {
                        throw DICOMPDUError.invalid("too many related general SOP classes")
                    }
                    item.writeInteger(UInt16(related.readableBytes))
                    item.writeBuffer(&related)
                }
            }
            if let identity = info.userIdentity {
                try writeItem(0x58, into: &body) {
                    $0.writeInteger(identity.kind.rawValue)
                    $0.writeInteger(UInt8(identity.positiveResponseRequested ? 1 : 0))
                    try writeLengthPrefixed(identity.primaryField, into: &$0)
                    try writeLengthPrefixed(identity.kind == .usernameAndPasscode ? identity.secondaryField : [], into: &$0)
                }
            }
            if let response = info.userIdentityServerResponse {
                try writeItem(0x59, into: &body) { try writeLengthPrefixed(response, into: &$0) }
            }
            for item in info.unknownSubItems {
                try writeItem(item.type, into: &body) { $0.writeBytes(item.value) }
            }
        }
    }

    private static func writeLengthPrefixedUID(_ uid: String, into buffer: inout ByteBuffer) throws {
        guard DICOMUniqueIdentifier.isValid(uid) else { throw DICOMPDUError.invalid("invalid UID \"\(uid)\"") }
        try writeLengthPrefixed(Array(uid.utf8), into: &buffer)
    }

    private static func writeLengthPrefixed(_ bytes: [UInt8], into buffer: inout ByteBuffer) throws {
        guard bytes.count <= Int(UInt16.max) else { throw DICOMPDUError.invalid("field of \(bytes.count) bytes") }
        buffer.writeInteger(UInt16(bytes.count))
        buffer.writeBytes(bytes)
    }

    // MARK: Decoding

    /// Decodes the body of a PDU of the given type (the bytes after the
    /// 6-byte header).
    public static func decode(type: UInt8, body: ByteBuffer) throws -> DICOMPDU {
        var body = body
        switch type {
        case 0x01:
            let header = try readAssociateHeader(&body)
            var applicationContext: String?
            var contexts: [DICOMPresentationContextProposal] = []
            var userInformation: DICOMUserInformation?
            while body.readableBytes > 0 {
                let (itemType, item) = try readItem(&body)
                switch itemType {
                case 0x10:
                    guard applicationContext == nil else { throw DICOMPDUError(.unexpectedPDUParameter, "two application contexts") }
                    applicationContext = try readUID(item)
                case 0x20: contexts.append(try readProposal(item))
                case 0x50:
                    guard userInformation == nil else { throw DICOMPDUError(.unexpectedPDUParameter, "two user information items") }
                    userInformation = try readUserInformation(item)
                default:
                    throw DICOMPDUError(.unrecognizedPDUParameter, "item type 0x\(String(itemType, radix: 16)) in A-ASSOCIATE-RQ")
                }
            }
            guard let applicationContext else { throw DICOMPDUError.invalid("A-ASSOCIATE-RQ without application context") }
            guard !contexts.isEmpty else { throw DICOMPDUError.invalid("A-ASSOCIATE-RQ without presentation context") }
            guard let userInformation else { throw DICOMPDUError.invalid("A-ASSOCIATE-RQ without user information") }
            return .associateRequest(DICOMAssociateRequest(
                calledAETitle: header.called, callingAETitle: header.calling, presentationContexts: contexts,
                userInformation: userInformation, applicationContextName: applicationContext,
                protocolVersion: header.version))

        case 0x02:
            let header = try readAssociateHeader(&body)
            var applicationContext: String?
            var contexts: [DICOMPresentationContextResult] = []
            var userInformation: DICOMUserInformation?
            while body.readableBytes > 0 {
                let (itemType, item) = try readItem(&body)
                switch itemType {
                case 0x10:
                    guard applicationContext == nil else { throw DICOMPDUError(.unexpectedPDUParameter, "two application contexts") }
                    applicationContext = try readUID(item)
                case 0x21: contexts.append(try readResult(item))
                case 0x50:
                    guard userInformation == nil else { throw DICOMPDUError(.unexpectedPDUParameter, "two user information items") }
                    userInformation = try readUserInformation(item)
                default:
                    throw DICOMPDUError(.unrecognizedPDUParameter, "item type 0x\(String(itemType, radix: 16)) in A-ASSOCIATE-AC")
                }
            }
            guard let applicationContext else { throw DICOMPDUError.invalid("A-ASSOCIATE-AC without application context") }
            guard let userInformation else { throw DICOMPDUError.invalid("A-ASSOCIATE-AC without user information") }
            return .associateAccept(DICOMAssociateAccept(
                calledAETitle: header.called, callingAETitle: header.calling, presentationContexts: contexts,
                userInformation: userInformation, applicationContextName: applicationContext,
                protocolVersion: header.version))

        case 0x03:
            guard body.readableBytes == 4, let bytes = body.readBytes(length: 4) else {
                throw DICOMPDUError.invalid("A-ASSOCIATE-RJ of \(body.readableBytes) bytes")
            }
            guard let result = DICOMAssociateReject.Result(rawValue: bytes[1]) else {
                throw DICOMPDUError.invalid("A-ASSOCIATE-RJ result \(bytes[1])")
            }
            return .associateReject(DICOMAssociateReject(
                result: result, reason: DICOMAssociateReject.Reason(source: bytes[2], reason: bytes[3])))

        case 0x04:
            var values: [DICOMPresentationDataValue] = []
            while body.readableBytes > 0 {
                guard let length = body.readInteger(as: UInt32.self), length >= 2, Int(length) <= body.readableBytes,
                      let id = body.readInteger(as: UInt8.self), let control = body.readInteger(as: UInt8.self),
                      let data = body.readSlice(length: Int(length) - 2) else {
                    throw DICOMPDUError.invalid("malformed PDV item")
                }
                values.append(DICOMPresentationDataValue(
                    presentationContextID: id, isCommand: control & 1 != 0, isLast: control & 2 != 0, data: data))
            }
            guard !values.isEmpty else { throw DICOMPDUError.invalid("P-DATA-TF without PDV") }
            return .data(values)

        case 0x05, 0x06:
            guard body.readableBytes == 4 else {
                throw DICOMPDUError.invalid("A-RELEASE PDU of \(body.readableBytes) bytes")
            }
            return type == 0x05 ? .releaseRequest : .releaseResponse

        case 0x07:
            guard body.readableBytes == 4, let bytes = body.readBytes(length: 4) else {
                throw DICOMPDUError.invalid("A-ABORT of \(body.readableBytes) bytes")
            }
            let source = DICOMAbort.Source(rawValue: bytes[2]) ?? .serviceProvider
            let reason = source == .serviceProvider ? (DICOMAbort.Reason(rawValue: bytes[3]) ?? .notSpecified) : .notSpecified
            return .abort(DICOMAbort(source: source, reason: reason))

        default:
            throw DICOMPDUError(.unrecognizedPDU, "PDU type 0x\(String(type, radix: 16))")
        }
    }

    private static func readAssociateHeader(_ body: inout ByteBuffer) throws -> (version: UInt16, called: String, calling: String) {
        guard let version = body.readInteger(as: UInt16.self), body.readSlice(length: 2) != nil,
              let called = body.readBytes(length: 16), let calling = body.readBytes(length: 16),
              body.readSlice(length: 32) != nil else {
            throw DICOMPDUError.invalid("truncated A-ASSOCIATE header")
        }
        return (version, DICOMApplicationEntityTitle.decode(called), DICOMApplicationEntityTitle.decode(calling))
    }

    private static func readItem(_ buffer: inout ByteBuffer) throws -> (UInt8, ByteBuffer) {
        guard let type = buffer.readInteger(as: UInt8.self), buffer.readInteger(as: UInt8.self) != nil,
              let length = buffer.readInteger(as: UInt16.self), let item = buffer.readSlice(length: Int(length)) else {
            throw DICOMPDUError.invalid("truncated item")
        }
        return (type, item)
    }

    private static func readUID(_ item: ByteBuffer, allowEmpty: Bool = false) throws -> String {
        let bytes = Array(item.readableBytesView)
        let uid = String(decoding: bytes.reversed().drop { $0 == 0 || $0 == 0x20 }.reversed(), as: UTF8.self)
        guard (allowEmpty && uid.isEmpty) || DICOMUniqueIdentifier.isValid(uid) else {
            throw DICOMPDUError.invalid("invalid UID \"\(uid)\"")
        }
        return uid
    }

    private static func readProposal(_ item: ByteBuffer) throws -> DICOMPresentationContextProposal {
        var item = item
        guard let id = item.readInteger(as: UInt8.self), item.readSlice(length: 3) != nil else {
            throw DICOMPDUError.invalid("truncated presentation context")
        }
        var abstractSyntax: String?
        var transferSyntaxes: [String] = []
        while item.readableBytes > 0 {
            let (type, sub) = try readItem(&item)
            switch type {
            case 0x30:
                guard abstractSyntax == nil else { throw DICOMPDUError(.unexpectedPDUParameter, "two abstract syntaxes") }
                abstractSyntax = try readUID(sub)
            case 0x40: transferSyntaxes.append(try readUID(sub))
            default:
                throw DICOMPDUError(.unrecognizedPDUParameter, "sub-item 0x\(String(type, radix: 16)) in a presentation context")
            }
        }
        guard let abstractSyntax, !transferSyntaxes.isEmpty else {
            throw DICOMPDUError.invalid("presentation context \(id) lacks an abstract or transfer syntax")
        }
        return DICOMPresentationContextProposal(id: id, abstractSyntax: abstractSyntax, transferSyntaxes: transferSyntaxes)
    }

    private static func readResult(_ item: ByteBuffer) throws -> DICOMPresentationContextResult {
        var item = item
        guard let id = item.readInteger(as: UInt8.self), item.readInteger(as: UInt8.self) != nil,
              let resultValue = item.readInteger(as: UInt8.self), item.readInteger(as: UInt8.self) != nil else {
            throw DICOMPDUError.invalid("truncated presentation context result")
        }
        guard let result = DICOMPresentationContextResult.Result(rawValue: resultValue) else {
            throw DICOMPDUError.invalid("presentation context result \(resultValue)")
        }
        var transferSyntax: String?
        while item.readableBytes > 0 {
            let (type, sub) = try readItem(&item)
            guard type == 0x40, transferSyntax == nil else {
                throw DICOMPDUError(.unexpectedPDUParameter, "sub-item 0x\(String(type, radix: 16)) in a presentation context result")
            }
            // Not significant when the context is rejected.
            transferSyntax = result == .acceptance ? try readUID(sub) : ((try? readUID(sub, allowEmpty: true)) ?? "")
        }
        guard result != .acceptance || transferSyntax != nil else {
            throw DICOMPDUError.invalid("accepted presentation context \(id) without transfer syntax")
        }
        return DICOMPresentationContextResult(id: id, result: result, transferSyntax: transferSyntax ?? "")
    }

    private static func readLengthPrefixed(_ buffer: inout ByteBuffer) throws -> [UInt8] {
        guard let length = buffer.readInteger(as: UInt16.self), let bytes = buffer.readBytes(length: Int(length)) else {
            throw DICOMPDUError.invalid("truncated length-prefixed field")
        }
        return bytes
    }

    private static func readLengthPrefixedUID(_ buffer: inout ByteBuffer) throws -> String {
        try readUID(ByteBufferAllocator().buffer(bytes: try readLengthPrefixed(&buffer)))
    }

    private static func readUserInformation(_ item: ByteBuffer) throws -> DICOMUserInformation {
        var item = item
        var info = DICOMUserInformation()
        while item.readableBytes > 0 {
            let (type, sub) = try readItem(&item)
            var value = sub
            switch type {
            case 0x51:
                guard value.readableBytes == 4, let length = value.readInteger(as: UInt32.self) else {
                    throw DICOMPDUError.invalid("maximum length sub-item of \(sub.readableBytes) bytes")
                }
                info.maximumLength = length
            case 0x52:
                info.implementationClassUID = try readUID(sub)
            case 0x53:
                guard value.readableBytes == 4, let invoked = value.readInteger(as: UInt16.self),
                      let performed = value.readInteger(as: UInt16.self) else {
                    throw DICOMPDUError.invalid("asynchronous operations window of \(sub.readableBytes) bytes")
                }
                info.asynchronousOperationsWindow = DICOMAsynchronousOperationsWindow(
                    maximumInvoked: invoked, maximumPerformed: performed)
            case 0x54:
                let uid = try readLengthPrefixedUID(&value)
                guard value.readableBytes == 2, let scu = value.readInteger(as: UInt8.self),
                      let scp = value.readInteger(as: UInt8.self) else {
                    throw DICOMPDUError.invalid("malformed role selection")
                }
                info.roleSelections.append(DICOMRoleSelection(sopClassUID: uid, scuRole: scu == 1, scpRole: scp == 1))
            case 0x55:
                let bytes = Array(sub.readableBytesView)
                guard (1...16).contains(bytes.count) else {
                    throw DICOMPDUError.invalid("implementation version name of \(bytes.count) bytes")
                }
                info.implementationVersionName = String(decoding: bytes, as: UTF8.self)
                    .trimmingCharacters(in: [" ", "\0"])
            case 0x56:
                let uid = try readLengthPrefixedUID(&value)
                info.extendedNegotiations.append(DICOMExtendedNegotiation(
                    sopClassUID: uid, applicationInformation: Array(value.readableBytesView)))
            case 0x57:
                let uid = try readLengthPrefixedUID(&value)
                let serviceClass = try readLengthPrefixedUID(&value)
                guard let relatedLength = value.readInteger(as: UInt16.self),
                      var related = value.readSlice(length: Int(relatedLength)) else {
                    throw DICOMPDUError.invalid("malformed common extended negotiation")
                }
                var uids: [String] = []
                while related.readableBytes > 0 { uids.append(try readLengthPrefixedUID(&related)) }
                info.commonExtendedNegotiations.append(DICOMCommonExtendedNegotiation(
                    sopClassUID: uid, serviceClassUID: serviceClass, relatedGeneralSOPClassUIDs: uids))
            case 0x58:
                guard let kindValue = value.readInteger(as: UInt8.self), let positive = value.readInteger(as: UInt8.self) else {
                    throw DICOMPDUError.invalid("truncated user identity")
                }
                guard let kind = DICOMUserIdentity.Kind(rawValue: kindValue) else {
                    throw DICOMPDUError.invalid("user identity type \(kindValue)")
                }
                let primary = try readLengthPrefixed(&value)
                let secondary = try readLengthPrefixed(&value)
                info.userIdentity = DICOMUserIdentity(
                    kind: kind, positiveResponseRequested: positive == 1, primaryField: primary, secondaryField: secondary)
            case 0x59:
                info.userIdentityServerResponse = try readLengthPrefixed(&value)
            default:
                info.unknownSubItems.append(DICOMUnknownItem(type: type, value: Array(sub.readableBytesView)))
            }
        }
        return info
    }
}

/// AE title rules (PS3.5 6.2, VR AE).
public enum DICOMApplicationEntityTitle {
    /// 1 to 16 characters of the default repertoire without backslash or
    /// control characters, not only spaces.
    public static func isValid(_ title: String) -> Bool {
        let bytes = Array(title.utf8)
        return (1...16).contains(bytes.count) && bytes.allSatisfy { $0 >= 0x20 && $0 < 0x7F && $0 != 0x5C }
            && bytes.contains { $0 != 0x20 }
    }

    /// A received 16-byte field without its padding; leading and trailing
    /// spaces are not significant.
    public static func decode(_ field: [UInt8]) -> String {
        String(decoding: field, as: UTF8.self).trimmingCharacters(in: [" ", "\0"])
    }
}

/// UID rules (PS3.5 9.1).
public enum DICOMUniqueIdentifier {
    public static func isValid(_ uid: String) -> Bool {
        let bytes = Array(uid.utf8)
        guard (1...64).contains(bytes.count), bytes.first != 0x2E, bytes.last != 0x2E else { return false }
        return bytes.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2E }
            && !uid.contains("..")
    }
}
