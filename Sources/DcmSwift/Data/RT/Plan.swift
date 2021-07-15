//
//  Plan.swift
//  
//
//  Created by Paul on 15/07/2021.
//

import Foundation


let SEQUENCE_WITH_NUMBER: [String: String] = ["PatientSetupSequence": "PatientSetupNumber",
                                           "ToleranceTableSequence": "ToleranceTableNumber",
                                           "BeamSequence": "BeamNumber",
                                           "FractionGroupSequence": "FractionGroupNumber",
                                           "DoseReferenceSequence": "DoseReferenceNumber",
                                           "ApplicationSetupSequence": "ApplicationSetupNumber"]


/**
 Helpers concerning RTPlan modality; we take an item from a sequence in which the "number" corresponds to the one given
 in the parameters
 */
public class Plan {
    
    
    public static func getItemInSequenceForNumber(dicomRT: DicomRT, forSequence: String, withNumber: String) -> DataItem? {
        if !SEQUENCE_WITH_NUMBER.keys.contains(forSequence) {
            return nil
        }
        
        guard let sequence = dicomRT.dataset.sequence(forTagName: forSequence) else { return nil }
        
        for item in sequence.items {
            guard let number = item.element(withName: SEQUENCE_WITH_NUMBER[forSequence] ?? "") else { return nil }
            
            if number.value as! String == withNumber {
                return item
            }
        }
        
        return nil
    }
    
    public static func getPatientSetup(dicomRT: DicomRT, withNumber: String) -> DataItem? {
        guard let patientSetupSequence = dicomRT.dataset.sequence(forTagName: "PatientSetupSequence") else {
            return nil
        }
        
        
        for patientSetupSequenceItem in patientSetupSequence.items {
            guard let patientSetupNumber = patientSetupSequenceItem.element(withName: "PatientSetupNumber") else {
                continue
            }
            
            if patientSetupNumber.value as! String == withNumber {
                return patientSetupSequenceItem
            }
        }
        
        return nil
    }
}
