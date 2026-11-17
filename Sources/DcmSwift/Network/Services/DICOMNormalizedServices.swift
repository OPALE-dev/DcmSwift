import Foundation

/// A DIMSE-N operation or notification (PS3.7 10.1).
public enum DICOMNormalizedOperation: Equatable, Sendable {
    /// N-EVENT-REPORT, invoked by the SCP of the SOP class.
    case eventReport(eventTypeID: UInt16)
    /// N-GET of the listed attributes (tags as group << 16 | element); empty
    /// asks for all of them.
    case get(attributes: [UInt32])
    /// N-SET with a Modification List.
    case set
    /// N-ACTION with Action Information.
    case action(actionTypeID: UInt16)
    /// N-CREATE with an Attribute List.
    case create
    /// N-DELETE.
    case delete

    var requestField: DICOMCommand.Field {
        switch self {
        case .eventReport: return .nEventReportRequest
        case .get: return .nGetRequest
        case .set: return .nSetRequest
        case .action: return .nActionRequest
        case .create: return .nCreateRequest
        case .delete: return .nDeleteRequest
        }
    }

    /// The operation a request command performs, or nil for DIMSE-C.
    init?(_ command: DICOMCommand) {
        switch command.field {
        case .nEventReportRequest: self = .eventReport(eventTypeID: command.eventTypeID ?? 0)
        case .nGetRequest: self = .get(attributes: command.attributeIdentifierList ?? [])
        case .nSetRequest: self = .set
        case .nActionRequest: self = .action(actionTypeID: command.actionTypeID ?? 0)
        case .nCreateRequest: self = .create
        case .nDeleteRequest: self = .delete
        default: return nil
        }
    }
}

/// A DIMSE-N request received by a service.
public struct DICOMNormalizedRequest: Sendable {
    public let operation: DICOMNormalizedOperation
    /// The Affected or Requested SOP Class UID.
    public let sopClassUID: String
    /// The Affected or Requested SOP Instance UID; nil only for an N-CREATE
    /// that lets the SCP choose it.
    public let sopInstanceUID: String?
    /// Event Information, Attribute List, Modification List, or Action
    /// Information, in the presentation context's transfer syntax.
    public let payload: DICOMDataSetPayload?
    let transferSyntaxUID: String

    /// Decodes the data set, if any.
    public func dataSet(limits: DicomReadLimits = DicomReadLimits()) throws -> DataSet? {
        try payload.map { try DICOMDataSetCoding.decode($0.data(), transferSyntax: transferSyntaxUID, limits: limits) }
    }
}

/// The response to a DIMSE-N request (PS3.7 10.1.1.1 to 10.1.6.1).
///
/// The data set is not copied: it must not be changed once the response
/// is returned.
public struct DICOMNormalizedResponse: @unchecked Sendable {
    public var status: DICOMStatus
    /// The Affected SOP Class UID, when the responder gives one.
    public var sopClassUID: String?
    /// The Affected SOP Instance UID; for N-CREATE, the created instance.
    public var sopInstanceUID: String?
    /// Event Reply, Attribute List, or Action Reply.
    public var dataSet: DataSet?
    public var errorComment: String?
    /// Error ID (0000,0903), a code defined by the SOP class.
    public var errorID: UInt16?
    /// Attribute Identifier List (0000,1005) of the attributes in error.
    public var attributes: [UInt32]?
    /// Event Type ID or Action Type ID, echoed in the response.
    public var typeID: UInt16?

    public init(
        status: DICOMStatus, sopClassUID: String? = nil, sopInstanceUID: String? = nil, dataSet: DataSet? = nil,
        errorComment: String? = nil, errorID: UInt16? = nil, attributes: [UInt32]? = nil, typeID: UInt16? = nil
    ) {
        self.errorID = errorID
        self.attributes = attributes
        self.status = status
        self.sopClassUID = sopClassUID
        self.sopInstanceUID = sopInstanceUID
        self.dataSet = dataSet
        self.errorComment = errorComment
        self.typeID = typeID
    }
}

/// Performs the DIMSE-N requests of a SOP class: N-GET, N-SET, N-ACTION,
/// N-CREATE, and N-DELETE as its SCP, and receives N-EVENT-REPORT as its
/// SCU. Errors thrown become a Processing failure (0110H).
public protocol DICOMNormalizedService: Sendable {
    func perform(_ request: DICOMNormalizedRequest, context: DICOMServiceContext) async throws -> DICOMNormalizedResponse
}

extension DICOMAssociation {
    // MARK: DIMSE-N operations (PS3.7 10.1)

    /// N-GET (PS3.7 10.1.2): the attributes of an instance; `attributes`
    /// lists tags as group << 16 | element, all of them when empty.
    public func nGet(
        sopClassUID: String, sopInstanceUID: String, attributes: [UInt32] = [], abstractSyntax: String? = nil
    ) async throws -> DICOMNormalizedResponse {
        try await normalized(
            .get(attributes: attributes), sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID, dataSet: nil,
            abstractSyntax: abstractSyntax)
    }

    /// N-SET (PS3.7 10.1.3).
    public func nSet(
        sopClassUID: String, sopInstanceUID: String, modifications: DataSet, abstractSyntax: String? = nil
    ) async throws -> DICOMNormalizedResponse {
        try await normalized(
            .set, sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID, dataSet: modifications,
            abstractSyntax: abstractSyntax)
    }

    /// N-ACTION (PS3.7 10.1.4).
    public func nAction(
        sopClassUID: String, sopInstanceUID: String, actionTypeID: UInt16, information: DataSet? = nil,
        abstractSyntax: String? = nil
    ) async throws -> DICOMNormalizedResponse {
        try await normalized(
            .action(actionTypeID: actionTypeID), sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID,
            dataSet: information, abstractSyntax: abstractSyntax)
    }

    /// N-CREATE (PS3.7 10.1.5); without an instance UID the SCP assigns one,
    /// returned in the response.
    public func nCreate(
        sopClassUID: String, sopInstanceUID: String? = nil, attributes: DataSet? = nil, abstractSyntax: String? = nil
    ) async throws -> DICOMNormalizedResponse {
        try await normalized(
            .create, sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID, dataSet: attributes,
            abstractSyntax: abstractSyntax)
    }

    /// N-DELETE (PS3.7 10.1.6).
    public func nDelete(
        sopClassUID: String, sopInstanceUID: String, abstractSyntax: String? = nil
    ) async throws -> DICOMNormalizedResponse {
        try await normalized(
            .delete, sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID, dataSet: nil,
            abstractSyntax: abstractSyntax)
    }

    /// N-EVENT-REPORT (PS3.7 10.1.1), sent by the SCP of the SOP class: the
    /// association acceptor, or a requestor granted the SCP role.
    public func nEventReport(
        sopClassUID: String, sopInstanceUID: String, eventTypeID: UInt16, information: DataSet? = nil,
        abstractSyntax: String? = nil
    ) async throws -> DICOMNormalizedResponse {
        try await normalized(
            .eventReport(eventTypeID: eventTypeID), sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID,
            dataSet: information, abstractSyntax: abstractSyntax)
    }

    /// Sends a DIMSE-N request on a context of `abstractSyntax` (the SOP
    /// class by default; a Meta SOP Class may hold several) and waits for
    /// its response.
    func normalized(
        _ operation: DICOMNormalizedOperation, sopClassUID: String, sopInstanceUID: String?, dataSet: DataSet?,
        abstractSyntax: String?
    ) async throws -> DICOMNormalizedResponse {
        let syntax = abstractSyntax ?? sopClassUID
        let context: DICOMAcceptedPresentationContext
        if case .eventReport = operation {
            context = try performerContext(for: syntax)
        } else {
            context = try self.context(for: syntax)
        }
        var command = DICOMCommand(field: operation.requestField, hasDataSet: dataSet != nil)
        switch operation {
        case .eventReport(let type):
            command.affectedSOPClassUID = sopClassUID
            command.affectedSOPInstanceUID = sopInstanceUID
            command.eventTypeID = type
        case .create:
            command.affectedSOPClassUID = sopClassUID
            command.affectedSOPInstanceUID = sopInstanceUID
        case .get(let attributes):
            command.requestedSOPClassUID = sopClassUID
            command.requestedSOPInstanceUID = sopInstanceUID
            command.attributeIdentifierList = attributes.isEmpty ? nil : attributes
        case .action(let type):
            command.requestedSOPClassUID = sopClassUID
            command.requestedSOPInstanceUID = sopInstanceUID
            command.actionTypeID = type
        case .set, .delete:
            command.requestedSOPClassUID = sopClassUID
            command.requestedSOPInstanceUID = sopInstanceUID
        }
        let payload = try dataSet.map {
            DICOMDataSetPayload(data: try DICOMDataSetCoding.encode($0, transferSyntax: context.transferSyntax))
        }
        let (_, queue) = try await runtime.request(command, dataSet: payload, contextID: context.id)
        var last: DICOMMessage?
        while let response = try await queue.next() { last = response }
        guard let last else { throw DICOMNetworkError.connectionClosed }
        guard last.command.field == command.field.response else {
            throw DICOMNetworkError.protocolViolation("\(last.command.field) answers \(command.field)")
        }
        let reply = try last.dataSet.map { try DICOMDataSetCoding.decode($0.data(), transferSyntax: context.transferSyntax) }
        return DICOMNormalizedResponse(
            status: last.command.statusValue ?? .success, sopClassUID: last.command.affectedSOPClassUID,
            sopInstanceUID: last.command.affectedSOPInstanceUID, dataSet: reply, errorComment: last.command.errorComment,
            errorID: last.command.errorID, attributes: last.command.attributeIdentifierList, typeID: last.command.eventTypeID ?? last.command.actionTypeID)
    }

    /// An accepted context on which this side acts as SCP, to send
    /// notifications.
    func performerContext(for abstractSyntax: String) throws -> DICOMAcceptedPresentationContext {
        let isRequestor = runtime.role == .requestor
        guard let context = negotiated.contexts(for: abstractSyntax)
            .first(where: { isRequestor ? $0.requestorIsSCP : $0.requestorIsSCU }) else {
            throw DICOMNetworkError.noPresentationContext(abstractSyntax: abstractSyntax)
        }
        return context
    }
}
