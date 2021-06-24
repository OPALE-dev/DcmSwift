//
//  File.swift
//  
//
//  Created by Rafael Warnault on 23/06/2021.
//

import Foundation
import DcmSwift


func usage() {
    Logger.info("DcmAnonymize is a CLI program that anonymize a DICOM file\n")
    Logger.info("Usage: DcmAnonymize <path/to/dicom/file> <path/to/anonymized/file>\n")
}

if CommandLine.arguments.count != 3 {
    Logger.error("Invalid arguments\n")
    
    usage()
    
    exit(0)
}

let sourcePath  = CommandLine.arguments[1]
let destPath    = CommandLine.arguments[2]

guard let anonymizer = Anonymizer(path: sourcePath) else {
    Logger.error("Cannot create anonymizer for file: \(sourcePath)")
    
    exit(0)
}

if !anonymizer.anonymize(to: destPath) {
    Logger.error("Cannot write anonymized file")
    
    exit(0)
}

Logger.info("Anonymization succeeded")



public class Anonymizer {
    public enum AnonymizationType {
        case uid(root: String? = nil)
        case string(_ string:String)
        case id
        case date
        case time
        case datetime
        case age
        case blank
        case delete
    }
    
    let UIDsToAnonymize:[String: AnonymizationType] = [
        "StudyInstanceUID":                 .uid(),
        "SeriesInstanceUID":                .uid(),
        "SOPInstanceUID":                   .uid(),
        "MediaStorageSOPInstanceUID":       .uid(),
        "InstanceCreationDate":             .date,
        "InstanceCreationTime":             .time,
        "StudyDate":                        .date,
        "StudyTime":                        .time,
        "SeriesDate":                       .date,
        "SeriesTime":                       .time,
        "AcquisitionDate":                  .date,
        "AcquisitionTime":                  .time,
        "ContentDate":                      .date,
        "ContentTime":                      .time,
        "PatientName":                      .string("Anonymized"),
        "PatientID":                        .id,
        "PatientAge":                       .age,
        "OtherPatientID":                   .id,
        "StudyDescription":                 .string("Anonymized"),
        "SeriesDescription":                .string("Anonymized"),
        "PerformingPhysicianName":          .blank,
        "OperatorsName":                    .blank,
        "ReferringPhysicianName":           .blank,
        "InstitutionName":                  .blank,
        "NameOfPhysiciansReadingStudy":     .blank
    ]
    
    var dicomFile:DicomFile
    
    public init?(path:String) {
        guard let dicomFile = DicomFile(forPath: path) else {
            return nil
        }
        
        self.dicomFile = dicomFile
    }
    
    public func anonymize(to destPath:String) -> Bool {
        if let dataset = dicomFile.dataset {
//            for (name, type) in UIDsToAnonymize {
//                for element in dataset.allElements {
//                    if element.name == name {
//                        switch type {
//                        case .uid(let root):
//                            _ = dataset.set(value: DicomUID.generate(root: root), forTagName: name)
//                        case .string(let string):
//                            _ = dataset.set(value: string, forTagName: name)
//                        case .id:
//                            _ = dataset.set(value: String.random(length: 12), forTagName: name)
//                        case .blank:
//                            _ = dataset.set(value: "", forTagName: name)
//                        default:
//                            _ = dataset.set(value: "", forTagName: name)
//                        }
//                    }
//                }
//            }
            
            //print("Anonymized Dataset\n\(dataset)")
            
            return dicomFile.write(atPath: destPath)
        }
        return false
    }
}
