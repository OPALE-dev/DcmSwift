//
//  DcmPrint.swift
//  
//
//  Created by Rafael Warnault, OPALE on 23/06/2021.
//

import Foundation
import DcmSwift
import ArgumentParser

/*
if let ageString = AgeString(ageString: "034Y") {
    print("bd : \(ageString.birthdate)")
}
*/

let stringTestTrue = "002D"
let stringTestFalse = "coucou :P"

var testAStr1 = AgeString.init(ageString:stringTestTrue)

if let unwrappedStr = testAStr1 {
    let a2 = unwrappedStr.validate(age:stringTestTrue)
    print(a2)
    
    let a3 = unwrappedStr.age(withPrecision: .days)
    print(a3!)
}

var testAstr2 = AgeString.init(ageString: stringTestTrue)
let dateFormatter = DateFormatter()
dateFormatter.dateStyle = .short

if let unwrappedStr = testAstr2?.birthdate {
    print(unwrappedStr)
}

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
