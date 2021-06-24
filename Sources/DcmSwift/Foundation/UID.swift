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

    public class func validate(uid:String) -> Bool {
        return false
    }
    
    
    
    // MARK: - Private
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
    
    // TODO: validate DICOM UID
    private func validate(uid:String) -> Bool {
        return false
    }
}
