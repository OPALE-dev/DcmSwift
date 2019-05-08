//
//  PresentationContext.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 02/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation


public class PresentationContext {
    public var acceptedTransferSyntax:String?
    public var abstractSyntax:String!
    public var contextID:UInt8!
    
    private var pcLength:Int16 = 0
    
    public init(abstractSyntax:String, transferSyntaxes:[String] = [], contextID:UInt8) {
        self.abstractSyntax = abstractSyntax
        self.contextID = contextID
    }
    
    
    public func length() -> Int16 {
        return pcLength
    }
    
    public init?(data:Data) {
        let pcType = data.first
        
        if pcType != ItemType.acPresentationContext.rawValue {
            return nil
        }
        
        let pcContextID = data.subdata(in: 4..<6).toInt8(byteOrder: .BigEndian)
        self.contextID = UInt8(pcContextID)
        
        let offset = 8
        
        // parse & check transfer syntax
        let tsData = data.subdata(in: offset..<data.count)
        let tsLength = tsData.subdata(in: 2..<4).toInt16(byteOrder: .BigEndian)
        let transferSyntaxData = tsData.subdata(in: 4..<Int(tsLength)+4)
        
        self.acceptedTransferSyntax = String(bytes: transferSyntaxData, encoding: .utf8)
        self.pcLength = Int16(offset) + tsLength
    }
    
    
    public func data() -> Data {
        // ABSTRACT SYNTAX Data
        var asData = Data()
        let asLength = UInt16(self.abstractSyntax.data(using: .utf8)!.count)
        asData.append(uint8: ItemType.abstractSyntax.rawValue, bigEndian: true) // 30H
        asData.append(byte: 0x00)
        asData.append(uint16: asLength, bigEndian: true)
        asData.append(self.abstractSyntax.data(using: .utf8)!)
        
        // TRANSFER SYNTAXES Data
        var tsData = Data()
        for ts in [DicomConstants.explicitVRLittleEndian] {
            let tsLength = UInt16(ts.data(using: .utf8)!.count)
            tsData.append(uint8: ItemType.transferSyntax.rawValue, bigEndian: true)
            tsData.append(byte: 0x00) // RESERVED
            tsData.append(uint16: tsLength, bigEndian: true)
            tsData.append(ts.data(using: .utf8)!)
        }
        
        // Presentation Context
        var pcData = Data()
        pcData.append(uint8: ItemType.rqPresentationContext.rawValue, bigEndian: true)
        pcData.append(byte: 0x00) // RESERVED
        
        let pcLength = UInt16(4 + asData.count + tsData.count)
        pcData.append(uint16: pcLength, bigEndian: true)
        
        pcData.append(uint8: self.contextID, bigEndian: true) // Presentation Context ID
        pcData.append(byte: 0x00, count: 3) // 00H x 3 RESERVED
        pcData.append(asData)
        pcData.append(tsData)
        
        return pcData
    }
}
