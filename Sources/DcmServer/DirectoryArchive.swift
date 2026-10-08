import DcmSwift
import Foundation

/// The instances of a directory, indexed by the attributes of the
/// Query/Retrieve information models (PS3.4 C.6).
actor DirectoryArchive {
    struct Record: Sendable {
        var url: URL
        var sopClassUID: String
        var transferSyntaxUID: String
        /// Indexed attributes, by keyword.
        var attributes: [String: String]
    }

    /// Unique keys and indexed attributes per level (PS3.4 C.6.1.1, C.6.2.1).
    static let levels: [(level: String, unique: String, keys: [String])] = [
        ("PATIENT", "PatientID", ["PatientName", "PatientID", "IssuerOfPatientID", "PatientBirthDate", "PatientSex"]),
        ("STUDY", "StudyInstanceUID", ["StudyInstanceUID", "StudyDate", "StudyTime", "AccessionNumber", "StudyID",
                                       "StudyDescription", "ReferringPhysicianName"]),
        ("SERIES", "SeriesInstanceUID", ["SeriesInstanceUID", "Modality", "SeriesNumber", "SeriesDescription"]),
        ("IMAGE", "SOPInstanceUID", ["SOPInstanceUID", "SOPClassUID", "InstanceNumber"]),
    ]
    static let indexedKeys = levels.flatMap(\.keys)

    let directory: URL
    private var records: [String: Record] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    /// Indexes the Part 10 files of the directory; returns their number.
    func scan() -> Int {
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
        attributes["SOPInstanceUID"] = header.sopInstanceUID
        attributes["SOPClassUID"] = header.sopClassUID
        return Record(url: url, sopClassUID: header.sopClassUID, transferSyntaxUID: header.transferSyntaxUID,
                      attributes: attributes)
    }

    /// Writes a received instance and indexes it.
    func store(_ instance: DICOMReceivedInstance) throws {
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
    func record(_ sopInstanceUID: String) -> Record? {
        records[sopInstanceUID]
    }

    /// The groups of records at `level` matching `identifier`, each the
    /// records of one patient, study, series, or instance.
    func match(_ identifier: DataSet, level: String) throws -> [[Record]] {
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
}

/// Storage, query, retrieval, and Storage Commitment over a
/// `DirectoryArchive`.
struct ArchiveServices: DICOMStorageService, DICOMQueryService, DICOMRetrieveService, DICOMStorageCommitmentService {
    let archive: DirectoryArchive
    let destinations: [String: DICOMRemoteNode]

    func store(_ instance: DICOMReceivedInstance, context: DICOMServiceContext) async throws -> DICOMStatus {
        try await archive.store(instance)
        return .success
    }

    func find(
        _ identifier: DataSet, informationModel: String, context: DICOMServiceContext
    ) async throws -> AsyncThrowingStream<DataSet, Error> {
        let level = identifier.string(forTag: "QueryRetrieveLevel") ?? ""
        let groups = try await archive.match(identifier, level: level)
        let requested = identifier.allElements.map(\.name)
        return AsyncThrowingStream { continuation in
            for group in groups {
                let match = DataSet()
                for keyword in requested {
                    if let value = Self.value(of: keyword, in: group, level: level) {
                        _ = match.set(value: value, forTagName: keyword)
                    } else if let element = identifier.element(forTagName: keyword), element.vr != .SQ {
                        // Unsupported keys are returned empty.
                        _ = match.set(value: "", forTagName: keyword)
                    }
                }
                continuation.yield(match)
            }
            continuation.finish()
        }
    }

    /// A return key: an indexed attribute or a count of the group.
    static func value(of keyword: String, in group: [DirectoryArchive.Record], level: String) -> String? {
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

    func retrieve(
        _ identifier: DataSet, informationModel: String, context: DICOMServiceContext
    ) async throws -> [DICOMRetrieveItem] {
        let level = identifier.string(forTag: "QueryRetrieveLevel") ?? ""
        return try await archive.match(identifier, level: level).joined().map { try DICOMRetrieveItem(file: $0.url) }
    }

    func destination(for aeTitle: String) async -> DICOMRemoteNode? {
        destinations[aeTitle]
    }

    /// Commits the instances in the directory (PS3.4 J.3.3.2).
    func commit(
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
}
