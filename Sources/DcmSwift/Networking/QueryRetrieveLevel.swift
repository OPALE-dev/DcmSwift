//
//  File.swift
//  
//
//  Created by Rafael Warnault on 29/07/2021.
//

import Foundation

/**
 Enum that define Query Retrieve Level (0008, 0052)
 
 http://dicom.nema.org/Dicom/2013/output/chtml/part04/sect_C.6.html
 */
public enum QueryRetrieveLevel {
    case PATIENT
    case STUDY
    case SERIES
    case IMAGE
    
    /**
     Returns a dataset for querying
     
     `DataSet` filled of DataElements (PatientID, PatientName etc.) with empry values.
     There are different levels of query : PATIENT, STUDY, SERIES, IMAGE. For each query level there's
     a different set of data elements
     
     - Returns: a `DataSet` of empty DataElements
     */
    static func defaultQueryDataset(level:QueryRetrieveLevel) -> DataSet {
        let dataset = DataSet()
        
        switch level {
        case .PATIENT:
            _ = dataset.set(value:"", forTagName: "PatientID")
            _ = dataset.set(value:"", forTagName: "PatientName")
            _ = dataset.set(value:"", forTagName: "PatientBirthDate")
            _ = dataset.set(value:"", forTagName: "PatientSex")
            _ = dataset.set(value:"", forTagName: "PatientComments")
            _ = dataset.set(value:"", forTagName: "NumberOfPatientRelatedStudies")
            _ = dataset.set(value:"", forTagName: "NumberOfPatientRelatedSeries")
            _ = dataset.set(value:"", forTagName: "NumberOfPatientRelatedInstances")
            
        case .STUDY:
            _ = dataset.set(value:"", forTagName: "PatientID")
            _ = dataset.set(value:"", forTagName: "PatientName")
            _ = dataset.set(value:"", forTagName: "PatientBirthDate")
            _ = dataset.set(value:"", forTagName: "PatientSex")
            _ = dataset.set(value:"", forTagName: "PatientAge")
            _ = dataset.set(value:"", forTagName: "PatientWeight")
            _ = dataset.set(value:"", forTagName: "PatientSize")
            _ = dataset.set(value:"", forTagName: "PatientComments")
            _ = dataset.set(value:"", forTagName: "StudyDescription")
            _ = dataset.set(value:"", forTagName: "StudyDate")
            _ = dataset.set(value:"", forTagName: "StudyTime")
            _ = dataset.set(value:"", forTagName: "StudyID")
            _ = dataset.set(value:"", forTagName: "StudyInstanceUID")
            _ = dataset.set(value:"", forTagName: "AccessionNumber")
            _ = dataset.set(value:"", forTagName: "NumberOfStudyRelatedSeries")
            _ = dataset.set(value:"", forTagName: "NumberOfStudyRelatedInstances")
            
        case .SERIES:
            _ = dataset.set(value:"", forTagName: "Modality")
            _ = dataset.set(value:"", forTagName: "SeriesNumber")
            _ = dataset.set(value:"", forTagName: "SeriesInstanceUID")
            _ = dataset.set(value:"", forTagName: "NumberOfSeriesRelatedInstances")
            
        case .IMAGE:
            _ = dataset.set(value:"", forTagName: "InstanceNumber")
            _ = dataset.set(value:"", forTagName: "SOPClassUID")
            _ = dataset.set(value:"", forTagName: "SOPInstanceUID")

        }
        
        return dataset
    }
}
