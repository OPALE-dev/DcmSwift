//
//  main.swift
//  
//
//  Created by Rafael Warnault on 23/06/2021.
//

import Foundation
import DcmSwift

func usage() {
    Logger.info("DcmPrint is a CLI program that display the DICOM dataset\n")
    Logger.info("Usage: DcmPrint <path/to/dicom/file>\n")
}

if CommandLine.arguments.count != 2 {
    Logger.error("Invalid arguments\n")
    
    usage()
    
    exit(0)
}

let path = CommandLine.arguments[1]

if let dicomFile = DicomFile(forPath: path) {
    if let dataset = dicomFile.dataset {
        print(dataset)
    }
}
