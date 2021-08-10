//
//  Anonymizer.swift
//  
//
//  Created by Rafael Warnault, OPALE on 24/06/2021.
//

import Foundation

/**
 Class for anonymizing a DICOM file
 
 - TODO: why not a static class ?
 */
public class Anonymizer {
    
    /// Related to `DataElement`'s `VR`
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
    
    /**
     Name of data elements to anonymize
     */
    let defaultUIDsToAnonymize:[String: AnonymizationType] = [
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
    
    /// the DICOM file to anonimyze
    var dicomFile:DicomFile
    
    /**
     Inits the anonimyzer for a DICOM file
     
     - Parameter path: the file path of the DICOM file to anonymize
     */
    public init?(path:String) {
        guard let dicomFile = DicomFile(forPath: path) else {
            return nil
        }
        
        self.dicomFile = dicomFile
    }
    
    /**
     Anonymize a DICOM file and writes the result in `destPath`
  
     The anonimyzation is based on a default set of data elements, see `defaultUIDsToAnonymize`.
  
     - SeeAlso: `defaultUIDsToAnonymize`
     
     - Parameters:
        - destPath: the path to write the anonymized DICOM file
     
     - Returns: a `Bool` indicating success
     */
    public func anonymize(to destPath:String) -> Bool {
        return anonymize(to: destPath, tags: defaultUIDsToAnonymize)
    }
    
    /**
     Anonymize a DICOM file and writes the result in `destPath`
  
     - Parameters:
        - destPath: the path to write the anonymized DICOM file
        - tags: a hash, with the keys being the names of the data elements to anonymize, and the values the types
     
     - Returns: a `Bool` indicating success
     */
    public func anonymize(to destPath:String, tags:[String: AnonymizationType]) -> Bool {
        if var dataset = dicomFile.dataset {
            dataset = anonymize(dataset: dataset, tags: tags)
            
            return dicomFile.write(atPath: destPath)
        }
        return false
    }
    
    /**
     Anonymize a `DataSet` given some tags of data elements to anonymize
     
     The data elements to anonymize are in a hash, with keys being the data elements' names to anonymize, and the values
     the type of the data element. We need the types because we can't anonymize randomly, like putting a random integer
     
     - Remark: why not get the data element type, and then anonymize according to it ? instead of providing the types
     - Parameters:
        - dataset: the dataset to anonymize
        - tags: a hash, with the keys being the names of the data elements to anonymize, and the values the types
     - Returns: the anonymized `DataSet`
     */
    public func anonymize(dataset:DataSet, tags:[String: AnonymizationType]) -> DataSet {
        let today       = Date()
        var birthdate   = Date()
        
        // TODO: obviously better birthdate is needed here...
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
                        if let age  = AgeString(birthdate: birthdate),
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
