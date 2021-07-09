//
//  SRCode.swift
//  
//
//  Created by Rafael Warnault on 05/07/2021.
//

import Foundation

public class SRCode: CustomStringConvertible {
    public var codeValue:String!
    public var codingSchemeDesignator:String!
    public var codeMeaning:String!
    public var codingSchemeUID:String?
    
    public init?(withSequence sequence:DataSequence) {
        guard let item = sequence.items.first else {
            return nil
        }
        
        if let cv   = item.element(withName: "CodeValue")?.value as? String,
           let csd  = item.element(withName: "CodingSchemeDesignator")?.value as? String,
           let cm   = item.element(withName: "CodeMeaning")?.value as? String
        {
            self.codeValue                  = cv.trimmingCharacters(in: .whitespacesAndNewlines)
            self.codingSchemeDesignator     = csd.trimmingCharacters(in: .whitespacesAndNewlines)
            self.codeMeaning                = cm.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let csu = item.element(withName: "CodingSchemeUID")?.value as? String {
                self.codingSchemeUID = csu.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
    
    public var description: String {
        get {
            "\(codeMeaning ?? ""): \(codeValue ?? ""), \(codingSchemeDesignator ?? "") [\(codingSchemeUID ?? "?")]"
        }
    }
}
