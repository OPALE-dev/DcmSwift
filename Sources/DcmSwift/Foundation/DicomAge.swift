//
//  DicomAge.swift
//  
//
//  Created by Rafael Warnault, OPALE on 24/06/2021.
//

import Foundation

/**
 DicomAge represents a DICOM Age String (AS value representation)
 
 This class aims to ease manipulations of DICOM Age String values by
 providing helpers to encode them from `Date` object and decode them
 from `String` object.
 
 The VR is defined here in the DICOM standard:
 
 http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_6.2.html
 */
public class DicomAge: VR {
    var birthdate:Date
    var precision:AgePrecision = .years
    
    /**
     AgePrecision is an enumeration that defines the age formatting behavior
     */
    public enum AgePrecision:Int {
        case years
        case month
        case weeks
        case days
    }
    
    /**
     From CustomStringConvertible protocol
     */
    public override var description: String {
        return self.age() ?? "000D"
    }
    
    
    /**
     Create age from birth date
     */
    public init?(birthdate:Date) {
        self.birthdate = birthdate
        
        super.init(name: "AS", maxLength: 4)
    }
    
    /**
     Create age from DICOM age string
     */
    public init?(ageString:String) {
        // TODO: decompose DicomAge string of every possible formats to determine birthdate
        // nnnD, nnnW, nnnM, nnnY, ex : 107Y, 033D, 012W, etc.
        // http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_6.2.html
        self.birthdate = Date() // fake date for init
        
        super.init(name: "AS", maxLength: 4)
    }
    
    /**
     Generate a DICOM Age String (AS VR)
     */
    public func age(withPrecision precision:AgePrecision? = nil) -> String? {
        // TODO: implement DicomAge for each formats:
        // nnnD, nnnW, nnnM, nnnY, ex : 107Y, 033D, 012W, etc.
        // http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_6.2.html
        let p = precision ?? self.precision
        
        let dateFormatter = DateFormatter()
        
        if p == .years {
            dateFormatter.dateFormat = "Y"
        
            let birthYear   = dateFormatter.string(from: birthdate)
            let thisYear    = dateFormatter.string(from: Date())
            
            if let ty       = Int(thisYear),
               let by       = Int(birthYear)
            {
  
                return String(format: "%03dY", ty - by)
            }
        }
        
        return nil
    }
    
    // TODO: implement a validation of Age String format
    private func validate(age:String) -> Bool {
        return false
    }
}
