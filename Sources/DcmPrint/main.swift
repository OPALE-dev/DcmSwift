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
    @Option(name: .shortAndLong, help: "Output format of the dictionary (TEXT, XML or JSON)")
    var format: String = "TEXT"
    
    @Flag(name: .shortAndLong, help: "Prettify the output string (apply to XML and JSON only)")
    var pretty: Bool = false
    
    @Argument(help: "Path of DICOM file to print")
    var sourcePath: String

    mutating func run() throws {
        if let dicomFile = DicomFile(forPath: sourcePath) {
            if let dataset = dicomFile.dataset {
                if format == "TEXT" {
                    Logger.info(dataset.description)
                }
                else if format == "XML" {
                    Logger.info(dataset.toXML(pretty))
                }
                else if format == "JSON" {
                    Logger.info(dataset.toJSON(pretty))
                }
            }
        }
    }
}

DcmPrint.main()
