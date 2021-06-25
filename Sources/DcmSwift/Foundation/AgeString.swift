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
public class AgeString: VR {
    var birthdate:Date
    var precision:AgePrecision = .years
    
    /**
     AgePrecision is an enumeration that defines the age formatting behavior
     */
    public enum AgePrecision:Int {
        case years
        case months
        case weeks
        case days
    }
    
    /**
     From CustomStringConvertible protocol
     */
    public override var description: String {
        return self.age(withPrecision: precision) ?? "000D"
    }
    
    
    /**
     Create age from birth date
     */
    public init?(birthdate:Date) {
        // make sure reject future dates
        if birthdate > Date() {
            return nil
        }
        
        self.birthdate = birthdate
        
        super.init(name: "AS", maxLength: 4)
    }
    
    /**
     Create age from DICOM age string
     */
    public init?(ageString:String) {
        // TODO: decompose AgeString string of every possible formats to determine birthdate
        // nnnD, nnnW, nnnM, nnnY, ex : 107Y, 033D, 012W, etc.
        // http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_6.2.html
        self.birthdate = Date() // fake date for init
        
        // make sure reject future dates
        if birthdate > Date() {
            return nil
        }
        
        super.init(name: "AS", maxLength: 4)
    }
    

    /**
        Generate a DICOM age String using specified precision
        Version Colombe
     */
    public func age(withPrecision precision:AgePrecision? = nil) -> String? {
        let p = precision ?? self.precision
        let nbDays = Calendar.current.dateComponents([.day], from: birthdate, to: Date()).day!
        
        if(nbDays > 999 || p == .weeks || p == .months || p == .years) {
            let nbWeeks = nbDays/7
            
            if(nbWeeks > 999 || p == .months || p == .years) {
                let nbMonths = nbDays/30
                
                if(nbMonths > 999 || p == .years) {
                    let nbYears = nbDays/365
                    
                    return "\(String(format: "%03d", nbYears))Y"
                } else {
                    return "\(String(format: "%03d", nbMonths))M"
                }
            } else {
                return "\(String(format: "%03d", nbWeeks))W"
            }
        } else {
            return "\(String(format: "%03d", nbDays))D"
        }
    }
    
    // TODO: implement a validation of Age String format
    public func validate(age:String) -> Bool {
        return false
    }
}
