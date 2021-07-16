//
//  StructureSet.swift
//  
//
//  Created by Paul on 15/07/2021.
//

import Foundation


let SSEQUENCE_WITH_NUMBER: [String: String] = ["ReferencedFrameofReferenceSequence": "FrameofReferenceUID",
                                              "StructureSetROISequence": "ROINumber",
                                              "ROIContourSequence": "ReferencedROINumber"]

/**
 Same class as Plan, provides helpers to get some item given a number/UID
 */
public class StructureSet {
    public static func getItemInSequenceForNumber(dicomRT: DicomRT, forSequence: String, withNumber: String) -> DataItem? {
        if !SSEQUENCE_WITH_NUMBER.keys.contains(forSequence) {
            return nil
        }
        
        guard let sequence = dicomRT.dataset.sequence(forTagName: forSequence) else { return nil }
        
        for item in sequence.items {
            guard let number = item.element(withName: SSEQUENCE_WITH_NUMBER[forSequence] ?? "") else { continue }
            
            if number.value as! String == withNumber {
                return item
            }
        }
        
        return nil
    }
    
    public static func getObservation(dicomRT: DicomRT, observationNumber: String) -> DataItem? {
        guard let sequence = dicomRT.dataset.sequence(forTagName: "RTROIObservationsSequence") else { return nil }
        
        for item in sequence.items {
            guard let number = item.element(withName: "ObservationNumber") else { return nil }
            
            if number.value as! String == observationNumber {
                return item
            }
        }
        
        return nil
    }
    
    public static func getObservationByROINumber(dicomRT: DicomRT, roiNumber: String) -> DataItem? {
        guard let sequence = dicomRT.dataset.sequence(forTagName: "RTROIObservationsSequence") else { return nil }
        
        for item in sequence.items {
            guard let number = item.element(withName: "ReferencedROINumber") else { continue }
            
            if number.value as! String == roiNumber {
                return item
            }
        }
        
        return nil
    }
}
