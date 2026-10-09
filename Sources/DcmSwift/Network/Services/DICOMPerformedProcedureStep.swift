import Foundation

/// A Modality Performed Procedure Step SCP (PS3.4 F.7 to F.9): N-CREATE
/// and N-SET under the Modality Performed Procedure Step SOP Class, N-GET
/// under the Retrieve SOP Class, and the events of the Notification SOP
/// Class given to `notify`.
///
/// Requests are checked against Table F.7.2-1:
/// - N-CREATE needs Performed Procedure Step Status IN PROGRESS (else 0106H)
///   and the Type 1 and Type 2 attributes, including those of the Items of
///   the Scheduled Step Attributes and Performed Series Sequences (0120H when
///   absent, 0121H when a Type 1 value is empty); an existing instance is
///   refused with 0111H, and an instance without UID gets one.
/// - N-SET is refused with 0110H, Error ID A710H, once the step is COMPLETED
///   or DISCONTINUED; attributes that may not be set are refused with
///   0106H; a sequence replaces the previous one whole.
/// - A step becomes COMPLETED or DISCONTINUED only with the Final State
///   attributes: End Date and Time, and Performed Series Sequence (with at
///   least one Item to be COMPLETED); else 0121H.
/// Conditional (1C, 2C) requirements are not checked.
public actor DICOMPerformedProcedureStepService: DICOMNormalizedService {
    /// The Notification events (PS3.4 Table F.9.2-1).
    public enum Event: UInt16, Sendable {
        case inProgress = 1, completed, discontinued, updated, deleted
    }

    /// A directory where each instance is written as `<uid>.json` (DICOM
    /// JSON) after each change, and read at start-up; nil keeps them in
    /// memory only.
    public nonisolated let directory: URL?
    private let notify: (@Sendable (Event, String, DataSet) async -> Void)?
    private var instances: [String: [String: Any]] = [:]

    public init(directory: URL? = nil, notify: (@Sendable (Event, String, DataSet) async -> Void)? = nil) {
        self.directory = directory
        self.notify = notify
        if let directory {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    instances[file.deletingPathExtension().lastPathComponent] = object
                }
            }
        }
    }

    /// The SOP classes to register with `DICOMServer`: the Modality
    /// Performed Procedure Step SOP Class and its Retrieve SOP Class.
    public static let sopClasses = [DICOMSOPClass.modalityPerformedProcedureStep,
                                    DICOMSOPClass.modalityPerformedProcedureStepRetrieve]

    /// The instance with this UID.
    public func instance(_ uid: String) throws -> DataSet? {
        try instances[uid].map { try DICOMJSON.dataSet($0) }
    }

    /// The UIDs of the instances.
    public func instanceUIDs() -> [String] { instances.keys.sorted() }

    public nonisolated func perform(
        _ request: DICOMNormalizedRequest, context: DICOMServiceContext
    ) async throws -> DICOMNormalizedResponse {
        let attributes = try request.dataSet().map {
            try DICOMJSON.object($0, options: DICOMJSON.EncodingOptions(numbersAsStrings: true))
        }
        switch (request.operation, request.sopClassUID) {
        case (.create, DICOMSOPClass.modalityPerformedProcedureStep):
            return try await create(request.sopInstanceUID, attributes ?? [:])
        case (.set, DICOMSOPClass.modalityPerformedProcedureStep):
            return try await set(request.sopInstanceUID ?? "", attributes ?? [:])
        case (.get(let tags), DICOMSOPClass.modalityPerformedProcedureStepRetrieve):
            return try await get(request.sopInstanceUID ?? "", tags)
        default:
            return DICOMNormalizedResponse(status: .unrecognizedOperation)
        }
    }

    // MARK: Operations

    func create(_ uid: String?, _ attributes: [String: Any]) async throws -> DICOMNormalizedResponse {
        let uid = uid ?? DICOMDataSetBuilder.newUID()
        guard instances[uid] == nil else { return DICOMNormalizedResponse(status: .duplicateSOPInstance) }
        guard Self.status(attributes) == "IN PROGRESS" else {
            return Self.failure(.invalidAttributeValue, "Performed Procedure Step Status must be IN PROGRESS",
                                ["PerformedProcedureStepStatus"])
        }
        if let failure = Self.check(attributes, Self.createRules) { return failure }
        var instance = attributes
        instance[Self.tag("SOPInstanceUID")] = ["vr": "UI", "Value": [uid]]
        instance[Self.tag("SOPClassUID")] = ["vr": "UI", "Value": [DICOMSOPClass.modalityPerformedProcedureStep]]
        try save(uid, instance)
        await notify?(.inProgress, uid, try DICOMJSON.dataSet(instance))
        return DICOMNormalizedResponse(status: .success, sopInstanceUID: uid)
    }

    func set(_ uid: String, _ modifications: [String: Any]) async throws -> DICOMNormalizedResponse {
        guard var instance = instances[uid] else { return DICOMNormalizedResponse(status: .noSuchObjectInstance) }
        guard Self.status(instance) == "IN PROGRESS" else {
            return DICOMNormalizedResponse(
                status: .processingFailure, errorComment: "Performed Procedure Step Object may no longer be updated",
                errorID: 0xA710)
        }
        let refused = modifications.keys.filter { !Self.settable.contains($0) }.sorted()
        if !refused.isEmpty {
            return DICOMNormalizedResponse(
                status: .invalidAttributeValue, errorComment: "attributes that may not be set",
                attributes: refused.compactMap { UInt32($0, radix: 16) })
        }
        if let failure = Self.check(modifications, Self.setRules, presentOnly: true) { return failure }
        for (tag, value) in modifications where tag != Self.specificCharacterSet { instance[tag] = value }
        let status = Self.status(instance)
        guard ["IN PROGRESS", "COMPLETED", "DISCONTINUED"].contains(status) else {
            return Self.failure(.invalidAttributeValue, "unknown Performed Procedure Step Status \(status)",
                                ["PerformedProcedureStepStatus"])
        }
        if status != "IN PROGRESS" {
            var rules = Self.finalRules
            if status == "DISCONTINUED" { rules[2].type = "2" }
            if let failure = Self.check(instance, rules) { return failure }
        }
        try save(uid, instance)
        let event: Event = status == "COMPLETED" ? .completed : status == "DISCONTINUED" ? .discontinued : .updated
        await notify?(event, uid, try DICOMJSON.dataSet(instance))
        return DICOMNormalizedResponse(status: .success)
    }

    func get(_ uid: String, _ tags: [UInt32]) throws -> DICOMNormalizedResponse {
        guard let instance = instances[uid] else { return DICOMNormalizedResponse(status: .noSuchObjectInstance) }
        var reply = instance
        if !tags.isEmpty {
            let wanted = Set(tags.map { String(format: "%08X", $0) })
            reply = instance.filter { wanted.contains($0.key) || $0.key == Self.specificCharacterSet }
        }
        return DICOMNormalizedResponse(status: .success, dataSet: try DICOMJSON.dataSet(reply))
    }

    private func save(_ uid: String, _ instance: [String: Any]) throws {
        if let directory {
            let data = try JSONSerialization.data(withJSONObject: instance, options: [.sortedKeys])
            try data.write(to: directory.appendingPathComponent(uid + ".json"), options: .atomic)
        }
        instances[uid] = instance
    }

    // MARK: Table F.7.2-1

    /// An attribute that must be present (Type 2) or have a value (Type 1),
    /// with the requirements of its Items.
    struct Requirement {
        let keyword: String
        var type: Character
        var items: [Requirement] = []
    }

    static let specificCharacterSet = "00080005"

    static func tag(_ keyword: String) -> String {
        DicomSpec.shared.dataTag(forName: keyword)!.code.uppercased()
    }

    static let referencedInstance = [Requirement(keyword: "ReferencedSOPClassUID", type: "1"),
                                     Requirement(keyword: "ReferencedSOPInstanceUID", type: "1")]

    static let performedSeries = [
        Requirement(keyword: "PerformingPhysicianName", type: "2"),
        Requirement(keyword: "ProtocolName", type: "1"),
        Requirement(keyword: "OperatorsName", type: "2"),
        Requirement(keyword: "SeriesInstanceUID", type: "1"),
        Requirement(keyword: "SeriesDescription", type: "2"),
        Requirement(keyword: "RetrieveAETitle", type: "2"),
        Requirement(keyword: "ReferencedImageSequence", type: "2", items: referencedInstance),
        Requirement(keyword: "ReferencedNonImageCompositeSOPInstanceSequence", type: "2", items: referencedInstance),
    ]

    static let createRules: [Requirement] = [
        Requirement(keyword: "ScheduledStepAttributesSequence", type: "1", items: [
            Requirement(keyword: "StudyInstanceUID", type: "1"),
            Requirement(keyword: "ReferencedStudySequence", type: "2", items: referencedInstance),
            Requirement(keyword: "AccessionNumber", type: "2"),
            Requirement(keyword: "RequestedProcedureID", type: "2"),
            Requirement(keyword: "RequestedProcedureDescription", type: "2"),
            Requirement(keyword: "ScheduledProcedureStepID", type: "2"),
            Requirement(keyword: "ScheduledProcedureStepDescription", type: "2"),
            Requirement(keyword: "ScheduledProtocolCodeSequence", type: "2"),
        ]),
        Requirement(keyword: "PatientName", type: "2"),
        Requirement(keyword: "PatientID", type: "2"),
        Requirement(keyword: "PatientBirthDate", type: "2"),
        Requirement(keyword: "PatientSex", type: "2"),
        Requirement(keyword: "ReferencedPatientSequence", type: "2", items: referencedInstance),
        Requirement(keyword: "PerformedProcedureStepID", type: "1"),
        Requirement(keyword: "PerformedStationAETitle", type: "1"),
        Requirement(keyword: "PerformedStationName", type: "2"),
        Requirement(keyword: "PerformedLocation", type: "2"),
        Requirement(keyword: "PerformedProcedureStepStartDate", type: "1"),
        Requirement(keyword: "PerformedProcedureStepStartTime", type: "1"),
        Requirement(keyword: "PerformedProcedureStepStatus", type: "1"),
        Requirement(keyword: "PerformedProcedureStepDescription", type: "2"),
        Requirement(keyword: "PerformedProcedureTypeDescription", type: "2"),
        Requirement(keyword: "ProcedureCodeSequence", type: "2"),
        Requirement(keyword: "PerformedProcedureStepEndDate", type: "2"),
        Requirement(keyword: "PerformedProcedureStepEndTime", type: "2"),
        Requirement(keyword: "Modality", type: "1"),
        Requirement(keyword: "StudyID", type: "2"),
        Requirement(keyword: "PerformedProtocolCodeSequence", type: "2"),
        Requirement(keyword: "PerformedSeriesSequence", type: "2", items: performedSeries),
    ]

    /// Requirements on the Items of the sequences an N-SET replaces.
    static let setRules = [Requirement(keyword: "PerformedSeriesSequence", type: "3", items: performedSeries)]

    /// Final State (the third requirement is relaxed for DISCONTINUED).
    static let finalRules = [
        Requirement(keyword: "PerformedProcedureStepEndDate", type: "1"),
        Requirement(keyword: "PerformedProcedureStepEndTime", type: "1"),
        Requirement(keyword: "PerformedSeriesSequence", type: "1", items: performedSeries),
    ]

    /// The attributes an N-SET may carry: those of Table F.7.2-1 with an
    /// N-SET usage, and the Billing and Material Management Code Module.
    static let settable: Set<String> = Set([
        "SpecificCharacterSet", "PerformedProcedureStepStatus", "PerformedProcedureStepDescription",
        "PerformedProcedureTypeDescription", "ProcedureCodeSequence", "ReasonForPerformedProcedureCodeSequence",
        "PerformedProcedureStepEndDate", "PerformedProcedureStepEndTime", "CommentsOnThePerformedProcedureStep",
        "PerformedProcedureStepDiscontinuationReasonCodeSequence", "PerformedProtocolCodeSequence",
        "PerformedSeriesSequence", "BillingProcedureStepSequence", "FilmConsumptionSequence",
        "BillingSuppliesAndDevicesSequence",
    ].map(tag))

    static func status(_ object: [String: Any]) -> String {
        ((object[tag("PerformedProcedureStepStatus")] as? [String: Any])?["Value"] as? [Any])?.first as? String ?? ""
    }

    static func failure(_ status: DICOMStatus, _ comment: String, _ keywords: [String]) -> DICOMNormalizedResponse {
        DICOMNormalizedResponse(status: status, errorComment: comment,
                                attributes: keywords.compactMap { UInt32(tag($0), radix: 16) })
    }

    /// The failure for the first unmet requirement; with `presentOnly`, the
    /// top-level requirements apply only to the attributes present.
    static func check(_ object: [String: Any], _ rules: [Requirement], presentOnly: Bool = false) -> DICOMNormalizedResponse? {
        for rule in rules {
            let key = tag(rule.keyword)
            guard let attribute = object[key] as? [String: Any] else {
                if presentOnly || rule.type == "3" { continue }
                return failure(.missingAttribute, "\(rule.keyword) is missing", [rule.keyword])
            }
            let values = attribute["Value"] as? [Any] ?? []
            let empty = values.isEmpty || values.allSatisfy { $0 is NSNull || ($0 as? String)?.isEmpty == true }
            if rule.type == "1", empty {
                return failure(.missingAttributeValue, "\(rule.keyword) has no value", [rule.keyword])
            }
            for item in values.compactMap({ $0 as? [String: Any] }) where !rule.items.isEmpty {
                if let failure = check(item, rule.items) { return failure }
            }
        }
        return nil
    }
}

/// Sends the events of a `DICOMPerformedProcedureStepService` to SCUs of
/// the Modality Performed Procedure Step Notification SOP Class (PS3.4
/// F.9), each on a new association. Failures are logged.
public struct DICOMPerformedProcedureStepNotifier: Sendable {
    public let client: DICOMClient
    public let recipients: [DICOMRemoteNode]

    public init(client: DICOMClient, recipients: [DICOMRemoteNode]) {
        self.client = client
        self.recipients = recipients
    }

    /// Sends N-EVENT-REPORT with the event's type to every recipient.
    public func send(_ event: DICOMPerformedProcedureStepService.Event, instance uid: String) async {
        let sopClass = DICOMSOPClass.modalityPerformedProcedureStepNotification
        for recipient in recipients {
            do {
                try await client.withAssociation(
                    to: recipient, presentationContexts: .proposals(abstractSyntaxes: [sopClass]),
                    roleSelections: [DICOMRoleSelection(sopClassUID: sopClass, scuRole: false, scpRole: true)]
                ) { association in
                    _ = try await association.nEventReport(
                        sopClassUID: sopClass, sopInstanceUID: uid, eventTypeID: event.rawValue)
                }
            } catch {
                Logger.warning("MPPS notification \(event) of \(uid) not sent to \(recipient.aeTitle): \(error)")
            }
        }
    }
}
