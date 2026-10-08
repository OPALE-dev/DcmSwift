//
//  DcmPrint.swift
//  
//
//  Created by Rafael Warnault, OPALE on 23/06/2021.
//

import Foundation
import DcmSwift
import ArgumentParser


struct DcmPrint: ParsableCommand {
    @Option(name: .shortAndLong, help: "Output format of the dictionary (TEXT, XML for the Native DICOM Model, or JSON for the DICOM JSON Model)")
    var format: String = "TEXT"
    
    @Flag(name: .shortAndLong, help: "Prettify the output string (apply to XML and JSON only)")
    var pretty: Bool = false
    
    @Argument(help: "Path of DICOM file to print")
    var sourcePath: String

    mutating func run() throws {
        guard let dicomFile = DicomFile(forPath: sourcePath), dicomFile.dataset != nil else {
            Logger.error("Cannot read \(sourcePath) as DICOM")
            throw ExitCode.failure
        }
        do {
            if let dataset = dicomFile.dataset {
                if format == "TEXT" {
                    print(dataset.description)
                }
                else if format == "XML" {
                    // The Native DICOM Model (PS3.19 A.1).
                    do {
                        let xml = try DICOMXML.encode(dataset, options: DICOMJSON.EncodingOptions(prettyPrinted: pretty))
                        print(String(decoding: xml, as: UTF8.self), terminator: "")
                    } catch {
                        Logger.error("\(error)")
                        DcmPrint.exit(withError: ExitCode.failure)
                    }
                }
                else if format == "JSON" {
                    // The DICOM JSON Model (PS3.18 Annex F).
                    do {
                        let json = try DICOMJSON.encode(dataset, options: DICOMJSON.EncodingOptions(prettyPrinted: pretty))
                        print(String(decoding: json, as: UTF8.self))
                    } catch {
                        Logger.error("\(error)")
                        DcmPrint.exit(withError: ExitCode.failure)
                    }
                }
            }
        }
    }
}

DcmPrint.main()
