import Foundation

/// An Instance Availability Notification (PS3.4 R, PS3.3 A.42): the
/// instances of one study that may be retrieved, and how.
public struct DICOMInstanceAvailability: Sendable, Equatable {
    /// Instance Availability (0008,0056).
    public enum Availability: String, Sendable, CaseIterable {
        case online = "ONLINE", nearline = "NEARLINE", offline = "OFFLINE", unavailable = "UNAVAILABLE"
    }

    public struct Instance: Sendable, Equatable {
        public var sopClassUID: String
        public var sopInstanceUID: String
        public var availability: Availability
        public var retrieveAETitle: String
        /// Retrieve URL (0008,1190), such as a WADO-RS instance URL.
        public var retrieveURL: String?

        public init(sopClassUID: String, sopInstanceUID: String, availability: Availability = .online,
                    retrieveAETitle: String, retrieveURL: String? = nil) {
            self.sopClassUID = sopClassUID
            self.sopInstanceUID = sopInstanceUID
            self.availability = availability
            self.retrieveAETitle = retrieveAETitle
            self.retrieveURL = retrieveURL
        }
    }

    public struct Series: Sendable, Equatable {
        public var seriesInstanceUID: String
        public var instances: [Instance]

        public init(seriesInstanceUID: String, instances: [Instance]) {
            self.seriesInstanceUID = seriesInstanceUID
            self.instances = instances
        }
    }

    /// A Referenced Performed Procedure Step.
    public struct ProcedureStep: Sendable, Equatable {
        public var sopClassUID: String
        public var sopInstanceUID: String

        public init(sopClassUID: String = DICOMSOPClass.modalityPerformedProcedureStep, sopInstanceUID: String) {
            self.sopClassUID = sopClassUID
            self.sopInstanceUID = sopInstanceUID
        }
    }

    public var studyInstanceUID: String
    public var series: [Series]
    public var procedureSteps: [ProcedureStep]

    public init(studyInstanceUID: String, series: [Series], procedureSteps: [ProcedureStep] = []) {
        self.studyInstanceUID = studyInstanceUID
        self.series = series
        self.procedureSteps = procedureSteps
    }

    /// The N-CREATE Attribute List (Table R.3.2-1).
    public func dataSet() throws -> DataSet {
        func ui(_ value: String) -> [String: Any] { ["vr": "UI", "Value": [value]] }
        let steps: [[String: Any]] = procedureSteps.map {
            ["00081150": ui($0.sopClassUID), "00081155": ui($0.sopInstanceUID), "00404019": ["vr": "SQ"]]
        }
        let series: [[String: Any]] = series.map { series in
            [
                "0020000E": ui(series.seriesInstanceUID),
                "00081199": ["vr": "SQ", "Value": series.instances.map { instance -> [String: Any] in
                    var item: [String: Any] = [
                        "00081150": ui(instance.sopClassUID), "00081155": ui(instance.sopInstanceUID),
                        "00080056": ["vr": "CS", "Value": [instance.availability.rawValue]],
                        "00080054": ["vr": "AE", "Value": [instance.retrieveAETitle]],
                    ]
                    if let url = instance.retrieveURL { item["00081190"] = ["vr": "UR", "Value": [url]] }
                    return item
                }],
            ]
        }
        let stepsAttribute: [String: Any] = steps.isEmpty ? ["vr": "SQ"] : ["vr": "SQ", "Value": steps]
        let object: [String: Any] = [
            "00081111": stepsAttribute, "0020000D": ui(studyInstanceUID), "00081115": ["vr": "SQ", "Value": series],
        ]
        return try DICOMJSON.dataSet(object)
    }

    /// A notification from an N-CREATE Attribute List.
    public init(dataSet: DataSet) throws {
        let object = try DICOMJSON.object(dataSet)
        try self.init(object: object)
    }

    init(object: [String: Any]) throws {
        func items(_ object: [String: Any], _ tag: String) -> [[String: Any]] {
            (object[tag] as? [String: Any])?["Value"] as? [[String: Any]] ?? []
        }
        func string(_ object: [String: Any], _ tag: String) -> String? {
            ((object[tag] as? [String: Any])?["Value"] as? [Any])?.first as? String
        }
        guard let study = string(object, "0020000D") else { throw DICOMCommandError("no Study Instance UID") }
        studyInstanceUID = study
        procedureSteps = items(object, "00081111").compactMap { item in
            string(item, "00081155").map { ProcedureStep(sopClassUID: string(item, "00081150") ?? "", sopInstanceUID: $0) }
        }
        series = try items(object, "00081115").map { item in
            Series(seriesInstanceUID: string(item, "0020000E") ?? "", instances: try items(item, "00081199").map { reference in
                guard let availability = string(reference, "00080056").flatMap(Availability.init(rawValue:)) else {
                    throw DICOMCommandError("invalid Instance Availability")
                }
                return Instance(sopClassUID: string(reference, "00081150") ?? "",
                                sopInstanceUID: string(reference, "00081155") ?? "", availability: availability,
                                retrieveAETitle: string(reference, "00080054") ?? "",
                                retrieveURL: string(reference, "00081190"))
            })
        }
    }

    /// One notification per study for archive records, in series and
    /// record order.
    public static func notifications(
        for records: [DICOMArchive.Record], retrieveAETitle: String, availability: Availability = .online
    ) -> [DICOMInstanceAvailability] {
        var studies: [String: [String: [Instance]]] = [:]
        var studyOrder: [String] = []
        var seriesOrder: [String: [String]] = [:]
        for record in records {
            let study = record.attributes["StudyInstanceUID"] ?? "", series = record.attributes["SeriesInstanceUID"] ?? ""
            if studies[study] == nil { studyOrder.append(study) }
            if studies[study]?[series] == nil { seriesOrder[study, default: []].append(series) }
            studies[study, default: [:]][series, default: []].append(Instance(
                sopClassUID: record.sopClassUID, sopInstanceUID: record.attributes["SOPInstanceUID"] ?? "",
                availability: availability, retrieveAETitle: retrieveAETitle))
        }
        return studyOrder.map { study in
            DICOMInstanceAvailability(studyInstanceUID: study, series: seriesOrder[study]!.map {
                Series(seriesInstanceUID: $0, instances: studies[study]![$0]!)
            })
        }
    }

    /// The attributes Table R.3.2-1 requires.
    static let requirements: [DICOMAttributeRequirement] = [
        DICOMAttributeRequirement(keyword: "ReferencedPerformedProcedureStepSequence", type: "2", items: [
            DICOMAttributeRequirement(keyword: "ReferencedSOPClassUID", type: "1"),
            DICOMAttributeRequirement(keyword: "ReferencedSOPInstanceUID", type: "1"),
            DICOMAttributeRequirement(keyword: "PerformedWorkitemCodeSequence", type: "2"),
        ]),
        DICOMAttributeRequirement(keyword: "StudyInstanceUID", type: "1"),
        DICOMAttributeRequirement(keyword: "ReferencedSeriesSequence", type: "1", items: [
            DICOMAttributeRequirement(keyword: "SeriesInstanceUID", type: "1"),
            DICOMAttributeRequirement(keyword: "ReferencedSOPSequence", type: "1", items: [
                DICOMAttributeRequirement(keyword: "ReferencedSOPClassUID", type: "1"),
                DICOMAttributeRequirement(keyword: "ReferencedSOPInstanceUID", type: "1"),
                DICOMAttributeRequirement(keyword: "InstanceAvailability", type: "1",
                                          values: Set(Availability.allCases.map(\.rawValue))),
                DICOMAttributeRequirement(keyword: "RetrieveAETitle", type: "1"),
            ]),
        ]),
    ]
}

/// An Instance Availability Notification SCP (PS3.4 R.3): N-CREATE
/// requests are checked against Table R.3.2-1 (0120H, 0121H, 0106H), kept
/// in the `instanceAvailability` collection of an archive index, and given
/// to `received`.
public struct DICOMInstanceAvailabilityService: DICOMNormalizedService {
    public let index: DICOMArchiveIndex
    let received: (@Sendable (DICOMInstanceAvailability, DICOMServiceContext) async -> Void)?

    public init(index: DICOMArchiveIndex = DICOMMemoryArchiveIndex(),
                received: (@Sendable (DICOMInstanceAvailability, DICOMServiceContext) async -> Void)? = nil) {
        self.index = index
        self.received = received
    }

    public func perform(_ request: DICOMNormalizedRequest, context: DICOMServiceContext) async throws -> DICOMNormalizedResponse {
        guard case .create = request.operation else { return DICOMNormalizedResponse(status: .unrecognizedOperation) }
        let object = try request.dataSet().map {
            try DICOMJSON.object($0, options: DICOMJSON.EncodingOptions(numbersAsStrings: true))
        } ?? [:]
        if let failure = DICOMAttributeRequirement.check(object, DICOMInstanceAvailability.requirements) {
            return failure
        }
        let uid = request.sopInstanceUID ?? DICOMDataSetBuilder.newUID()
        do {
            try await index.insert(DICOMArchiveDocument(id: uid, attributes: object,
                                                        metadata: ["sourceAETitle": context.callingAETitle]),
                                   into: .instanceAvailability)
        } catch DICOMArchiveError.duplicate {
            return DICOMNormalizedResponse(status: .duplicateSOPInstance)
        }
        await received?(try DICOMInstanceAvailability(object: object), context)
        return DICOMNormalizedResponse(status: .success, sopInstanceUID: uid)
    }
}

extension DICOMAssociation {
    /// Sends an Instance Availability Notification (N-CREATE, PS3.4 R.3.2);
    /// returns the response, whose SOP Instance UID is the notification's.
    public func notifyAvailability(
        _ notification: DICOMInstanceAvailability, sopInstanceUID: String? = nil
    ) async throws -> DICOMNormalizedResponse {
        try await nCreate(sopClassUID: DICOMSOPClass.instanceAvailabilityNotification,
                          sopInstanceUID: sopInstanceUID ?? DICOMDataSetBuilder.newUID(),
                          attributes: notification.dataSet())
    }
}

/// Sends Instance Availability Notifications for stored instances: the
/// instances of a study are gathered until none arrives for `delay`, then
/// notified to every recipient in one N-CREATE. Failures are logged.
public actor DICOMInstanceAvailabilityNotifier {
    public nonisolated let client: DICOMClient
    public nonisolated let recipients: [DICOMRemoteNode]
    public nonisolated let retrieveAETitle: String
    /// Seconds without a new instance before a study is notified.
    public nonisolated let delay: TimeInterval
    private var pending: [String: [DICOMArchive.Record]] = [:]
    private var generations: [String: Int] = [:]

    public init(client: DICOMClient, recipients: [DICOMRemoteNode], retrieveAETitle: String,
                delay: TimeInterval = 5) {
        self.client = client
        self.recipients = recipients
        self.retrieveAETitle = retrieveAETitle
        self.delay = delay
    }

    /// Records a stored instance; its study is notified once quiet.
    public func stored(_ record: DICOMArchive.Record) {
        let study = record.attributes["StudyInstanceUID"] ?? ""
        pending[study, default: []].append(record)
        let generation = generations[study, default: 0] + 1
        generations[study] = generation
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self.flush(study: study, generation: generation)
        }
    }

    private func flush(study: String, generation: Int) async {
        guard generations[study] == generation else { return }
        await flush(study: study)
    }

    /// Sends what is pending for every study now.
    public func flush() async {
        for study in pending.keys.sorted() { await flush(study: study) }
    }

    private func flush(study: String) async {
        guard let records = pending.removeValue(forKey: study) else { return }
        generations[study] = nil
        for notification in DICOMInstanceAvailability.notifications(for: records, retrieveAETitle: retrieveAETitle) {
            await send(notification)
        }
    }

    /// Sends a notification to every recipient.
    public nonisolated func send(_ notification: DICOMInstanceAvailability) async {
        let sopClass = DICOMSOPClass.instanceAvailabilityNotification
        for recipient in recipients {
            do {
                let response = try await client.withAssociation(
                    to: recipient, presentationContexts: .proposals(abstractSyntaxes: [sopClass])
                ) { try await $0.notifyAvailability(notification) }
                if response.status.category == .failure {
                    Logger.warning("\(recipient.aeTitle) refused the availability of \(notification.studyInstanceUID): \(response.status)")
                }
            } catch {
                Logger.warning("availability of \(notification.studyInstanceUID) not sent to \(recipient.aeTitle): \(error)")
            }
        }
    }
}
