import Foundation

/// The instances of an archive, indexed by the attributes of the
/// Query/Retrieve information models (PS3.4 C.6): their index entries are
/// documents of the `instances` collection of a `DICOMArchiveIndex`, their
/// bytes are kept by a `DICOMInstanceStore`. It backs the storage, query,
/// retrieval, and Storage Commitment services of `DcmServer`, over DIMSE and
/// DICOMweb.
public actor DICOMArchive {
    public struct Record: Sendable {
        /// The location of the instance in the store.
        public var location: String
        public var sopClassUID: String
        public var transferSyntaxUID: String
        /// Indexed attributes, by keyword.
        public var attributes: [String: String]
    }

    /// Unique keys and indexed attributes per level (PS3.4 C.6.1.1, C.6.2.1).
    static let levels: [(level: String, unique: String, keys: [String])] = [
        ("PATIENT", "PatientID", ["PatientName", "PatientID", "IssuerOfPatientID", "PatientBirthDate", "PatientSex"]),
        ("STUDY", "StudyInstanceUID", ["StudyInstanceUID", "StudyDate", "StudyTime", "AccessionNumber", "StudyID",
                                       "StudyDescription", "ReferringPhysicianName"]),
        ("SERIES", "SeriesInstanceUID", ["SeriesInstanceUID", "Modality", "SeriesNumber", "SeriesDescription"]),
        ("IMAGE", "SOPInstanceUID", ["SOPInstanceUID", "SOPClassUID", "InstanceNumber", "Rows", "Columns",
                                     "BitsAllocated", "NumberOfFrames"]),
    ]
    static let indexedKeys = levels.flatMap(\.keys)
    /// Indexed keywords by tag (8 upper-case hexadecimal digits), and back.
    static let tags: [String: String] = Dictionary(uniqueKeysWithValues: indexedKeys.map {
        ($0, DicomSpec.shared.dataTag(forName: $0)!.code.uppercased())
    })
    static let keywords: [String: String] = Dictionary(uniqueKeysWithValues: tags.map { ($1, $0) })

    public nonisolated let index: DICOMArchiveIndex
    public nonisolated let store: DICOMInstanceStore

    public init(index: DICOMArchiveIndex = DICOMMemoryArchiveIndex(), store: DICOMInstanceStore) {
        self.index = index
        self.store = store
    }

    /// An archive of the Part 10 files of a directory, indexed in memory
    /// (call `scan()` to index the files already there).
    public init(directory: URL) {
        self.init(store: DICOMFileInstanceStore(directory: directory))
    }

    /// Indexes the Part 10 files of a `DICOMFileInstanceStore`; returns the
    /// number of instances indexed.
    public func scan() async throws -> Int {
        guard let files = store as? DICOMFileInstanceStore else { return 0 }
        var count = 0
        for url in files.files() {
            guard let record = try? Self.record(of: url) else { continue }
            try await index.save(Self.document(record), in: .instances)
            count += 1
        }
        return count
    }

    static func record(of url: URL) throws -> Record {
        let header = try DICOMPart10Header.read(url)
        guard let file = DicomFile(forPath: url.path), let dataSet = file.dataset else {
            throw DICOMCommandError("cannot read \(url.lastPathComponent)")
        }
        return record(location: url.path, header: header, dataSet: dataSet)
    }

    static func record(location: String, header: DICOMPart10Header, dataSet: DataSet) -> Record {
        var attributes: [String: String] = [:]
        for key in indexedKeys {
            if let values = dataSet.textValues(forTag: key) { attributes[key] = values.joined(separator: "\\") }
        }
        // The data set's UIDs prevail over File Meta Information that
        // disagrees with them.
        if attributes["SOPInstanceUID"]?.isEmpty ?? true { attributes["SOPInstanceUID"] = header.sopInstanceUID }
        if attributes["SOPClassUID"]?.isEmpty ?? true { attributes["SOPClassUID"] = header.sopClassUID }
        return Record(location: location, sopClassUID: attributes["SOPClassUID"] ?? header.sopClassUID,
                      transferSyntaxUID: header.transferSyntaxUID, attributes: attributes)
    }

    /// The index document of a record: its attributes in the DICOM JSON
    /// Model, its location and transfer syntax as metadata.
    static func document(_ record: Record) -> DICOMArchiveDocument {
        var attributes: [String: Any] = [:]
        for (keyword, value) in record.attributes {
            guard let tag = tags[keyword] else { continue }
            let vr = DicomSpec.shared.vrForTag(withCode: tag.lowercased()).map { "\($0)" } ?? "UN"
            let values = value.isEmpty ? [] : value.components(separatedBy: "\\")
            if vr == "PN" {
                attributes[tag] = ["vr": vr, "Value": values.map { name -> [String: String] in
                    var groups: [String: String] = [:]
                    for (offset, group) in name.split(separator: "=", omittingEmptySubsequences: false).prefix(3).enumerated()
                    where !group.isEmpty {
                        groups[["Alphabetic", "Ideographic", "Phonetic"][offset]] = String(group)
                    }
                    return groups
                }]
            } else {
                attributes[tag] = values.isEmpty ? ["vr": vr] : ["vr": vr, "Value": values]
            }
        }
        return DICOMArchiveDocument(
            id: record.attributes["SOPInstanceUID"] ?? record.location, attributes: attributes,
            metadata: ["location": record.location, "sopClassUID": record.sopClassUID,
                       "transferSyntaxUID": record.transferSyntaxUID])
    }

    static func record(_ document: DICOMArchiveDocument) -> Record {
        var attributes: [String: String] = [:]
        for (tag, value) in document.attributes {
            guard let keyword = keywords[tag], let attribute = value as? [String: Any] else { continue }
            attributes[keyword] = DICOMQueryMatcher.strings(attribute).joined(separator: "\\")
        }
        return Record(location: document.metadata["location"] ?? "", sopClassUID: document.metadata["sopClassUID"] ?? "",
                      transferSyntaxUID: document.metadata["transferSyntaxUID"] ?? "", attributes: attributes)
    }

    /// Writes a received instance and indexes it; returns its record.
    @discardableResult
    public func store(_ instance: DICOMReceivedInstance) async throws -> Record {
        let dataSet = try instance.dataSet()
        let location = try await store.write(instance)
        let header = DICOMPart10Header(
            sopClassUID: instance.sopClassUID, sopInstanceUID: instance.sopInstanceUID,
            transferSyntaxUID: instance.transferSyntaxUID, dataSetOffset: 0, dataSetLength: 0)
        let record = Self.record(location: location, header: header, dataSet: dataSet)
        try await index.save(Self.document(record), in: .instances)
        return record
    }

    /// The record of an instance.
    public func record(_ sopInstanceUID: String) async throws -> Record? {
        try await index.document(sopInstanceUID, in: .instances).map(Self.record)
    }

    /// The instance of a record, to send.
    public func item(_ record: Record) async throws -> DICOMRetrieveItem {
        try await store.item(at: record.location)
    }

    /// The groups of records at `level` matching `identifier`, each the
    /// records of one patient, study, series, or instance, in a stable order.
    public func match(_ identifier: DataSet, level: String) async throws -> [[Record]] {
        guard let depth = Self.levels.firstIndex(where: { $0.level == level }) else {
            throw DICOMCommandError("unknown Query/Retrieve Level \(level)")
        }
        // Keys of this level and the levels above it take part in matching.
        let keys = Self.levels[...depth].flatMap(\.keys)
        var conditions: [(String, String)] = []
        for key in keys {
            guard let values = identifier.textValues(forTag: key) else { continue }
            let value = values.joined(separator: "\\")
            if !value.isEmpty, value != "*" { conditions.append((key, value)) }
        }
        // The index is asked for the candidates of these keys only.
        let allowed = Set(keys.compactMap { Self.tags[$0] })
        let query = DICOMQuery(conditions: try DICOMQuery(identifier: identifier).conditions.filter {
            $0.path.count == 1 && allowed.contains($0.path[0])
        })
        let candidates = try await index.documents(in: .instances, matching: query).map(Self.record)
        let unique = Self.levels[depth].unique
        var groups: [String: [Record]] = [:]
        var order: [String] = []
        for record in candidates.sorted(by: { $0.location < $1.location }) {
            guard conditions.allSatisfy({ key, value in
                DICOMQueryMatching.matches(record.attributes[key] ?? "", key: value, keyword: key)
            }) else { continue }
            let id = record.attributes[unique] ?? ""
            if groups[id] == nil { order.append(id) }
            groups[id, default: []].append(record)
        }
        return order.map { groups[$0]! }
    }

    /// The matches of a C-FIND identifier, with its return keys filled.
    public func find(_ identifier: DataSet) async throws -> [DataSet] {
        let level = identifier.string(forTag: "QueryRetrieveLevel") ?? ""
        let groups = try await match(identifier, level: level)
        let requested = identifier.allElements.map(\.name)
        return groups.map { group in
            let match = DataSet()
            for keyword in requested {
                if let value = Self.value(of: keyword, in: group, level: level) {
                    _ = match.set(value: value, forTagName: keyword)
                } else if let element = identifier.element(forTagName: keyword), element.vr != .SQ {
                    // Unsupported keys are returned empty.
                    _ = match.set(value: "", forTagName: keyword)
                }
            }
            return match
        }
    }

    /// A return key: an indexed attribute or a count of the group.
    static func value(of keyword: String, in group: [Record], level: String) -> String? {
        switch keyword {
        case "QueryRetrieveLevel": return level
        case "SpecificCharacterSet": return nil
        case "NumberOfStudyRelatedInstances", "NumberOfSeriesRelatedInstances", "NumberOfPatientRelatedInstances":
            return String(group.count)
        case "NumberOfStudyRelatedSeries", "NumberOfPatientRelatedSeries":
            return String(Set(group.compactMap { $0.attributes["SeriesInstanceUID"] }).count)
        case "NumberOfPatientRelatedStudies":
            return String(Set(group.compactMap { $0.attributes["StudyInstanceUID"] }).count)
        case "ModalitiesInStudy":
            return Array(Set(group.compactMap { $0.attributes["Modality"] })).sorted().joined(separator: "\\")
        case "SOPClassesInStudy":
            return Array(Set(group.map(\.sopClassUID))).sorted().joined(separator: "\\")
        default:
            return group.first?.attributes[keyword]
        }
    }
}

/// Storage, query, retrieval, and Storage Commitment over a
/// `DICOMArchive`, for DIMSE and for DICOMweb.
public struct DICOMArchiveServices: DICOMStorageService, DICOMQueryService, DICOMRetrieveService,
    DICOMStorageCommitmentService, DICOMwebSearchService, DICOMwebRetrieveService, DICOMwebStoreService {
    public let archive: DICOMArchive
    /// C-MOVE destinations and Storage Commitment SCUs, by AE title.
    public let destinations: [String: DICOMRemoteNode]
    /// What to do with received instances that do not conform to their IOD.
    public let validation: DICOMIODValidationPolicy
    /// Receives the audit messages of storage, query, and retrieval (PS3.15
    /// A.5.3): DICOM Instances Transferred, Query, Begin Transferring DICOM
    /// Instances.
    public let audit: DICOMAuditRecorder?
    public let auditSource: DICOMAuditSource
    /// Notified of each instance stored, for Instance Availability
    /// Notification.
    public let availability: DICOMInstanceAvailabilityNotifier?

    public init(archive: DICOMArchive, destinations: [String: DICOMRemoteNode] = [:],
                validation: DICOMIODValidationPolicy = .off, audit: DICOMAuditRecorder? = nil,
                auditSource: DICOMAuditSource = DICOMAuditSource(id: "DcmSwift"),
                availability: DICOMInstanceAvailabilityNotifier? = nil) {
        self.availability = availability
        self.archive = archive
        self.destinations = destinations
        self.validation = validation
        self.audit = audit
        self.auditSource = auditSource
    }

    // MARK: Audit

    /// DICOM Instances Transferred for a received instance: created when the
    /// archive did not hold it, read otherwise.
    private func auditReceived(_ instance: DICOMReceivedInstance, existed: Bool, stored: Bool,
                               sender: DICOMAuditMessage.ActiveParticipant,
                               receiver: DICOMAuditMessage.ActiveParticipant) async {
        guard let audit else { return }
        let objects = (try? instance.dataSet()).map(DICOMAuditMessage.objects(of:))
            ?? (.study(uid: "unknown", sopClasses: [.init(uid: instance.sopClassUID, numberOfInstances: 1)]),
                .patient(id: "unknown", name: "unknown"))
        await audit.record(.instancesTransferred(
            action: existed ? .read : .create, sender: sender, receiver: receiver, studies: [objects.study],
            patient: objects.patient, source: auditSource, outcome: stored ? .success : .minorFailure))
    }

    private func local(_ aeTitle: String, isRequestor: Bool = false) -> DICOMAuditMessage.ActiveParticipant {
        .application(aeTitles: [aeTitle], isRequestor: isRequestor)
    }

    private func remote(_ context: DICOMServiceContext) -> DICOMAuditMessage.ActiveParticipant {
        .node(aeTitle: context.callingAETitle, host: DICOMAuditMessage.host(of: context.remoteAddress), isRequestor: true)
    }

    private func remote(_ context: DICOMwebRequestContext) -> DICOMAuditMessage.ActiveParticipant {
        let host = DICOMAuditMessage.host(of: context.remoteAddress)
        return .node(aeTitle: "", host: host, isRequestor: true)
    }

    /// Validates a received instance as the policy says; true when it is to
    /// be stored with a warning, false when it conforms, and nil when it is
    /// refused.
    private func admit(_ instance: DICOMReceivedInstance) -> Bool? {
        guard let report = validation.report(for: instance) else { return false }
        Logger.warning("\(instance.sopInstanceUID) does not conform to the \(report.iod ?? "IOD"): "
            + report.findings.map(\.description).joined(separator: "; "))
        return validation == .reject ? nil : true
    }

    // MARK: DIMSE

    public func store(_ instance: DICOMReceivedInstance, context: DICOMServiceContext) async throws -> DICOMStatus {
        let existed = audit != nil ? try await archive.record(instance.sopInstanceUID) != nil : false
        guard let warn = admit(instance) else {
            await auditReceived(instance, existed: existed, stored: false, sender: remote(context),
                                receiver: local(context.calledAETitle))
            return .storageDataSetDoesNotMatchSOPClass
        }
        do {
            let record = try await archive.store(instance)
            await availability?.stored(record)
        } catch {
            await auditReceived(instance, existed: existed, stored: false, sender: remote(context),
                                receiver: local(context.calledAETitle))
            throw error
        }
        await auditReceived(instance, existed: existed, stored: true, sender: remote(context),
                            receiver: local(context.calledAETitle))
        return warn ? .storageDataSetDoesNotMatchSOPClassWarning : .success
    }

    public func find(
        _ identifier: DataSet, informationModel: String, context: DICOMServiceContext
    ) async throws -> AsyncThrowingStream<DataSet, Error> {
        let matches = try await archive.find(identifier)
        if let audit {
            let syntax = context.presentationContext.transferSyntax
            await audit.record(.query(
                issuer: remote(context), responder: local(context.calledAETitle), sopClassUID: informationModel,
                query: (try? DICOMDataSetCoding.encode(identifier, transferSyntax: syntax)) ?? Data(),
                transferSyntaxUID: syntax, source: auditSource))
        }
        return AsyncThrowingStream { continuation in
            for match in matches { continuation.yield(match) }
            continuation.finish()
        }
    }

    public func retrieve(
        _ identifier: DataSet, informationModel: String, context: DICOMServiceContext
    ) async throws -> [DICOMRetrieveItem] {
        let level = identifier.string(forTag: "QueryRetrieveLevel") ?? ""
        let records = Array(try await archive.match(identifier, level: level).joined())
        if let audit, !records.isEmpty {
            // C-MOVE sends to the Move Destination, C-GET to the requestor.
            let receiver: DICOMAuditMessage.ActiveParticipant
            var others: [DICOMAuditMessage.ActiveParticipant] = []
            if let destination = context.moveDestination {
                receiver = .node(aeTitle: destination, host: destinations[destination]?.host, isRequestor: false)
                others = [remote(context)]
            } else {
                receiver = remote(context)
            }
            let objects = DICOMAuditMessage.objects(of: records)
            let patients = objects.filter { $0.idType == .patientNumber }
            await audit.record(.beginTransferring(
                sender: local(context.calledAETitle), receiver: receiver, others: others,
                studies: objects.filter { $0.idType != .patientNumber },
                patient: patients.first ?? .patient(id: "unknown", name: "unknown"), source: auditSource))
        }
        var items: [DICOMRetrieveItem] = []
        for record in records { items.append(try await archive.item(record)) }
        return items
    }

    public func destination(for aeTitle: String) async -> DICOMRemoteNode? {
        destinations[aeTitle]
    }

    /// Commits the instances in the directory (PS3.4 J.3.3.2).
    public func commit(
        _ request: DICOMStorageCommitmentRequest, context: DICOMServiceContext
    ) async throws -> DICOMStorageCommitmentResult {
        var result = DICOMStorageCommitmentResult(
            transactionUID: request.transactionUID, committed: [], retrieveAETitle: context.calledAETitle)
        for reference in request.references {
            guard let record = try await archive.record(reference.sopInstanceUID),
                  await archive.store.exists(record.location) else {
                result.failed.append(.init(reference: reference, reason: DICOMStorageCommitmentResult.FailureReason.noSuchSOPInstance))
                continue
            }
            if record.sopClassUID == reference.sopClassUID {
                result.committed.append(reference)
            } else {
                result.failed.append(.init(
                    reference: reference, reason: DICOMStorageCommitmentResult.FailureReason.classInstanceConflict))
            }
        }
        return result
    }

    // MARK: DICOMweb

    public func search(
        _ identifier: DataSet, level: DICOMwebSearchLevel, query: DICOMwebSearchQuery, context: DICOMwebRequestContext
    ) async throws -> [DataSet] {
        let matches = try await archive.find(identifier)
        if let audit {
            // QIDO-RS searches the Study Root information model.
            await audit.record(.query(
                issuer: remote(context), responder: local(auditSource.id),
                sopClassUID: "1.2.840.10008.5.1.4.1.2.2.1",
                query: (try? DICOMDataSetCoding.encode(identifier, transferSyntax: TransferSyntax.explicitVRLittleEndian)) ?? Data(),
                transferSyntaxUID: TransferSyntax.explicitVRLittleEndian, source: auditSource))
        }
        return matches
    }

    public func instances(
        study: String, series: String?, instance: String?, context: DICOMwebRequestContext
    ) async throws -> [DICOMRetrieveItem] {
        let identifier = DataSet()
        _ = identifier.set(value: study, forTagName: "StudyInstanceUID")
        if let series { _ = identifier.set(value: series, forTagName: "SeriesInstanceUID") }
        if let instance { _ = identifier.set(value: instance, forTagName: "SOPInstanceUID") }
        let level = instance != nil ? "IMAGE" : series != nil ? "SERIES" : "STUDY"
        let records = try await archive.match(identifier, level: level).joined()
        // Instances in series and instance number order.
        func key(_ record: DICOMArchive.Record) -> (Int, Int, String) {
            let series: Int = Int(record.attributes["SeriesNumber"] ?? "") ?? 0
            let instance: Int = Int(record.attributes["InstanceNumber"] ?? "") ?? 0
            return (series, instance, record.location)
        }
        let ordered = records.sorted { key($0) < key($1) }
        if let audit, !ordered.isEmpty {
            // WADO-RS sends copies to the user agent.
            let objects = DICOMAuditMessage.objects(of: ordered)
            let patients = objects.filter { $0.idType == .patientNumber }
            await audit.record(.instancesTransferred(
                action: .read, sender: local(auditSource.id), receiver: remote(context),
                studies: objects.filter { $0.idType != .patientNumber },
                patient: patients.first ?? .patient(id: "unknown", name: "unknown"), source: auditSource))
        }
        var items: [DICOMRetrieveItem] = []
        for record in ordered { items.append(try await archive.item(record)) }
        return items
    }

    public func store(
        _ instance: DICOMReceivedInstance, context: DICOMwebRequestContext
    ) async throws -> DICOMwebStoreResult {
        let existed = audit != nil ? try await archive.record(instance.sopInstanceUID) != nil : false
        guard let warn = admit(instance) else {
            await auditReceived(instance, existed: existed, stored: false, sender: remote(context),
                                receiver: local(auditSource.id))
            return .failed(DICOMwebStoreResponse.dataSetDoesNotMatchSOPClass)
        }
        do {
            let record = try await archive.store(instance)
            await availability?.stored(record)
            await auditReceived(instance, existed: existed, stored: true, sender: remote(context),
                                receiver: local(auditSource.id))
            return warn ? .storedWithWarning(DICOMwebStoreResponse.dataSetDoesNotMatchSOPClassWarning) : .stored
        } catch {
            await auditReceived(instance, existed: existed, stored: false, sender: remote(context),
                                receiver: local(auditSource.id))
            return .failed(DICOMwebStoreResponse.processingFailure)
        }
    }
}
