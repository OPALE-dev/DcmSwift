//
//  StructureSet.swift
//  
//
//  Created by Paul on 15/07/2021.
//

import Foundation

/**
 For a sequence, gives the id by which an item is identified
 */
let SSEQUENCE_WITH_NUMBER: [String: String] = ["ReferencedFrameofReferenceSequence": "FrameofReferenceUID",
                                               "StructureSetROISequence": "ROINumber",
                                               "ROIContourSequence": "ReferencedROINumber"]

/**
 Same class as Plan, provides helpers to get some item given a number/UID
 Example below : find the item in SomeSequence, with Number2
 ```
 SomeSequence
    - Item1
        * SomeDataElement
        * Number1
    - Item2
        * SomeDataElement
        * Number2
 ```
 */
public class StructureSet {
    /**
     Gets a Data Item in a specific sequence, with the item having a specific number/ID
     
     ```
     StructureSet.getItemInSequenceForNumber(dicomRT: dicomRT,
                                             forSequence: "ReferencedFrameofReferenceSequence",
                                             withNumber: "1.2.840.113619.2.55.3.3767434740.12488.1173961280.931.803.0.11")
     ```
     */
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
    
    /**
     Get Data Item in Observation sequence, data item identified by an observation number
     
     ```
     StructureSet.getObservation(dicomRT: dicomRT, observationNumber: "1")
     ```
     */
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
    
    /**
     Get Data Item in Observation sequence, data item identified by a ROI number
     
     ```
     StructureSet.getObservationByROINumber(dicomRT: dicomRT, roiNumber: "1")
     ```
     */
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
