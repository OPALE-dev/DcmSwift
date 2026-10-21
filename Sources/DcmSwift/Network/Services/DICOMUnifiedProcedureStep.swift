import Foundation
import Logging

/// UPS Push, Pull, Watch and Event SCP (PS3.4 Annex CC). The index holds both
/// UPS instances and subscriptions; `replace` enforces the Transaction UID
/// state change against a document version shared by all server processes.
public actor DICOMUnifiedProcedureStepService: DICOMNormalizedService, DICOMQueryService {
    public nonisolated let index: DICOMArchiveIndex
    public nonisolated let eventHub: DICOMUPSEventHub
    /// Called for each subscribed AE. The application opens an association
    /// with the UPS Event SOP Class and sends N-EVENT-REPORT on it.
    private let notify: (@Sendable (String, String, UInt16, DataSet) async -> Void)?

    private let receivingAEs: Set<String>?
    private let eventReportsSupported: Bool
    private let receive: (@Sendable (String, UInt16, DataSet) async -> Void)?

    public init(index: DICOMArchiveIndex = DICOMMemoryArchiveIndex(),
                eventHub: DICOMUPSEventHub = DICOMUPSEventHub(),
                receivingAEs: Set<String>? = nil, eventReportsSupported: Bool = true,
                receive: (@Sendable (String, UInt16, DataSet) async -> Void)? = nil,
                notify: (@Sendable (String, String, UInt16, DataSet) async -> Void)? = nil) {
        self.index = index
        self.eventHub = eventHub
        self.receivingAEs = receivingAEs
        self.eventReportsSupported = eventReportsSupported
        self.receive = receive
        self.notify = notify
    }

    public static let sopClasses = [DICOMSOPClass.upsPush, DICOMSOPClass.upsPull,
                                    DICOMSOPClass.upsWatch, DICOMSOPClass.upsEvent]

    enum Tag {
        static let state = "00741000"
        static let transaction = "00081195"
        static let instance = "00080018"
        static let sopClass = "00080016"
        static let priority = "00741200"
        static let label = "00741204"
        static let worklist = "00741202"
        static let start = "00404005"
        static let readiness = "00404041"
        static let scheduledParameters = "00741210"
        static let stationName = "00404025"
        static let stationClass = "00404026"
        static let stationLocation = "00404027"
        static let workitem = "00404018"
        static let comments = "00400400"
        static let input = "00404021"
        static let progress = "00741002"
        static let performed = "00741216"
        static let performedStart = "00404050"
        static let performedEnd = "00404051"
        static let performedStation = "00404028"
        static let performedWorkitem = "00404019"
        static let output = "00404033"
        static let cancelTime = "00404052"
        static let cancelReasonCode = "0074100E"
        static let cancelReason = "00741238"
        static let receivingAE = "00741234"
        static let requestingAE = "00741236"
        static let deletionLock = "00741230"
        static let modificationTime = "00404010"
    }

    static func attribute(_ vr: String, _ value: String) -> [String: Any] {
        ["vr": vr, "Value": [value]]
    }

    static func value(_ object: [String: Any], _ tag: String) -> String? {
        ((object[tag] as? [String: Any])?["Value"] as? [String])?.first
    }

    static func hasValue(_ object: [String: Any], _ tag: String) -> Bool {
        guard let values = (object[tag] as? [String: Any])?["Value"] as? [Any] else { return false }
        return !values.isEmpty && values.contains { !($0 is NSNull) && !(($0 as? String)?.isEmpty ?? false) }
    }

    private static func dateTime() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmssXXXXX"
        return formatter.string(from: Date()).replacingOccurrences(of: "Z", with: "+0000")
    }

    private static func reply(_ code: UInt16, _ comment: String? = nil) -> DICOMNormalizedResponse {
        DICOMNormalizedResponse(status: DICOMStatus(code: code), errorComment: comment)
    }

    public nonisolated func perform(_ request: DICOMNormalizedRequest,
                                    context: DICOMServiceContext) async throws -> DICOMNormalizedResponse {
        let object = try request.dataSet().map {
            try DICOMJSON.object($0, options: DICOMJSON.EncodingOptions(numbersAsStrings: true))
        } ?? [:]
        let uid = request.sopInstanceUID ?? ""
        // The command's SOP Class UID is always UPS Push, even when the
        // negotiated abstract syntax is Pull or Watch (CC.3.1).
        guard request.sopClassUID == DICOMSOPClass.upsPush else {
            return DICOMNormalizedResponse(status: .noSuchSOPClass)
        }
        switch (context.presentationContext.abstractSyntax, request.operation) {
        case (DICOMSOPClass.upsPush, .create):
            return try await create(request.sopInstanceUID, object)
        case (DICOMSOPClass.upsPush, .action(2)), (DICOMSOPClass.upsWatch, .action(2)):
            return try await cancel(uid, object, requestingAE: context.callingAETitle)
        case (DICOMSOPClass.upsPull, .action(1)):
            return try await changeState(uid, object)
        case (DICOMSOPClass.upsPull, .set), (DICOMSOPClass.upsPush, .set):
            return try await set(uid, object)
        case (DICOMSOPClass.upsPull, .get(let tags)),
             (DICOMSOPClass.upsPush, .get(let tags)),
             (DICOMSOPClass.upsWatch, .get(let tags)):
            return try await get(uid, tags)
        case (DICOMSOPClass.upsWatch, .action(let action)) where (3...5).contains(action):
            return try await subscription(uid, action: action, object: object)
        case (DICOMSOPClass.upsEvent, .eventReport(let type)) where (1...5).contains(type):
            return try await receiveEvent(uid, type: type, object: object)
        case (_, .eventReport): return DICOMNormalizedResponse(status: .noSuchEventType)
        case (_, .action): return DICOMNormalizedResponse(status: .noSuchActionType)
        default:
            return DICOMNormalizedResponse(status: .unrecognizedOperation)
        }
    }

    func receiveEvent(_ uid: String, type: UInt16, object: [String: Any]) async throws -> DICOMNormalizedResponse {
        let required: [String]
        switch type {
        case 1: required = [Tag.state, Tag.readiness]
        case 2: required = [Tag.requestingAE]
        case 3: required = [Tag.progress]
        case 4: required = ["00741242", "00741244", "00741246"]
        case 5: required = []
        default: return DICOMNormalizedResponse(status: .noSuchEventType)
        }
        if let missing = required.first(where: { !Self.hasValue(object, $0) }) {
            return Self.reply(0x0120, "missing event attribute \(missing)")
        }
        if let receive { await receive(uid, type, try DICOMJSON.dataSet(object)) }
        return DICOMNormalizedResponse(status: .success)
    }

    /// Creates a SCHEDULED instance. The required Type 1/2 top-level
    /// attributes of CC.2.5-3 are checked; the SCP supplies its own UIDs,
    /// worklist label, and modification time.
    func create(_ requestedUID: String?, _ object: [String: Any]) async throws -> DICOMNormalizedResponse {
        let uid = requestedUID ?? DICOMDataSetBuilder.newUID()
        guard try await index.document(uid, in: .unifiedProcedureSteps) == nil else {
            return DICOMNormalizedResponse(status: .duplicateSOPInstance)
        }
        // Top-level Type 1 and Type 2 N-CREATE attributes in CC.2.5-3.
        let type1 = [Tag.priority, Tag.label, Tag.start, Tag.readiness, Tag.state]
        let type2 = [Tag.transaction, Tag.worklist, Tag.scheduledParameters,
                     Tag.stationName, Tag.stationClass, Tag.stationLocation,
                     Tag.workitem, Tag.comments, Tag.input,
                     "00100010", "00100021", "00100024", "00101002",
                     "00100030", "00100040", "00380010", "00380014",
                     "00081080", "00081084", "0040A370", Tag.progress, Tag.performed]
        if let missing = (type1 + type2).first(where: { object[$0] == nil }) {
            return Self.reply(0x0120, "required UPS attribute \(missing) is missing")
        }
        if let empty = type1.first(where: { !Self.hasValue(object, $0) }) {
            return Self.reply(0x0121, "required UPS attribute \(empty) has no value")
        }
        if Self.value(object, Tag.state) != "SCHEDULED" {
            return Self.reply(0xC309, "UPS must be created SCHEDULED")
        }
        if Self.hasValue(object, Tag.transaction) || Self.hasValue(object, Tag.progress)
            || Self.hasValue(object, Tag.performed) {
            return Self.reply(0x0106, "Transaction UID and performed information must be empty at creation")
        }
        if let sopClass = Self.value(object, Tag.sopClass), sopClass != DICOMSOPClass.upsPush {
            return Self.reply(0x0106, "SOP Class must be UPS Push")
        }
        if object[Tag.instance] != nil || object[Tag.modificationTime] != nil {
            return Self.reply(0x0106, "SCP-managed attribute in N-CREATE")
        }
        if let error = Self.validateAttributes(object) { return Self.reply(0x0106, error) }
        var instance = object
        // The SCP supports these Type 2 attributes even when the SCU's
        // real-world Type 1C condition does not apply.
        instance["00100020"] = instance["00100020"] ?? ["vr": "LO"]
        instance["0020000D"] = instance["0020000D"] ?? ["vr": "UI"]
        instance[Tag.instance] = Self.attribute("UI", uid)
        instance[Tag.sopClass] = Self.attribute("UI", DICOMSOPClass.upsPush)
        instance[Tag.state] = Self.attribute("CS", "SCHEDULED")
        instance[Tag.transaction] = ["vr": "UI"]
        if !Self.hasValue(instance, Tag.worklist) {
            instance[Tag.worklist] = Self.attribute("LO", "DEFAULT")
        }
        instance[Tag.modificationTime] = Self.attribute("DT", Self.dateTime())
        for (tag, vr) in [(Tag.scheduledParameters, "SQ"), (Tag.stationName, "SQ"),
                          (Tag.stationClass, "SQ"), (Tag.stationLocation, "SQ"),
                          (Tag.workitem, "SQ"), (Tag.input, "SQ"), (Tag.progress, "SQ"),
                          (Tag.performed, "SQ")] {
            instance[tag] = instance[tag] ?? ["vr": vr]
        }
        instance[Tag.comments] = instance[Tag.comments] ?? ["vr": "LT"]
        do {
            try await index.insert(DICOMArchiveDocument(id: uid, attributes: instance), into: .unifiedProcedureSteps)
        } catch DICOMArchiveError.duplicate {
            return DICOMNormalizedResponse(status: .duplicateSOPInstance)
        }
        try await applyGlobalSubscriptions(to: uid, instance: instance)
        return DICOMNormalizedResponse(status: .success, sopInstanceUID: uid)
    }

    /// Applies CC.1.1-2 and CC.2.1-2, including optimistic locking.
    func changeState(_ uid: String, _ action: [String: Any], requestingAE: String? = nil) async throws -> DICOMNormalizedResponse {
        guard var document = try await index.document(uid, in: .unifiedProcedureSteps) else { return Self.reply(0xC307) }
        let old = Self.value(document.attributes, Tag.state) ?? ""
        guard let desired = Self.value(action, Tag.state),
              let token = Self.value(action, Tag.transaction), !token.isEmpty else {
            return Self.reply(0x0121, "Procedure Step State and Transaction UID are required")
        }
        if desired == "SCHEDULED" { return Self.reply(0xC303) }
        if old == "IN PROGRESS" || old == "COMPLETED" || old == "CANCELED" {
            guard token == Self.value(document.attributes, Tag.transaction) else { return Self.reply(0xC301) }
        }
        if desired == old {
            if desired == "COMPLETED" { return Self.reply(0xB306) }
            if desired == "CANCELED" { return Self.reply(0xB304) }
            return Self.reply(0xC302)
        }
        if old == "COMPLETED" || old == "CANCELED" { return Self.reply(0xC300) }
        if desired == "IN PROGRESS" {
            guard old == "SCHEDULED" else { return Self.reply(0xC302) }
            document.attributes[Tag.transaction] = Self.attribute("UI", token)
        } else if desired == "COMPLETED" || desired == "CANCELED" {
            guard old == "IN PROGRESS" else { return Self.reply(0xC310) }
            if desired == "CANCELED" {
                var progress = Self.items(document.attributes, Tag.progress).first ?? [:]
                if !Self.hasValue(progress, Tag.cancelTime) {
                    progress[Tag.cancelTime] = Self.attribute("DT", Self.dateTime())
                }
                document.attributes[Tag.progress] = ["vr": "SQ", "Value": [progress]]
            }
            if let missing = Self.missingFinalAttribute(document.attributes, state: desired) {
                return Self.reply(0xC304, "final state requires \(missing)")
            }
        } else { return Self.reply(0x0106, "unknown Procedure Step State") }
        document.attributes[Tag.state] = Self.attribute("CS", desired)
        document.attributes[Tag.modificationTime] = Self.attribute("DT", Self.dateTime())
        do {
            try await index.replace(document, in: .unifiedProcedureSteps)
        } catch DICOMArchiveError.conflict { return Self.reply(0xC301, "UPS changed concurrently") }
        var report = document.attributes
        if let requestingAE { report[Tag.requestingAE] = Self.attribute("AE", requestingAE) }
        try await emit(uid: uid, event: 1, object: report)
        return DICOMNormalizedResponse(status: .success)
    }

    private static func missingFinalAttribute(_ object: [String: Any], state: String) -> String? {
        for tag in [Tag.sopClass, Tag.instance, Tag.priority, Tag.start, Tag.modificationTime,
                    Tag.readiness, Tag.state] where !hasValue(object, tag) { return tag }
        if state == "CANCELED" {
            guard let progress = items(object, Tag.progress).first else { return Tag.progress }
            for tag in [Tag.cancelTime, Tag.cancelReasonCode] where !hasValue(progress, tag) { return tag }
            return nil
        }
        guard !items(object, Tag.performed).isEmpty else { return Tag.performed }
        for performed in items(object, Tag.performed) {
            for tag in [Tag.performedStation, Tag.performedStart, Tag.performedWorkitem, Tag.performedEnd] {
                if !hasValue(performed, tag) { return tag }
            }
            // Output Information is Type 2: an empty sequence means no output.
            if performed[Tag.output] == nil { return Tag.output }
        }
        return nil
    }

    /// N-SET is restricted to the owning Transaction UID while IN PROGRESS.
    func set(_ uid: String, _ changes: [String: Any]) async throws -> DICOMNormalizedResponse {
        guard var document = try await index.document(uid, in: .unifiedProcedureSteps) else { return Self.reply(0xC307) }
        let state = Self.value(document.attributes, Tag.state) ?? ""
        if state == "COMPLETED" || state == "CANCELED" { return Self.reply(0xC300) }
        if state == "IN PROGRESS" {
            guard Self.value(changes, Tag.transaction) == Self.value(document.attributes, Tag.transaction) else {
                return Self.reply(0xC301)
            }
        } else if changes[Tag.transaction] != nil {
            return Self.reply(0xC301)
        }
        let immutable: Set<String> = [Tag.state, Tag.instance, Tag.sopClass, Tag.transaction,
                                      Tag.modificationTime, "00100010", "00100020", "00100021", "00100024",
                                      "00100030", "00100040", "00380010", "00380014", "00081080",
                                      "00081084", "0040A370", "00741224", "00100041", "00100043",
                                      "00100011", "00100014"]
        if changes.keys.contains(where: { immutable.contains($0) && $0 != Tag.transaction }) {
            return Self.reply(0x0106, "attribute cannot be set")
        }
        if let unknown = changes.keys.first(where: { document.attributes[$0] == nil && $0 != "00080005" }) {
            return Self.reply(0x0105, "attribute was not created: \(unknown)")
        }
        for tag in [Tag.priority, Tag.label, Tag.worklist, Tag.start, Tag.readiness,
                    Tag.workitem, Tag.comments, "00404011"] where changes[tag] != nil && !Self.hasValue(changes, tag) {
            return Self.reply(0x0106, "empty N-SET Type 1 attribute \(tag)")
        }
        let previous = document.attributes
        for (tag, value) in changes where tag != Tag.transaction { document.attributes[tag] = value }
        if let error = Self.validateAttributes(document.attributes) { return Self.reply(0x0106, error) }
        document.attributes[Tag.modificationTime] = Self.attribute("DT", Self.dateTime())
        do { try await index.replace(document, in: .unifiedProcedureSteps) }
        catch DICOMArchiveError.conflict { return Self.reply(0xC301, "UPS changed concurrently") }
        func changed(_ tag: String) -> Bool {
            !NSDictionary(dictionary: previous[tag] as? [String: Any] ?? [:])
                .isEqual(to: document.attributes[tag] as? [String: Any] ?? [:])
        }
        if changed(Tag.readiness) { try await emit(uid: uid, event: 1, object: document.attributes) }
        if changed(Tag.stationName) || changed("00404034") {
            try await emit(uid: uid, event: 5, object: document.attributes)
        }
        if changed(Tag.progress) { try await emit(uid: uid, event: 3, object: document.attributes) }
        return DICOMNormalizedResponse(status: .success)
    }

    func get(_ uid: String, _ tags: [UInt32] = []) async throws -> DICOMNormalizedResponse {
        guard var object = try await index.document(uid, in: .unifiedProcedureSteps)?.attributes else {
            return Self.reply(0xC307)
        }
        object.removeValue(forKey: Tag.transaction)
        object.removeValue(forKey: Tag.instance)
        object.removeValue(forKey: Tag.sopClass)
        if !tags.isEmpty {
            let wanted = Set(tags.map { String(format: "%08X", $0) })
            object = object.filter { wanted.contains($0.key) || $0.key == "00080005" }
        }
        return DICOMNormalizedResponse(status: .success, dataSet: try DICOMJSON.dataSet(object))
    }

    func cancel(_ uid: String, _ reason: [String: Any], requestingAE: String) async throws -> DICOMNormalizedResponse {
        guard var document = try await index.document(uid, in: .unifiedProcedureSteps) else { return Self.reply(0xC307) }
        let state = Self.value(document.attributes, Tag.state)
        if state == "CANCELED" { return Self.reply(0xB304) }
        if state == "COMPLETED" { return Self.reply(0xC311) }
        if let error = Self.validateAttributes([Tag.progress: ["vr": "SQ", "Value": [reason]]]) {
            return Self.reply(0x0106, error)
        }
        var requestEvent = reason
        requestEvent[Tag.requestingAE] = Self.attribute("AE", requestingAE)
        try await emit(uid: uid, event: 2, object: requestEvent)
        if state == "SCHEDULED" {
            document.attributes[Tag.transaction] = Self.attribute("UI", DICOMDataSetBuilder.newUID())
            var inProgress = document.attributes
            inProgress[Tag.state] = Self.attribute("CS", "IN PROGRESS")
            document.attributes[Tag.state] = Self.attribute("CS", "CANCELED")
            var progress: [String: Any] = [Tag.cancelTime: Self.attribute("DT", Self.dateTime())]
            progress[Tag.cancelReasonCode] = reason[Tag.cancelReasonCode] ?? ["vr": "SQ", "Value": [[
                "00080100": Self.attribute("SH", "110513"),
                "00080102": Self.attribute("SH", "DCM"),
                "00080104": Self.attribute("LO", "Discontinued for unspecified reason"),
            ]]]
            if let text = reason[Tag.cancelReason] { progress[Tag.cancelReason] = text }
            document.attributes[Tag.progress] = ["vr": "SQ", "Value": [progress]]
            document.attributes[Tag.modificationTime] = Self.attribute("DT", Self.dateTime())
            do { try await index.replace(document, in: .unifiedProcedureSteps) }
            catch DICOMArchiveError.conflict { return Self.reply(0xC301, "UPS changed concurrently") }
            try await emit(uid: uid, event: 1, object: inProgress)
            try await emit(uid: uid, event: 1, object: document.attributes)
        }
        return DICOMNormalizedResponse(status: .success)
    }

    /// N-ACTION 3/4/5, persisted in the archive index. A global subscription
    /// uses the well-known UID; a specific one uses the UPS SOP Instance UID.
    func subscription(_ uid: String, action: UInt16, object: [String: Any]) async throws -> DICOMNormalizedResponse {
        guard let ae = Self.value(object, Tag.receivingAE), !ae.isEmpty else { return Self.reply(0x0121) }
        let filtered = uid == DICOMSOPClass.upsFilteredGlobalSubscription
        let global = uid == DICOMSOPClass.upsGlobalSubscription || filtered
        if !global {
            guard try await index.document(uid, in: .unifiedProcedureSteps) != nil else { return Self.reply(0xC307) }
        }
        if (action == 5 || action == 4) && filtered { return Self.reply(0xC314) }
        if action == 5 && !global { return Self.reply(0xC314) }
        let id = ae + "|" + uid
        if action == 3 {
            let webConnected = await eventHub.isConnected(ae)
            if !eventReportsSupported && !webConnected { return Self.reply(0xC315) }
            if let receivingAEs, !receivingAEs.contains(ae) && !webConnected { return Self.reply(0xC308) }
            guard let lockValue = Self.value(object, Tag.deletionLock),
                  ["TRUE", "FALSE"].contains(lockValue) else { return Self.reply(0x0121) }
            let lock = lockValue == "TRUE"
            var filter = object
            filter.removeValue(forKey: Tag.receivingAE)
            filter.removeValue(forKey: Tag.deletionLock)
            if filtered && filter.isEmpty { return Self.reply(0x0120, "Matching Keys are required") }
            if filtered, let error = Self.validateQueryKeys(filter) { return Self.reply(0x0106, error) }
            // One global subscription per AE; a new filtered/unfiltered request replaces it.
            if global {
                let otherUID = filtered ? DICOMSOPClass.upsGlobalSubscription : DICOMSOPClass.upsFilteredGlobalSubscription
                _ = try await index.delete(ae + "|" + otherUID, from: .unifiedProcedureStepSubscriptions)
            }
            try await index.save(DICOMArchiveDocument(id: id, attributes: filtered ? filter : [:],
                metadata: ["ae": ae, "uid": uid, "lock": lock ? "TRUE" : "FALSE"]),
                in: .unifiedProcedureStepSubscriptions)
            if global {
                let steps = try await index.documents(in: .unifiedProcedureSteps, matching: DICOMQuery(conditions: []))
                for step in steps where !filtered || DICOMQueryMatcher().match(filter, against: step.attributes) != nil {
                    try await subscribeSpecific(ae: ae, uid: step.id, lock: lock, object: step.attributes,
                                                sendInitial: lock, preserveExisting: true)
                }
            } else if let step = try await index.document(uid, in: .unifiedProcedureSteps) {
                try await emit(to: ae, uid: uid, event: 1, object: step.attributes)
            }
        } else if action == 4 {
            _ = try await index.delete(id, from: .unifiedProcedureStepSubscriptions)
            if global {
                let all = try await index.documents(in: .unifiedProcedureStepSubscriptions,
                                                    matching: DICOMQuery(conditions: []))
                for item in all where item.metadata["ae"] == ae && item.metadata["uid"] != uid {
                    _ = try await index.delete(item.id, from: .unifiedProcedureStepSubscriptions)
                }
            }
        } else if action == 5 {
            for globalUID in [DICOMSOPClass.upsGlobalSubscription, DICOMSOPClass.upsFilteredGlobalSubscription] {
                _ = try await index.delete(ae + "|" + globalUID, from: .unifiedProcedureStepSubscriptions)
            }
        } else { return DICOMNormalizedResponse(status: .noSuchActionType) }
        return DICOMNormalizedResponse(status: .success)
    }

    private func subscribeSpecific(ae: String, uid: String, lock: Bool, object: [String: Any],
                                   sendInitial: Bool = true, preserveExisting: Bool = false) async throws {
        let id = ae + "|" + uid
        if preserveExisting, try await index.document(id, in: .unifiedProcedureStepSubscriptions) != nil { return }
        let subscription = DICOMArchiveDocument(id: id, attributes: [:],
            metadata: ["ae": ae, "uid": uid, "lock": lock ? "TRUE" : "FALSE"])
        if preserveExisting {
            do { try await index.insert(subscription, into: .unifiedProcedureStepSubscriptions) }
            catch DICOMArchiveError.duplicate { return }
        } else {
            try await index.save(subscription, in: .unifiedProcedureStepSubscriptions)
        }
        if sendInitial { try await emit(to: ae, uid: uid, event: 1, object: object) }
    }

    private func applyGlobalSubscriptions(to uid: String, instance: [String: Any]) async throws {
        let subscriptions = try await index.documents(in: .unifiedProcedureStepSubscriptions,
                                                       matching: DICOMQuery(conditions: []))
        for item in subscriptions where [DICOMSOPClass.upsGlobalSubscription,
                                         DICOMSOPClass.upsFilteredGlobalSubscription].contains(item.metadata["uid"] ?? "") {
            guard let ae = item.metadata["ae"] else { continue }
            if item.metadata["uid"] == DICOMSOPClass.upsFilteredGlobalSubscription,
               DICOMQueryMatcher().match(item.attributes, against: instance) == nil { continue }
            try await subscribeSpecific(ae: ae, uid: uid, lock: item.metadata["lock"] == "TRUE", object: instance)
            if Self.hasValue(instance, Tag.stationName) || Self.hasValue(instance, "00404034") {
                try await emit(to: ae, uid: uid, event: 5, object: instance)
            }
        }
    }

    private func emit(uid: String, event: UInt16, object: [String: Any]) async throws {
        let subscriptions = try await index.documents(in: .unifiedProcedureStepSubscriptions,
                                                       matching: DICOMQuery(conditions: []))
        for item in subscriptions where item.metadata["uid"] == uid {
            if let ae = item.metadata["ae"] { try await emit(to: ae, uid: uid, event: event, object: object) }
        }
    }

    private func emit(to ae: String, uid: String, event: UInt16, object: [String: Any]) async throws {
        var report: [String: Any] = [:]
        var source = object
        if event == 5, let performer = Self.items(object, "00404034").first {
            source.merge(performer) { _, nested in nested }
        }
        if event == 1, let progress = Self.items(object, Tag.progress).first {
            source.merge(progress) { _, nested in nested }
        }
        let tags: [String] = event == 1 ? [Tag.state, Tag.readiness, Tag.cancelReason, Tag.cancelReasonCode, Tag.requestingAE]
            : event == 2 ? [Tag.requestingAE, Tag.cancelReason, Tag.cancelReasonCode, "0074100A", "0074100C"]
            : event == 3 ? [Tag.progress]
            : event == 4 ? ["00741242", "00741244", "00741246"]
            : [Tag.stationName, "00404034", "00404009", "00404036"]
        for tag in tags { report[tag] = source[tag] }
        if let charset = object["00080005"] { report["00080005"] = charset }
        let dataSet = try DICOMJSON.dataSet(report)
        try await eventHub.publish(to: ae, uid: uid, type: event, information: dataSet)
        if let notify { await notify(ae, uid, event, dataSet) }
    }

    /// Announces restart/shutdown to subscribers and the application's fallback AEs.
    /// Instances, subscriptions and deletion locks are retained until the host archives them.
    public func reportStatus(restarted: Bool, subscriptionsPreserved: Bool = true,
                             instancesPreserved: Bool = true, fallbackAEs: [String] = []) async throws {
        let subscriptions = try await index.documents(in: .unifiedProcedureStepSubscriptions,
                                                       matching: DICOMQuery(conditions: []))
        let recipients = Set(fallbackAEs + subscriptions.compactMap { $0.metadata["ae"] })
        let information = ["00741242": Self.attribute("CS", restarted ? "RESTARTED" : "GOING DOWN"),
                           "00741244": Self.attribute("CS", subscriptionsPreserved ? "WARM START" : "COLD START"),
                           "00741246": Self.attribute("CS", instancesPreserved ? "WARM START" : "COLD START")]
        for ae in recipients.sorted() {
            try await emit(to: ae, uid: DICOMSOPClass.upsGlobalSubscription, event: 4, object: information)
        }
    }

    /// C-FIND on the UPS Query SOP Class. Candidate selection is delegated to
    /// the adapter and exact matching to the core matcher.
    public func matches(_ identifier: DataSet) async throws -> [DataSet] {
        let keys = try DICOMJSON.object(identifier, options: DICOMJSON.EncodingOptions(numbersAsStrings: true))
        if let error = Self.validateQueryKeys(keys) {
            throw DICOMServiceError(status: .identifierDoesNotMatchSOPClass, comment: error)
        }
        let matcher = DICOMQueryMatcher()
        let documents = try await index.documents(in: .unifiedProcedureSteps,
                                                  matching: DICOMQuery(identifier: keys, matcher: matcher))
        return try documents.compactMap { document in
            var object = document.attributes
            object.removeValue(forKey: Tag.transaction)
            return try matcher.match(keys, against: object).map { try DICOMJSON.dataSet($0) }
        }
    }

    public nonisolated func find(_ identifier: DataSet, informationModel: String,
                                 context: DICOMServiceContext) async throws -> AsyncThrowingStream<DataSet, Error> {
        guard [DICOMSOPClass.upsQuery, DICOMSOPClass.upsPull, DICOMSOPClass.upsWatch]
            .contains(informationModel) else {
            throw DICOMServiceError(status: .identifierDoesNotMatchSOPClass, comment: "not UPS Query")
        }
        let found = try await matches(identifier)
        return AsyncThrowingStream { continuation in
            for item in found { continuation.yield(item) }
            continuation.finish()
        }
    }
}

/// Delivers UPS event reports to AE Titles configured by the application.
public struct DICOMUPSNotifier: Sendable {
    public let client: DICOMClient
    public let recipients: [String: DICOMRemoteNode]

    public init(client: DICOMClient, recipients: [String: DICOMRemoteNode]) {
        self.client = client
        self.recipients = recipients
    }

    public func send(to ae: String, instance uid: String, event: UInt16, information: DataSet) async {
        guard let recipient = recipients[ae] else {
            Logger.warning("UPS event \(event) of \(uid) has no destination for \(ae)")
            return
        }
        let sopClass = DICOMSOPClass.upsEvent
        do {
            try await client.withAssociation(
                to: recipient, presentationContexts: .proposals(abstractSyntaxes: [sopClass]),
                roleSelections: [DICOMRoleSelection(sopClassUID: sopClass, scuRole: false, scpRole: true)]
            ) { association in
                _ = try await association.nEventReport(
                    sopClassUID: DICOMSOPClass.upsPush, sopInstanceUID: uid, eventTypeID: event,
                    information: information, abstractSyntax: sopClass)
            }
        } catch {
            Logger.warning("UPS event \(event) of \(uid) not sent to \(ae): \(error)")
        }
    }
}
