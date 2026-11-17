import Foundation

/// An Application Event Logging SCP (PS3.4 P): the Procedural Event
/// Logging and Substance Administration Logging SOP Classes. Each N-ACTION
/// (Action Type 1, on the well-known SOP Instance) is checked, kept in the
/// `eventLog` collection of an archive index, and given to `received`.
///
/// - Procedural events (P.2) need Patient ID, Study Instance UID, Study ID,
///   Synchronization Frame of Reference UID, and Performed Location to be
///   present (0120H), and a CONTAINER with Content Sequence as Event
///   Information (else C102H). An event without Study Instance UID cannot
///   be matched to a study (C103H); the Action Reply returns the Study
///   Instance UID and Patient ID of the request.
/// - Substance administration events (P.3) need Patient ID or Admission ID
///   (else C110H), Product Package Identifier or Product Name, Substance
///   Administration DateTime, Patient's Name, Administration Route Code
///   Sequence, and Operator Identification Sequence with Person
///   Identification Code Sequence (0120H, 0121H).
public struct DICOMEventLoggingService: DICOMNormalizedService {
    public let index: DICOMArchiveIndex
    let received: (@Sendable (String, DataSet, DICOMServiceContext) async -> Void)?

    /// - Parameters:
    ///   - index: where the events are kept.
    ///   - received: called with the SOP Class UID and the Action
    ///     Information of each event logged.
    public init(index: DICOMArchiveIndex = DICOMMemoryArchiveIndex(),
                received: (@Sendable (String, DataSet, DICOMServiceContext) async -> Void)? = nil) {
        self.index = index
        self.received = received
    }

    /// The SOP classes to register with `DICOMServer`.
    public static let sopClasses = [DICOMSOPClass.proceduralEventLogging, DICOMSOPClass.substanceAdministrationLogging]

    // Specific statuses (Tables P.2-3, P.3-3).
    public static let eventDoesNotMatchTemplate = DICOMStatus(code: 0xC102)
    public static let cannotMatchEventToStudy = DICOMStatus(code: 0xC103)
    public static let patientCannotBeIdentified = DICOMStatus(code: 0xC110)

    public func perform(_ request: DICOMNormalizedRequest, context: DICOMServiceContext) async throws -> DICOMNormalizedResponse {
        guard case .action(let type) = request.operation else {
            return DICOMNormalizedResponse(status: .unrecognizedOperation)
        }
        let instance = request.sopClassUID == DICOMSOPClass.proceduralEventLogging
            ? DICOMSOPClass.proceduralEventLoggingInstance : DICOMSOPClass.substanceAdministrationLoggingInstance
        guard request.sopInstanceUID == instance else { return DICOMNormalizedResponse(status: .noSuchObjectInstance) }
        guard type == 1 else { return DICOMNormalizedResponse(status: .noSuchActionType) }
        guard let dataSet = try request.dataSet() else {
            return DICOMNormalizedResponse(status: .missingAttribute, errorComment: "no Action Information")
        }
        let object = try DICOMJSON.object(dataSet, options: DICOMJSON.EncodingOptions(numbersAsStrings: true))
        func value(_ keyword: String) -> String? {
            ((object[DICOMAttributeRequirement.tag(keyword)] as? [String: Any])?["Value"] as? [Any])?.first as? String
        }

        var reply: DataSet?
        if request.sopClassUID == DICOMSOPClass.proceduralEventLogging {
            if let failure = DICOMAttributeRequirement.check(object, Self.proceduralRequirements) { return failure }
            guard value("ValueType") == "CONTAINER", object[DICOMAttributeRequirement.tag("ContentSequence")] != nil else {
                return DICOMNormalizedResponse(status: Self.eventDoesNotMatchTemplate,
                                               errorComment: "the event is not a CONTAINER with content")
            }
            guard let study = value("StudyInstanceUID"), !study.isEmpty else {
                return DICOMNormalizedResponse(status: Self.cannotMatchEventToStudy, errorComment: "no Study Instance UID")
            }
            let identifiers = DataSet()
            _ = identifiers.set(value: study, forTagName: "StudyInstanceUID")
            _ = identifiers.set(value: value("PatientID") ?? "", forTagName: "PatientID")
            reply = identifiers
        } else {
            guard !(value("PatientID") ?? "").isEmpty || !(value("AdmissionID") ?? "").isEmpty else {
                return DICOMNormalizedResponse(status: Self.patientCannotBeIdentified,
                                               errorComment: "neither Patient ID nor Admission ID")
            }
            guard !(value("ProductPackageIdentifier") ?? "").isEmpty || !(value("ProductName") ?? "").isEmpty else {
                return DICOMAttributeRequirement.failure(
                    .missingAttribute, "neither Product Package Identifier nor Product Name", ["ProductName"])
            }
            if let failure = DICOMAttributeRequirement.check(object, Self.substanceRequirements) { return failure }
        }
        try await index.insert(
            DICOMArchiveDocument(id: UUID().uuidString, attributes: object, metadata: [
                "sopClassUID": request.sopClassUID, "sourceAETitle": context.callingAETitle,
                "received": ISO8601DateFormatter().string(from: Date()),
            ]), into: .eventLog)
        await received?(request.sopClassUID, dataSet, context)
        return DICOMNormalizedResponse(status: .success, dataSet: reply, typeID: 1)
    }

    static let proceduralRequirements = ["PatientID", "StudyInstanceUID", "StudyID", "SynchronizationFrameOfReferenceUID",
                                         "PerformedLocation"].map { DICOMAttributeRequirement(keyword: $0, type: "2") }

    static let substanceRequirements = [
        DICOMAttributeRequirement(keyword: "PatientName", type: "2"),
        DICOMAttributeRequirement(keyword: "SubstanceAdministrationDateTime", type: "1"),
        DICOMAttributeRequirement(keyword: "AdministrationRouteCodeSequence", type: "2"),
        DICOMAttributeRequirement(keyword: "OperatorIdentificationSequence", type: "1", items: [
            DICOMAttributeRequirement(keyword: "PersonIdentificationCodeSequence", type: "1"),
        ]),
    ]
}

extension DICOMAssociation {
    /// Records a procedural event (PS3.4 P.2): N-ACTION, Action Type 1, with
    /// the identifiers of the study and the event as a TID 3001 Content Item.
    /// The Action Reply holds the study the event was logged in.
    public func logProceduralEvent(_ information: DataSet) async throws -> DICOMNormalizedResponse {
        try await nAction(sopClassUID: DICOMSOPClass.proceduralEventLogging,
                          sopInstanceUID: DICOMSOPClass.proceduralEventLoggingInstance, actionTypeID: 1,
                          information: information)
    }

    /// Records a substance administration (PS3.4 P.3): N-ACTION, Action
    /// Type 1, with the Substance Administration Log Module.
    public func logSubstanceAdministration(_ information: DataSet) async throws -> DICOMNormalizedResponse {
        try await nAction(sopClassUID: DICOMSOPClass.substanceAdministrationLogging,
                          sopInstanceUID: DICOMSOPClass.substanceAdministrationLoggingInstance, actionTypeID: 1,
                          information: information)
    }
}
