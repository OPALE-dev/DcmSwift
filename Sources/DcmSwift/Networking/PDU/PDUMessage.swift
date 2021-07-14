//
//  PDUMessage.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 02/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation


public protocol PDUResponsable {
    func handleResponse(data:Data) -> PDUMessage?
    func handleRequest() -> PDUMessage?
}


public class PDUMessage: PDUResponsable, PDUDecodable, PDUEncodable {
    
    public var pduType:PDUType!
    public var pduLength:Int = -1
    public var pdvLength:Int = -1
    public var commandField:CommandField?
    public var commandDataSetType:Int16?
    public var association:DicomAssociation!
    public var dimseStatus:DIMSEStatus!
    public var flags:UInt8!
    public var errors:[DicomError] = []
    public var debugDescription:String = "No message description"
    public var commandDataset:DataSet!
    public var requestMessage:PDUMessage?
    public var responseDataset:DataSet!
    public var messageID = UInt16(1).bigEndian
    public var stream:OffsetInputStream!
    
    
    
    public init(pduType:PDUType, association:DicomAssociation) {
        self.pduType = pduType
        self.association = association
    }
    
    
    public convenience init(pduType:PDUType, commandField:CommandField, association:DicomAssociation) {
        self.init(pduType: pduType, association: association)
        self.commandField = commandField
    }


    
    public convenience init?(data:Data, pduType:PDUType, association:DicomAssociation) {
        self.init(pduType: pduType, association: association)
        
        if decodeData(data: data) == .Refused {
            return nil
        }
    }
    
    
    public convenience init?(data:Data, pduType:PDUType, commandField:CommandField, association:DicomAssociation) {
        self.init(pduType: pduType, commandField:commandField, association: association)
        
        if decodeData(data: data) == .Refused {
            return nil
        }
    }
    
    
    public func messageName() -> String {
        return "UNKNOW-DIMSE"
    }
    
    public func messagesData() -> [Data] {
//        if let p = self.pduType {
//            Logger.warning("Not implemented yet \(#function) \(p)")
//        }
        return []
    }
    
    
    public func data() -> Data {
        if let p = self.pduType {
            Logger.warning("Not implemented yet \(#function) \(p)")
        }
        return Data()
    }
    
    
    public func decodeData(data:Data) -> DIMSEStatus.Status {
        stream = OffsetInputStream(data: data)
                
        stream.open()
 
        // fake read PDU type + dead byte
        stream.forward(by: 2)
        
        // read PDU length
        guard let pduLength = stream.read(length: 4)?.toInt32(byteOrder: .BigEndian) else {
            Logger.error("Cannot read PDU Length")
            return .Refused
        }
        
        self.pduLength = Int(pduLength)
        
        return .Success
    }
    
    
    public func handleResponse(data:Data) -> PDUMessage? {
        if let p = self.pduType {
            Logger.warning("Not implemented yet \(#function) \(p)")
        }
        return nil
    }

    public func handleRequest() -> PDUMessage? {
        return nil
    }
    
}
