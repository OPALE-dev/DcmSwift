//
//  File.swift
//
//
//  Created by Rafael Warnault on 25/06/2021.
//

import Foundation
import DcmSwift
import ArgumentParser

struct DcmSR: ParsableCommand {
    @Argument(help: "Path of DICOM SR file to print")
    var sourcePath: String

    mutating func run() throws {
        if let dicomFile = DicomFile(forPath: sourcePath) {
            if let doc = dicomFile.structuredReportDocument {
                print(doc)
            }
        }
    }
}

DcmSR.main()
