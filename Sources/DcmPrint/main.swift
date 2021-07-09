//
//  DcmPrint.swift
//  
//
//  Created by Rafael Warnault, OPALE on 23/06/2021.
//

import Foundation
import DcmSwift
import ArgumentParser


//struct DcmPrint: ParsableCommand {
//    @Argument(help: "Path of DICOM file to print")
//    var sourcePath: String
//
//    mutating func run() throws {
//        if let dicomFile = DicomFile(forPath: sourcePath) {
//            if let dataset = dicomFile.dataset {
//                Logger.info(dataset.description)
//            }
//        }
//    }
//}
//
//DcmPrint.main()

let pathFolder = "/Users/home/Documents/2_skull_ct/DICOM"

/*
if let dir = DicomDir.parse(atPath: pathFolder) {
    for (a,b) in dir.studies {
        print("key : \(a) value : \(b)")
    }
}
*/

let dcmDir = DicomDir.init()
let d = DicomDir.parse(atPath: pathFolder)
let dir = d!.writeDicomDir(atPath: "/Users/home/Documents/Test write DICOMDIR/")

//let d2 = DicomDir.init(forPath: "/Users/home/Documents/Test write DICOMDIR/DICOMDIR")
//print(d2?.index)
