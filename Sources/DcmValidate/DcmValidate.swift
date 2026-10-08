//
//  DcmValidate.swift
//
//  Validates DICOM files against the IODs of PS3.3.
//

import Foundation
import DcmSwift
import ArgumentParser

@main
struct DcmValidate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Validate DICOM files against the IODs of PS3.3 \(DICOMIODSpecification.shared.edition).",
        discussion: """
            Reports, for each file, the attributes its IOD requires that are missing or \
            empty, and the values outside the Enumerated Values, with the PS3.3 table \
            that defines them. Exits with 1 when a file has findings or cannot be read.
            """)

    @Argument(help: "DICOM files, or directories of DICOM files")
    var paths: [String]

    @Flag(name: .shortAndLong, help: "Also validate the files of subdirectories")
    var recursive: Bool = false

    @Flag(name: .shortAndLong, help: "Print only the files with findings")
    var quiet: Bool = false

    mutating func run() throws {
        let validator = DICOMIODValidator()
        var failed = false
        for path in files() {
            guard let file = DicomFile(forPath: path), let dataSet = file.dataset else {
                print("\(path): cannot be read as DICOM")
                failed = true
                continue
            }
            let report = validator.validate(dataSet)
            if report.isValid {
                if !quiet { print("\(path): valid \(report.iod ?? "")") }
                continue
            }
            failed = true
            print("\(path): \(report.findings.count) finding(s) against \(report.iod ?? "an unknown IOD")")
            for finding in report.findings { print("  \(finding)") }
        }
        if failed { throw ExitCode.failure }
    }

    private func files() -> [String] {
        var result: [String] = []
        let manager = FileManager.default
        for path in paths {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                result.append(path)
                continue
            }
            let base = URL(fileURLWithPath: path)
            if recursive {
                let enumerator = manager.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey],
                                                    options: [.skipsHiddenFiles])
                while let url = enumerator?.nextObject() as? URL {
                    if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                        result.append(url.path)
                    }
                }
            } else {
                for name in (try? manager.contentsOfDirectory(atPath: path)) ?? [] where !name.hasPrefix(".") {
                    var isSubdirectory: ObjCBool = false
                    let child = base.appendingPathComponent(name).path
                    if manager.fileExists(atPath: child, isDirectory: &isSubdirectory), !isSubdirectory.boolValue {
                        result.append(child)
                    }
                }
            }
        }
        return result.sorted()
    }
}
