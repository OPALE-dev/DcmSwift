//
//  Plan.swift
//  
//
//  Created by Paul on 15/07/2021.
//

import Foundation


/**
 Helpers concerning RTPlan modality; we return data element instead of data sequence because there's no helper
 to get a sequence for a tag name out of a dataset
 */
public class Plan {
    public static func getPatientSetupSequence(dicomRT: DicomRT) -> DataElement? {
        return dicomRT.dataset.element(forTagName: "PatientSetupSequence")
    }
    
    public static func getToleranceTableSequence(dicomRT: DicomRT) -> DataElement? {
        return dicomRT.dataset.element(forTagName: "ToleranceTableSequence")
    }
    
    public static func getBeamSequence(dicomRT: DicomRT) -> DataElement? {
        return dicomRT.dataset.element(forTagName: "BeamSequence")
    }
    
    public static func getFractionGroupSequence(dicomRT: DicomRT) -> DataElement? {
        return dicomRT.dataset.element(forTagName: "FractionGroupSequence")
    }
    
    // data elements not found
    
    public static func getDoseReferenceSequence(dicomRT: DicomRT) -> DataElement? {
        return dicomRT.dataset.element(forTagName: "DoseReferenceSequence")
    }
    
    public static func getApplicationSetupSequence(dicomRT: DicomRT) -> DataElement? {
        return dicomRT.dataset.element(forTagName: "ApplicationSetupSequence")
    }
}
