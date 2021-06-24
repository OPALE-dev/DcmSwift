//
//  DicomAge.swift
//  
//
//  Created by Rafael Warnault on 24/06/2021.
//

import Foundation


public class DicomAge: CustomStringConvertible {
    public var description: String {
        return self.age() ?? "000D"
    }
    
    var birthdate:Date
    
    public init(birthdate:Date) {
        self.birthdate = birthdate
    }
    
    public init(ageString:String) {
        // TODO: decompose DicomAge string of every possible formats to determine birthdate
        // nnnD, nnnW, nnnM, nnnY
        // http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_6.2.html
        self.birthdate = Date() // fake date for init
    }
    
    
    public func age() -> String? {
        // TODO: implement DicomAge for each formats:
        // nnnD, nnnW, nnnM, nnnY
        // http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_6.2.html
        let dateFormatter = DateFormatter()
        
        dateFormatter.dateFormat = "Y"
        
        let birthYear   = dateFormatter.string(from: birthdate)
        let thisYear    = dateFormatter.string(from: Date())
        
        if let ty = Int(thisYear),
           let by = Int(birthYear)
        {
            return String(format: "%03dY", ty - by)
        }
        
        return nil
    }
}
