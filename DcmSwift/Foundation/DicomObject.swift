//
//  DicomObject.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 30/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation

/**
 The DicomObject class defines the structure and associated methods
 of a standard DICOM object.
 
 This class inherits from CustomStringConvertible to provide
 a proper description property implementation.
 
 It also exposes data output and formatting methods common to
 its children classes.
 */
public class DicomObject: CustomStringConvertible {
    /**
     A string description of the DICOM object
     */
    public var description: String { return "" }
    
    
    /**
     Data representation of the DICOM object
     - Returns : A Data representation of the object encoded to comply with the DICOM standard
     */
    public func toData(vrMethod inVrMethod:DicomSpec.VRMethod = .Explicit, byteOrder inByteOrder:DicomSpec.ByteOrder = .LittleEndian) -> Data {
        return Data()
    }
    
    
    /**
     XML representation of the DICOM object
     - Returns : A XML representation of the object encoded to comply with the DICOM standard
     */
    public func toXML() -> String {
        return ""
    }
    
    
    /**
     XML representation of the DICOM object
     - Returns : A XML representation of the object encoded to comply with the DICOM standard
     */
    public func toJSONArray() -> Any {
        return [:]
    }
    
    
    /**
     JSON representation of the DICOM object
     - Returns : A JSON representation of the object encoded to comply with the DICOM standard
     */
    public func toJSON() -> String {
        let data = try! JSONSerialization.data(withJSONObject: self.toJSONArray(), options: [.prettyPrinted])
        let string = String(data: data, encoding: String.Encoding.utf8)
        return string!
    }
}
