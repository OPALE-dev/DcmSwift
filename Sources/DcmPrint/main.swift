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
    
    @Argument(help: "Path of DICOM file to print")
    var sourcePath: String

    mutating func run() throws {
        if let dicomFile = DicomFile(forPath: sourcePath) {
            if let dataset = dicomFile.dataset {
                if format == "TEXT" {
                    Logger.info(dataset.description)
                }
                else if format == "XML" {
                    Logger.info(dataset.toXML())
                }
                else if format == "JSON" {
                    Logger.info(dataset.toJSON())
                }
            }
        }
    }
}

DcmPrint.main()
