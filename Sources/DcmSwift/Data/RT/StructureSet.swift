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
let SSEQUENCE_WITH_NUMBER: [String: String] = ["ReferencedFrameOfReferenceSequence": "FrameOfReferenceUID",
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
    private static func normalizedIdentifier(_ element: DataElement) -> String? {
        return (element.value as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
    }
    /**
     Gets a Data Item in a specific sequence, with the item having a specific number/ID
     
     ```
     StructureSet.getItemInSequenceForNumber(dicomRT: dicomRT,
                                             forSequence: "ReferencedFrameOfReferenceSequence",
                                             withNumber: "1.2.840.113619.2.55.3.3767434740.12488.1173961280.931.803.0.11")
     ```
     
     - Parameters:
        - dicomRT: the DICOM RT file to parse
        - forSequence: the name of the sequence to parse
        - withNumber: the ID of the `DataItem` to get
     - Returns: the `DataItem` found, or nil if not found
     */
    public static func getItemInSequenceForNumber(dicomRT: DicomFile, forSequence: String, withNumber: String) -> DataItem? {
        if !SSEQUENCE_WITH_NUMBER.keys.contains(forSequence) {
            return nil
        }
        
        guard let sequence = dicomRT.dataset.sequence(forTagName: forSequence) else { return nil }
        
        for item in sequence.items {
            guard let number = item.element(withName: SSEQUENCE_WITH_NUMBER[forSequence] ?? "") else { continue }
            
            if normalizedIdentifier(number) == withNumber {
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
     
     - Parameters:
        - observationNumber: the ID of the `DataItem` to get
     - Returns: the `DataItem` found, or `nil` if not found
     */
    public static func getObservation(dicomRT: DicomFile, observationNumber: String) -> DataItem? {
        guard let sequence = dicomRT.dataset.sequence(forTagName: "RTROIObservationsSequence") else { return nil }
        
        for item in sequence.items {
            guard let number = item.element(withName: "ObservationNumber") else { return nil }
            
            if normalizedIdentifier(number) == observationNumber {
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
     
     - Parameters:
        - roiNumber: the ID of the `DataItem` to get
     - Returns: the `DataItem` found, or `nil` if not found
     */
    public static func getObservationByROINumber(dicomRT: DicomFile, roiNumber: String) -> DataItem? {
        guard let sequence = dicomRT.dataset.sequence(forTagName: "RTROIObservationsSequence") else { return nil }
        
        for item in sequence.items {
            guard let number = item.element(withName: "ReferencedROINumber") else { continue }
            
            if normalizedIdentifier(number) == roiNumber {
                return item
            }
        }
        
        return nil
    }
}
