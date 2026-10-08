//
//  DcmAnonymize.swift
//
//
//  Created by Rafael Warnault, OPALE on 23/06/2021.
//

import Foundation
import DcmSwift
import ArgumentParser

struct DcmAnonymize: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "De-identify DICOM files with the Basic Application Level Confidentiality Profile of PS3.15.",
        discussion: """
            SOURCE is a file or a directory; with a directory, every DICOM file under it is \
            written under DESTINATION with the same relative path. Files de-identified with \
            the same --key keep consistent UIDs, so studies stay whole across runs.
            """)

    @Argument(help: "DICOM file, or directory of DICOM files, to de-identify")
    var sourcePath: String

    @Argument(help: "Path of the de-identified file, or directory of the de-identified files")
    var destPath: String

    @Option(help: "File holding the secret from which replacement UIDs and the date shift derive (default: a random secret)")
    var key: String?

    @Option(help: "Days added to dates with --retain-modified-dates (default: derived from the key)")
    var dateShift: Int?

    @Flag(help: "Retain Safe Private Option: keep the private attributes PS3.15 lists as safe")
    var retainSafePrivate = false

    @Flag(name: .customLong("retain-uids"), help: "Retain UIDs Option")
    var retainUIDs = false

    @Flag(help: "Retain Device Identity Option")
    var retainDeviceIdentity = false

    @Flag(help: "Retain Institution Identity Option")
    var retainInstitutionIdentity = false

    @Flag(help: "Retain Patient Characteristics Option")
    var retainPatientCharacteristics = false

    @Flag(help: "Retain Longitudinal Temporal Information with Full Dates Option")
    var retainFullDates = false

    @Flag(help: "Retain Longitudinal Temporal Information with Modified Dates Option: shift dates")
    var retainModifiedDates = false

    mutating func run() throws {
        var options: DICOMDeidentificationOptions = []
        if retainSafePrivate { options.insert(.retainSafePrivate) }
        if retainUIDs { options.insert(.retainUIDs) }
        if retainDeviceIdentity { options.insert(.retainDeviceIdentity) }
        if retainInstitutionIdentity { options.insert(.retainInstitutionIdentity) }
        if retainPatientCharacteristics { options.insert(.retainPatientCharacteristics) }
        if retainFullDates { options.insert(.retainLongitudinalFullDates) }
        if retainModifiedDates { options.insert(.retainLongitudinalModifiedDates) }
        let secret = try key.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
        let deidentifier = try DICOMDeidentifier(options: options, key: secret, dateShift: dateShift)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourcePath, isDirectory: &isDirectory) else {
            throw ValidationError("\(sourcePath) does not exist")
        }
        let pairs: [(String, String)]
        if isDirectory.boolValue {
            let base = URL(fileURLWithPath: sourcePath).standardizedFileURL
            let enumerator = FileManager.default.enumerator(
                at: base, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            var found: [(String, String)] = []
            while let url = enumerator?.nextObject() as? URL {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                let relative = String(url.standardizedFileURL.path.dropFirst(base.path.count + 1))
                found.append((url.path, URL(fileURLWithPath: destPath).appendingPathComponent(relative).path))
            }
            pairs = found.sorted { $0.0 < $1.0 }
        } else {
            pairs = [(sourcePath, destPath)]
        }

        var failures = 0
        for (source, destination) in pairs {
            guard let file = DicomFile(forPath: source), let dataSet = file.dataset else {
                Logger.error("Cannot read \(source) as DICOM")
                failures += 1
                continue
            }
            deidentifier.deidentify(dataSet)
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: destination).deletingLastPathComponent(), withIntermediateDirectories: true)
            if !file.write(atPath: destination) {
                Logger.error("Cannot write \(destination)")
                failures += 1
            }
        }
        if failures > 0 { throw ExitCode.failure }
    }
}

DcmAnonymize.main()
