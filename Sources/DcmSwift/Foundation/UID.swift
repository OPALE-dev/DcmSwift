//
//  UID.swift
//  
//
//  Created by Rafael Warnault, OPALE on 23/06/2021.
//

import Foundation

public let orgRoot = "2.5.220.10055"

/**
 UID represents DICOM Unique Identifiers
 
 DICOM standard:
 * Section 9: http://dicom.nema.org/dicom/2013/output/chtml/part05/chapter_9.html
 * Annex B: http://dicom.nema.org/dicom/2013/output/chtml/part05/chapter_B.html
 */
public class UID {
    public var root:String
    public var suffix:String?
    
    
    // MARK: - Public interface
    public class func generate(root:String? = nil) -> String {
        let uid = UID(root: root)
                
        return uid.generate()
    }
    
    /**
     DICOM UID Validation
    
     9.1 UID Encoding Rules
     
     http://dicom.nema.org/dicom/2013/output/chtml/part05/chapter_9.html

     1.2.840.xxxxx.3.152.235.2.12.187636473
     11111.1111111
     11.11111.44444
     1.0.34444.222
     1.45464.0333.333
     
     */
    public class func validate(uid:String) -> Bool {
        let uidSplit = uid.components(separatedBy: ".")
        
        // max length up to 64 bytes
        if uid.count > 64 {
            Logger.error("UID \(uid) is larger than 64 bytes")
            return false
        }
                
        // at least 2 components
        if uidSplit.count < 2 {
            Logger.error("UID \(uid) should at least have 2 components")
            return false
        }
        
        for partString in uidSplit {
            
            // contains only digits
            guard let _ = Int(partString) else {
                Logger.error("UID \(uid) needs to be made of integers")
                return false
            }
            
            //1st char of a part cannot be a `0`
            guard let partInt = Int(partString.prefix(1)) else {
                return false
            }
            if partInt == 0 {
                Logger.error("UID \(uid) parts cannot start by '0' digit")
                return false
            }
        }
        
        return true
    }
    
    
    
    // MARK: - Private init
    private init(root:String? = nil) {
        var r = orgRoot
        
        if root != nil {
            r = root!
        }
        
        self.root = r
    }
    
    private init(uid:String? = nil) {
        self.root = orgRoot
    }
}
    


// MARK: - 
private extension UID {
    private func compose(root:String, suffix:String) -> String {
        return "\(root).\(suffix)"
    }
    
    private func generate() -> String {
        let comp1 = Int.random(in: 1..<5)
        let comp2 = Int.random(in: 1..<9999)
        let comp3 = Int.random(in: 1..<55)
        
        self.suffix = "\(comp1).\(comp2).\(comp3).\(Date().timeIntervalSince1970)"
        
        return compose(root: self.root, suffix: self.suffix!)
    }
}
