//
//  File.swift
//  
//
//  Created by Rafael Warnault on 23/06/2021.
//

import Foundation
import DcmSwift
import ArgumentParser

struct DcmAnonymize: ParsableCommand {
    @Argument(help: "Path of DICOM file to anonymize")
    var sourcePath: String
    
    @Argument(help: "Path to save the anonymized DICOM file")
    var destPath: String

    mutating func run() throws {
        guard let anonymizer = Anonymizer(path: sourcePath) else {
            Logger.error("Cannot create anonymizer for file: \(sourcePath)")

            DcmAnonymize.exit(withError: nil)
        }

        if !anonymizer.anonymize(to: destPath) {
            Logger.error("Cannot write anonymized file \(destPath)")

            DcmAnonymize.exit(withError: nil)
        }

        Logger.info("Anonymization succeeded")
    }
}

DcmAnonymize.main()


public class Anonymizer {
    public enum AnonymizationType {
        case uid(root: String? = nil)
        case string(_ string:String)
        case id
        case date
        case time
        case datetime
        case birthdate
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
        "PatientBirthDate":                 .birthdate,
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
        if var dataset = dicomFile.dataset {
            dataset = anonymize(dataset: dataset, tags: UIDsToAnonymize)
            
            Logger.info("Anonymized Dataset\n\(dataset)")
            
            return dicomFile.write(atPath: destPath)
        }
        return false
    }
    
    
    public func anonymize(dataset:DataSet, tags:[String: AnonymizationType]) -> DataSet {
        let today       = Date()
        var birthdate   = Date()
        
        birthdate = birthdate.addingTimeInterval(-20000)
        
        for (name, type) in tags {
            for element in dataset.allElements {
                if element.name == name {
                    switch type {
                    case .uid(let root):
                        _ = dataset.set(value: UID.generate(root: root), forTagName: name)
                    case .string(let string):
                        _ = dataset.set(value: string, forTagName: name)
                    case .id:
                        _ = dataset.set(value: String.random(length: 12), forTagName: name)
                    case .blank:
                        _ = dataset.set(value: "", forTagName: name)
                    case .date:
                        _ = dataset.set(value: today.dicomDateString(), forTagName: name)
                    case .time:
                        _ = dataset.set(value: today.dicomTimeString(), forTagName: name)
                    case .datetime:
                        _ = dataset.set(value: today.dicomDateTimeString(), forTagName: name)
                    case .birthdate:
                        _ = dataset.set(value: birthdate.dicomDateString(), forTagName: name)
                    case .age:
                        if let age  = DicomAge(birthdate: birthdate),
                           let a    = age.age()
                        {
                            _ = dataset.set(value: a, forTagName: name)
                        }
                    case .delete:
                        _ = dataset.remove(elementForTagName: name)
                    }
                }
            }
        }
        return dataset
    }
}
