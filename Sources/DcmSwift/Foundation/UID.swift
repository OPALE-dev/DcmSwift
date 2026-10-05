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
        if uid.utf8.count > 64 {
            Logger.error("UID \(uid) is larger than 64 bytes")
            return false
        }
                
        // at least 2 components
        if uidSplit.count < 2 {
            Logger.error("UID \(uid) should at least have 2 components")
            return false
        }
        
        for partString in uidSplit {
            guard !partString.isEmpty,
                  partString.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) else {
                Logger.error("UID \(uid) needs to be made of integers")
                return false
            }
            
            // Multi-digit components cannot have leading zeroes; the component "0" is valid.
            if partString.count > 1 && partString.first == "0" {
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
        let milliseconds = UInt64(Date().timeIntervalSince1970 * 1_000)
        let random = UInt64.random(in: 0...UInt64.max)
        self.suffix = "\(milliseconds).\(random)"

        let uid = compose(root: self.root, suffix: self.suffix!)
        if UID.validate(uid: uid) { return uid }
        return compose(root: orgRoot, suffix: self.suffix!)
    }
}
