//
//  PresentationContext.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 02/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 Presentation Context Item Structure
 
 TODO: rewrite with OffsetInputStream
 
 Presentation Context consists of:
 - item type
 - 1 reserved byte
 - 2 item length
 - presentation context id
 - 1 reserved byte
 - result/reason OR 1 reserved byte
 - 1 reserved byte
 - only 1 transfer syntax OR 1 abstract syntax and 1 or more transfer syntax
 
 http://dicom.nema.org/dicom/2013/output/chtml/part08/sect_9.3.html#sect_9.3.2.2
 */
public class PresentationContext {
    public var transferSyntaxes:[String] = []
    
    
    public var acceptedTransferSyntax:String?
    public var abstractSyntax:String!
    public var contextID:UInt8!
    public var result:UInt8!
    
    private var pcLength:Int16 = 0
    
    public init(abstractSyntax:String, transferSyntaxes:[String] = [], contextID:UInt8, result:UInt8? = nil) {
        self.transferSyntaxes = transferSyntaxes
        self.abstractSyntax = abstractSyntax
        self.contextID = contextID
        self.result = result
    }
    
    public var description: String {
        return String(format:"%@ %@ %@ %d %d", transferSyntaxes.debugDescription, acceptedTransferSyntax ?? "x", abstractSyntax ?? "x", contextID, result)
    }
    
    public func length() -> Int16 {
        return pcLength
    }
    
    public init?(data:Data) {
       
        let stream = OffsetInputStream(data: data)
        
        stream.open()
        
        guard let presentationContextType = stream.read(length: 1) else { return nil }
        if presentationContextType.toUInt8() != ItemType.acPresentationContext.rawValue
           && presentationContextType.toUInt8() != ItemType.rqPresentationContext.rawValue {
            
            return nil
        }
        
        stream.forward(by: 1)// reserved byte
        
        // we don't need the length, except maybe to check all bounds are right
        // guard let itemLength = stream.read(length: 2) else { return nil }
        // let presentationContextItemLength = itemLength.toInt16(byteOrder: .BigEndian)
        stream.forward(by: 2)
        
        guard let contextID = stream.read(length: 1) else { return nil }
        self.contextID = contextID.toUInt8(byteOrder: .BigEndian)
        
        stream.forward(by: 1)// reserved byte
        
        switch presentationContextType.toUInt8(byteOrder: .BigEndian) {
        case ItemType.acPresentationContext.rawValue:
            // result / reason
            guard let result = stream.read(length: 1) else { return nil }
            self.result = result.toUInt8(byteOrder: .BigEndian)
            
        case ItemType.rqPresentationContext.rawValue:
            stream.forward(by: 1)
            
        default:
            return nil
        }

        
        stream.forward(by: 1)// reserved byte
        
        if presentationContextType.toUInt8() == ItemType.acPresentationContext.rawValue {
            //
            // 1 transfer syntax subitem
            //
            
            // when result has a value other than 0 (acceptance), transfer syntax shall not be tested when received
            if self.result != 0 { return }
            
            guard let itemType = stream.read(length: 1) else { return nil }
            if itemType.toInt8(byteOrder: .BigEndian) != ItemType.transferSyntax.rawValue { return nil }
            
            stream.forward(by: 1)// reserved byte
            
            guard let itemLength = stream.read(length: 2) else { return nil }
            let transferSyntaxItemLength = itemLength.toUInt16(byteOrder: .BigEndian)
            
            guard let transferSyntaxName = stream.read(length: Int(transferSyntaxItemLength)) else { return nil }
            // in fact you don't need that ?
            self.acceptedTransferSyntax = transferSyntaxName.toString()
            // you need that
            self.transferSyntaxes.append(transferSyntaxName.toString())
            
            
            
        } else if presentationContextType.toUInt8() == ItemType.rqPresentationContext.rawValue {
            
            //
            // 1 abstract syntax subitem
            //
            guard let itemType = stream.read(length: 1) else { return nil }
            // Todo: expects abstract syntax item type 30H error handling
            if itemType.toUInt8() != ItemType.abstractSyntax.rawValue { return nil }
            
            stream.forward(by: 1)// reserved byte
            
            guard let itemLength = stream.read(length: 2) else { return nil }
            let abstractSyntaxItemLength = itemLength.toUInt16()
            
            guard let abstractSyntaxName = stream.read(length: Int(abstractSyntaxItemLength)) else { return nil }
            self.abstractSyntax = abstractSyntaxName.toString()
            
            //
            // 1+ transfer syntaxes subitems
            //
            while stream.hasReadableBytes {
                guard let itemType = stream.read(length: 1) else { return nil }
                // Todo: expects abstract syntax item type 30H error handling
                if itemType.toUInt8() != ItemType.transferSyntax.rawValue { return nil }
                
                stream.forward(by: 1)// reserved byte
                
                guard let itemLength = stream.read(length: 2) else { return nil }
                let transferSyntaxItemLength = itemLength.toUInt16()
                
                guard let transferSyntaxName = stream.read(length: Int(transferSyntaxItemLength)) else { return nil }
                if let tsn = String(bytes: transferSyntaxName, encoding: .utf8) {
                    self.transferSyntaxes.append(tsn)
                }
            }
        } else {
            Logger.error("Unknown presentation context type")
        }
    }
    
    
    /**
     - Parameter onlyAcceptedTS: setup Presentation Context with the given Transfer Syntax. Used
     by AssociationAC message to reply only with the Association accepted Transfer Syntax, where in AssociationRQ,
     the Presentation Context presents all the supported TS.
     */
    public func data(onlyAcceptedTS:String? = nil) -> Data {
        // ABSTRACT SYNTAX Data
        var asData = Data()
        
        if self.abstractSyntax != nil {
            let asLength = UInt16(self.abstractSyntax.data(using: .utf8)!.count)
            asData.append(uint8: ItemType.abstractSyntax.rawValue, bigEndian: true) // 30H
            asData.append(byte: 0x00)
            asData.append(uint16: asLength, bigEndian: true)
            asData.append(self.abstractSyntax.data(using: .utf8)!)
        }
        
        // TRANSFER SYNTAXES Data
        var tsData = Data()        
        if onlyAcceptedTS != nil {
            let tsLength = UInt16(onlyAcceptedTS!.data(using: .utf8)!.count)
            tsData.append(uint8: ItemType.transferSyntax.rawValue, bigEndian: true)
            tsData.append(byte: 0x00) // RESERVED
            tsData.append(uint16: tsLength, bigEndian: true)
            tsData.append(onlyAcceptedTS!.data(using: .utf8)!)
        } else {
            for ts in self.transferSyntaxes {
                let tsLength = UInt16(ts.data(using: .utf8)!.count)
                tsData.append(uint8: ItemType.transferSyntax.rawValue, bigEndian: true)
                tsData.append(byte: 0x00) // RESERVED
                tsData.append(uint16: tsLength, bigEndian: true)
                tsData.append(ts.data(using: .utf8)!)
            }
        }
        
        // Presentation Context
        var pcData = Data()
        if self.abstractSyntax == nil {
            pcData.append(uint8: ItemType.acPresentationContext.rawValue, bigEndian: true)
        }else {
            pcData.append(uint8: ItemType.rqPresentationContext.rawValue, bigEndian: true)
        }
        pcData.append(byte: 0x00) // RESERVED
        
        let pcLength = UInt16(4 + asData.count + tsData.count)
        pcData.append(uint16: pcLength, bigEndian: true)
        
        pcData.append(uint8: self.contextID, bigEndian: true) // Presentation Context ID
        pcData.append(byte: 0x00)
        
        if let r = self.result {
            pcData.append(uint8: r)
        } else {
            pcData.append(byte: 0x00)
        }
        
        pcData.append(byte: 0x00)
        pcData.append(asData)
        pcData.append(tsData)
        
        return pcData
    }
}
