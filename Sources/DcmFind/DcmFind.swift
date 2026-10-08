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
            -k PatientName=DOE* -k StudyDate=20240101-20241231 -k ModalitiesInStudy. Without keys, \
            the usual attributes of the level are requested. Exits with status 1 on failure.
            """)

    enum Level: String, ExpressibleByArgument, CaseIterable {
        case patient = "PATIENT", study = "STUDY", series = "SERIES", image = "IMAGE"

        init?(argument: String) { self.init(rawValue: argument.uppercased()) }
    }

    enum Model: String, ExpressibleByArgument, CaseIterable {
        case study, patient, patientStudyOnly = "patient-study-only"

        var findSOPClass: String {
            switch self {
            case .study: return DICOMSOPClass.studyRootFind
            case .patient: return DICOMSOPClass.patientRootFind
            case .patientStudyOnly: return DICOMSOPClass.patientStudyOnlyFind
            }
        }
    }

    @OptionGroup var remote: RemoteOptions

    @Option(name: .shortAndLong, help: "Query/Retrieve Level: PATIENT, STUDY, SERIES, or IMAGE.")
    var level: Level = .study

    @Option(name: .shortAndLong, help: "Information model: study, patient, or patient-study-only (default: patient for PATIENT, else study).")
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

    func identifier() throws -> DataSet {
        let identifier = DataSet()
        _ = identifier.set(value: level.rawValue, forTagName: "QueryRetrieveLevel")
        for key in key.isEmpty ? Self.defaultKeys(level) : key {
            let parts = key.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = try Self.keyword(String(parts[0]))
            let value = parts.count > 1 ? String(parts[1]) : ""
            guard identifier.set(value: value, forTagName: name) != nil else {
                throw ValidationError("cannot set \(name) to \"\(value)\"")
            }
        }
        return identifier
    }

    /// A keyword, from a keyword or a gggg,eeee tag.
    static func keyword(_ key: String) throws -> String {
        let hex = key.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        if hex.count == 8, hex.allSatisfy(\.isHexDigit) {
            guard let name = DicomSpec.shared.nameForTag(withCode: hex.lowercased()) else {
                throw ValidationError("unknown tag \(key)")
            }
            return name
        }
        guard DicomSpec.shared.dataTag(forName: key) != nil else { throw ValidationError("unknown keyword \(key)") }
        return key
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

    /// One `(gggg,eeee) Keyword: value` line per attribute.
    static func format(_ dataSet: DataSet) -> String {
        dataSet.allElements.map { element -> String in
            let value = dataSet.textValues(forTag: element.name)?.joined(separator: "\\") ?? "\(element.value)"
            return "\(element.tag) \(element.name): \(value)"
        }.joined(separator: "\n")
    }
}
