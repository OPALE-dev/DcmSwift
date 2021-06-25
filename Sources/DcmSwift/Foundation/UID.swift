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

     */
    public class func validate(uid:String) -> Bool {
        // max length up to 64 bytes
        if uid.count > 64 {
            Logger.error("UID \(uid) is larger than 64 bytes")
            return false
        }
        
        // 1st char cannot be a `0`
        if uid.first == "0" {
            Logger.error("UID \(uid) cannot start by `0' digit")
            return false
        }
        
        // at least 2 components
        if uid.split(separator: ".").count != 2 {
            Logger.error("UID \(uid) should at least have 2 components")
            return false
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
