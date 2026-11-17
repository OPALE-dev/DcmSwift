//
//  File.swift
//
//
//  Created by Rafael Warnault, OPALE on 25/06/2021.
//

import Foundation
import DcmSwift
import ArgumentParser

/**
 DcmSR is a tool to extract DICOM SR data
 
 Usage:
 
     OVERVIEW: A tool to extract DICOM SR data

     USAGE: dcm-sr <subcommand>

     OPTIONS:
       -h, --help              Show help information.

     SUBCOMMANDS:
       dump (default)          Print the DICOM SR Tree
       html                    Convert DICOM SR to HTML
       json                    Print the content tree as JSON
       measure                 Make a TID 1500 Measurement Report

       See 'dcm-sr help <subcommand>' for detailed help.
 
 */
struct DcmSR: ParsableCommand {
    static var configuration = CommandConfiguration(
            abstract: "A tool to extract DICOM SR data",
            subcommands: [Dump.self, Html.self, JSON.self, Measure.self],
            defaultSubcommand: Dump.self)
    
    struct Options: ParsableArguments {
        @Argument(help: "Path of DICOM SR input file ")
        var dicomPath: String
    }
}

extension DcmSR {
    struct Dump: ParsableCommand {
        static var configuration
            = CommandConfiguration(abstract: "Print the DICOM SR Tree")

        @OptionGroup var options: DcmSR.Options

        mutating func run() throws {
            if let dicomFile = DicomFile(forPath: options.dicomPath) {
                if let doc = dicomFile.structuredReportDocument {
                    print(doc)
                }
            }
        }
    }

    struct Html: ParsableCommand {
        static var configuration
            = CommandConfiguration(abstract: "Convert DICOM SR to HTML")

        @OptionGroup var options: DcmSR.Options
        
        @Argument(help: "Path of HTML output file ")
        var htmlPath: String

        mutating func run() throws {
            if let dicomFile = DicomFile(forPath: options.dicomPath) {
                if let doc = dicomFile.structuredReportDocument {
                    let html = doc.html
                    
                    print(html)
                    
                    try? html.write(to: URL(fileURLWithPath: htmlPath), atomically: true, encoding: .utf8)
                }
            }
        }
    }
}

DcmSR.main()

extension DcmSR {
    struct JSON: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print the content tree as JSON")

        @OptionGroup var options: DcmSR.Options

        mutating func run() throws {
            guard let file = DicomFile(forPath: options.dicomPath), let dataSet = file.dataset,
                  let report = DICOMStructuredReport(dataSet: dataSet) else {
                throw ValidationError("\(options.dicomPath) is not a Structured Report")
            }
            func code(_ code: DICOMCode?) -> Any {
                code.map { [$0.value, $0.scheme, $0.meaning] } ?? NSNull()
            }
            func node(_ item: DICOMSRContentItem) -> [String: Any] {
                var object: [String: Any] = ["relationship": item.relationship ?? NSNull(), "valueType": item.value.valueType,
                                             "concept": code(item.conceptName), "children": item.children.map(node)]
                switch item.value {
                case .text(let text), .dateTime(let text), .date(let text), .time(let text), .uidReference(let text),
                     .personName(let text):
                    object["value"] = text
                case .code(let value): object["value"] = code(value)
                case .number(let number, let units, _): object["value"] = [number ?? NSNull(), code(units)]
                case .image(let reference), .composite(let reference), .waveform(let reference):
                    object["value"] = [reference.sopClassUID, reference.sopInstanceUID]
                case .spatialCoordinates(let type, let points), .spatialCoordinates3D(let type, let points, _):
                    object["value"] = [type, points]
                case .reference(let identifier): object["value"] = identifier
                default: break
                }
                return object
            }
            let object: [String: Any] = ["sopClassUID": report.sopClassUID,
                                         "template": report.template.map { [$0.mappingResource, $0.identifier] } ?? NSNull(),
                                         "root": node(report.root)]
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: object))
        }
    }

    struct Measure: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Make a TID 1500 Measurement Report of measurements on images",
            discussion: """
                Each --measurement is name=code,scheme,meaning:value:units, such as \
                "volume=118565006,SCT,Volume:12.5:cm3"; measurements of the same name form one \
                Measurement Group, tracked by that name.
                """)

        @Option(name: .customLong("image"), help: "A measured image; repeatable. The first gives the patient and study")
        var images: [String] = []

        @Option(help: "Person Observer Name")
        var observer: String = ""

        @Option(help: "Procedure reported, as code,scheme,meaning")
        var procedure: String = "77477000,SCT,CT"

        @Option(name: .customLong("measurement"), help: "name=code,scheme,meaning:value:units; repeatable")
        var measurements: [String] = []

        @Option(name: .shortAndLong, help: "SR file to write")
        var output: String

        mutating func run() throws {
            func code(_ text: Substring) throws -> DICOMCode {
                let parts = text.split(separator: ",", maxSplits: 2).map(String.init)
                guard parts.count == 3 else { throw ValidationError("a code is code,scheme,meaning, not \(text)") }
                return DICOMCode(parts[0], scheme: parts[1], meaning: parts[2])
            }
            let dataSets = try images.map { path -> DataSet in
                guard let file = DicomFile(forPath: path), let dataSet = file.dataset else {
                    throw ValidationError("cannot read \(path) as DICOM")
                }
                return dataSet
            }
            var groups: [(String, [DICOMMeasurementReport.Measurement])] = []
            for text in measurements {
                let parts = text.split(separator: "=", maxSplits: 1)
                let fields = parts.count == 2 ? parts[1].split(separator: ":") : []
                guard fields.count == 3, let value = Double(fields[1]) else {
                    throw ValidationError("--measurement expects name=code,scheme,meaning:value:units, not \(text)")
                }
                let measurement = DICOMMeasurementReport.Measurement(
                    concept: try code(fields[0]), value: value,
                    units: DICOMCode(String(fields[2]), scheme: "UCUM", meaning: String(fields[2])))
                if let index = groups.firstIndex(where: { $0.0 == String(parts[0]) }) {
                    groups[index].1.append(measurement)
                } else {
                    groups.append((String(parts[0]), [measurement]))
                }
            }
            let report = DICOMMeasurementReport(
                procedure: try code(Substring(procedure)), observerName: observer,
                images: dataSets.map { DICOMSRReference(sopClassUID: $0.string(forTag: "SOPClassUID") ?? "",
                                                        sopInstanceUID: $0.string(forTag: "SOPInstanceUID") ?? "") },
                groups: groups.map { DICOMMeasurementReport.Group(trackingIdentifier: $0.0, measurements: $0.1) })
            try report.document().dataSet(context: dataSets.first).writePart10(to: URL(fileURLWithPath: output))
        }
    }
}
