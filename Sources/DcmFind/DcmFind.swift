//
//  DcmFind.swift
//
//
//  Created by Paul on 30/06/2021.
//

import ArgumentParser
import DcmNetworkCommand
import DcmSwift
import Foundation

/// `DcmFind` is a Query/Retrieve SCU for C-FIND (PS3.4 C.4.1).
@main
struct DcmFind: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Query a remote AE with C-FIND (Query/Retrieve SCU).",
        discussion: """
            Keys are attribute keywords or tags (gggg,eeee), with an optional matching value: \
            -k PatientName=DOE* -k StudyDate=20240101-20241231 -k ModalitiesInStudy. A key inside a \
            sequence is written Sequence[0].Keyword, as -k 'ScheduledProcedureStepSequence[0].Modality=CT'. \
            Without keys, the usual attributes of the level, or of a worklist item with -m worklist, are \
            requested. Exits with status 1 on failure.
            """)

    enum Level: String, ExpressibleByArgument, CaseIterable {
        case patient = "PATIENT", study = "STUDY", series = "SERIES", image = "IMAGE"

        init?(argument: String) { self.init(rawValue: argument.uppercased()) }
    }

    enum Model: String, ExpressibleByArgument, CaseIterable {
        case study, patient, patientStudyOnly = "patient-study-only", worklist

        var findSOPClass: String {
            switch self {
            case .worklist: return DICOMSOPClass.modalityWorklistFind
            case .study: return DICOMSOPClass.studyRootFind
            case .patient: return DICOMSOPClass.patientRootFind
            case .patientStudyOnly: return DICOMSOPClass.patientStudyOnlyFind
            }
        }
    }

    @OptionGroup var remote: RemoteOptions

    @Option(name: .shortAndLong, help: "Query/Retrieve Level: PATIENT, STUDY, SERIES, or IMAGE.")
    var level: Level = .study

    @Option(name: .shortAndLong, help: "Information model: study, patient, patient-study-only, or worklist (Modality Worklist; default: patient for PATIENT, else study).")
    var model: Model?

    @Option(name: .shortAndLong, help: "A matching or return key, as Keyword[=value] or gggg,eeee[=value].")
    var key: [String] = []

    @Option(name: .long, help: "Stop after this many matches (sends C-CANCEL).")
    var limit: Int?

    @OptionGroup var network: NetworkOptions
    @OptionGroup var tls: ClientTLSOptions

    func validate() throws {
        if let limit, limit < 1 { throw ValidationError("--limit must be at least 1") }
        if level == .patient, model == .study { throw ValidationError("the study root model has no PATIENT level") }
        _ = try identifier()
    }

    /// Return keys requested when none is given (PS3.4 C.6.1.1 and C.6.2.1).
    static func defaultKeys(_ level: Level) -> [String] {
        switch level {
        case .patient: return ["PatientName", "PatientID", "PatientBirthDate", "PatientSex", "NumberOfPatientRelatedStudies"]
        case .study: return ["PatientName", "PatientID", "StudyInstanceUID", "StudyDate", "StudyTime", "AccessionNumber",
                             "StudyID", "StudyDescription", "ModalitiesInStudy", "NumberOfStudyRelatedInstances"]
        case .series: return ["StudyInstanceUID", "SeriesInstanceUID", "Modality", "SeriesNumber", "SeriesDescription",
                              "NumberOfSeriesRelatedInstances"]
        case .image: return ["StudyInstanceUID", "SeriesInstanceUID", "SOPInstanceUID", "SOPClassUID", "InstanceNumber"]
        }
    }

    /// Return keys of a worklist query without keys (PS3.4 Table K.6-1).
    static let worklistKeys = [
        "PatientName", "PatientID", "PatientBirthDate", "PatientSex", "AccessionNumber", "RequestedProcedureID",
        "RequestedProcedureDescription", "StudyInstanceUID",
    ] + ["ScheduledStationAETitle", "ScheduledProcedureStepStartDate", "ScheduledProcedureStepStartTime", "Modality",
         "ScheduledPerformingPhysicianName", "ScheduledProcedureStepDescription", "ScheduledProcedureStepID",
         "ScheduledStationName"].map { "ScheduledProcedureStepSequence[0].\($0)" }

    func identifier() throws -> DataSet {
        let worklist = model == .worklist
        do {
            let keys = try (key.isEmpty ? (worklist ? Self.worklistKeys : Self.defaultKeys(level)) : key).map { try DICOMQueryKey($0) }
            return try DICOMQueryKey.identifier(keys, level: worklist ? nil : level.rawValue)
        } catch {
            throw ValidationError("invalid keys: \(error)")
        }
    }

    func run() async throws {
        let identifier = try identifier()
        let informationModel = (model ?? (level == .patient ? .patient : .study)).findSOPClass
        let client = try DICOMClient(configuration: DICOMClientConfiguration(
            aeTitle: remote.callingAET, limits: network.limits, timeouts: network.timeouts,
            tls: try tls.configuration(), logger: network.logger(label: "dcmfind")))
        do {
            let count = try await client.withAssociation(
                to: remote.node(tls: tls.tls), presentationContexts: .proposals(abstractSyntaxes: [informationModel])
            ) { association in
                var count = 0
                for try await match in association.find(identifier, informationModel: informationModel) {
                    count += 1
                    print("# Match \(count)")
                    print(Self.format(match))
                    if let limit, count >= limit { break }
                }
                return count
            }
            print("C-FIND \(remote.description): \(count) match\(count == 1 ? "" : "es")"
                  + (limit.map { count >= $0 ? " (stopped at --limit \($0))" : "" } ?? ""))
        } catch {
            printError("C-FIND \(remote.description) failed: \(error.commandLineDescription)")
            throw ExitCode.failure
        }
    }

    /// One `(gggg,eeee) Keyword: value` line per attribute; the attributes
    /// of sequence Items follow, indented with `>`.
    static func format(_ dataSet: DataSet) -> String {
        format(dataSet.allElements, depth: 0).joined(separator: "\n")
    }

    static func format(_ elements: [DataElement], depth: Int) -> [String] {
        let prefix = String(repeating: ">", count: depth)
        return elements.flatMap { element -> [String] in
            if let sequence = element as? DataSequence {
                return ["\(prefix)\(element.tag) \(element.name): \(sequence.items.count) Item(s)"]
                    + sequence.items.flatMap { format($0.elements, depth: depth + 1) }
            }
            let value = element.textValues?.joined(separator: "\\") ?? "\(element.value)"
            return ["\(prefix)\(element.tag) \(element.name): \(value)"]
        }
    }
}
