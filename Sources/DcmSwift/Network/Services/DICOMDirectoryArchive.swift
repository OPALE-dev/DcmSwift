import Foundation

/// The instances of a directory, indexed by the attributes of the
/// Query/Retrieve information models (PS3.4 C.6). It backs the storage,
/// query, retrieval, and Storage Commitment services of `DcmServer`, over
/// DIMSE and DICOMweb.
public actor DICOMDirectoryArchive {
    public struct Record: Sendable {
        public var url: URL
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

    public let directory: URL
    private var records: [String: Record] = [:]

    public init(directory: URL) {
        self.directory = directory
    }

    /// Indexes the Part 10 files of the directory; returns their number.
    public func scan() -> Int {
        let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            if let record = try? Self.record(of: url) { records[record.attributes["SOPInstanceUID"] ?? url.path] = record }
        }
        return records.count
    }

    static func record(of url: URL) throws -> Record {
        let header = try DICOMPart10Header.read(url)
        guard let file = DicomFile(forPath: url.path), let dataSet = file.dataset else {
            throw DICOMCommandError("cannot read \(url.lastPathComponent)")
        }
        return record(url: url, header: header, dataSet: dataSet)
    }

    static func record(url: URL, header: DICOMPart10Header, dataSet: DataSet) -> Record {
        var attributes: [String: String] = [:]
        for key in indexedKeys {
            if let values = dataSet.textValues(forTag: key) { attributes[key] = values.joined(separator: "\\") }
        }
        // The data set's UIDs prevail over File Meta Information that
        // disagrees with them.
        if attributes["SOPInstanceUID"]?.isEmpty ?? true { attributes["SOPInstanceUID"] = header.sopInstanceUID }
        if attributes["SOPClassUID"]?.isEmpty ?? true { attributes["SOPClassUID"] = header.sopClassUID }
        return Record(url: url, sopClassUID: attributes["SOPClassUID"] ?? header.sopClassUID,
                      transferSyntaxUID: header.transferSyntaxUID, attributes: attributes)
    }

    /// Writes a received instance and indexes it.
    public func store(_ instance: DICOMReceivedInstance) throws {
        guard DICOMUniqueIdentifier.isValid(instance.sopInstanceUID) else {
            throw DICOMCommandError("invalid SOP Instance UID")
        }
        let url = directory.appendingPathComponent(instance.sopInstanceUID + ".dcm")
        let dataSet = try instance.dataSet()
        try instance.write(to: url)
        let header = try DICOMPart10Header.read(url)
        records[instance.sopInstanceUID] = Self.record(url: url, header: header, dataSet: dataSet)
    }

    /// The record of an instance.
    public func record(_ sopInstanceUID: String) -> Record? {
        records[sopInstanceUID]
    }

    /// The groups of records at `level` matching `identifier`, each the
    /// records of one patient, study, series, or instance, in a stable order.
    public func match(_ identifier: DataSet, level: String) throws -> [[Record]] {
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
        let unique = Self.levels[depth].unique
        var groups: [String: [Record]] = [:]
        var order: [String] = []
        for record in records.values.sorted(by: { $0.url.path < $1.url.path }) {
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
    public func find(_ identifier: DataSet) throws -> [DataSet] {
        let level = identifier.string(forTag: "QueryRetrieveLevel") ?? ""
        let groups = try match(identifier, level: level)
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
/// `DICOMDirectoryArchive`, for DIMSE and for DICOMweb.
public struct DICOMDirectoryArchiveServices: DICOMStorageService, DICOMQueryService, DICOMRetrieveService,
    DICOMStorageCommitmentService, DICOMwebSearchService, DICOMwebRetrieveService, DICOMwebStoreService {
    public let archive: DICOMDirectoryArchive
    /// C-MOVE destinations and Storage Commitment SCUs, by AE title.
    public let destinations: [String: DICOMRemoteNode]
    /// What to do with received instances that do not conform to their IOD.
    public let validation: DICOMIODValidationPolicy

    public init(archive: DICOMDirectoryArchive, destinations: [String: DICOMRemoteNode] = [:],
                validation: DICOMIODValidationPolicy = .off) {
        self.archive = archive
        self.destinations = destinations
        self.validation = validation
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
        guard let warn = admit(instance) else { return .storageDataSetDoesNotMatchSOPClass }
        try await archive.store(instance)
        return warn ? .storageDataSetDoesNotMatchSOPClassWarning : .success
    }

    public func find(
        _ identifier: DataSet, informationModel: String, context: DICOMServiceContext
    ) async throws -> AsyncThrowingStream<DataSet, Error> {
        let matches = try await archive.find(identifier)
        return AsyncThrowingStream { continuation in
            for match in matches { continuation.yield(match) }
            continuation.finish()
        }
    }

    public func retrieve(
        _ identifier: DataSet, informationModel: String, context: DICOMServiceContext
    ) async throws -> [DICOMRetrieveItem] {
        let level = identifier.string(forTag: "QueryRetrieveLevel") ?? ""
        return try await archive.match(identifier, level: level).joined().map { try DICOMRetrieveItem(file: $0.url) }
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
            guard let record = await archive.record(reference.sopInstanceUID),
                  FileManager.default.fileExists(atPath: record.url.path) else {
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
        try await archive.find(identifier)
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
        func key(_ record: DICOMDirectoryArchive.Record) -> (Int, Int, String) {
            let series: Int = Int(record.attributes["SeriesNumber"] ?? "") ?? 0
            let instance: Int = Int(record.attributes["InstanceNumber"] ?? "") ?? 0
            return (series, instance, record.url.path)
        }
        let ordered = records.sorted { key($0) < key($1) }
        return try ordered.map { try DICOMRetrieveItem(file: $0.url) }
    }

    public func store(
        _ instance: DICOMReceivedInstance, context: DICOMwebRequestContext
    ) async throws -> DICOMwebStoreResult {
        guard let warn = admit(instance) else {
            return .failed(DICOMwebStoreResponse.dataSetDoesNotMatchSOPClass)
        }
        do {
            try await archive.store(instance)
            return warn ? .storedWithWarning(DICOMwebStoreResponse.dataSetDoesNotMatchSOPClassWarning) : .stored
        } catch {
            return .failed(DICOMwebStoreResponse.processingFailure)
        }
    }
}
