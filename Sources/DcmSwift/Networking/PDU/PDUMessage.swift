//
//  PDUMessage.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 02/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation


/**
 The `PDUResponsable` protocol indicates if the target class should manage the response handling by itself, using the `handleResponse()` method.
 This allows the `DicomAssociation` class to automatically decode the corresponding response for a sent request. For example, the association will
 call the `handleResponse()` method of the sent `CEchoRQ` object to automatically decode the corresponding response as a `CEchoRSP` type of message.
 */
public protocol PDUResponsable {
    func handleResponse(data:Data) -> PDUMessage?
    func handleRequest() -> PDUMessage?
}


/**
 `PDUMessage` is a superclass used to form Protocol Data Units type of messages.
 */
public class PDUMessage:
    CustomStringConvertible, PDUResponsable, PDUDecodable, PDUEncodable {
    
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
    public var receivedData:Data = Data()
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
    
    
    
    public var description: String {
        "\(messageName())"
    }
    
    
    /**
     The human readable name of the DICOM message
     */
    public func messageName() -> String {
        return "UNKNOW-DIMSE"
    }
    
    
    public func messageInfos() -> String {
        return ""
    }
    
    
    public func messagesData() -> [Data] {
        // if let p = self.pduType {
        //     Logger.warning("Not implemented yet \(#function) \(p)")
        // }
        return []
    }
    
    
    /**
     Encoded representation of the PDUMessage as binary data
     */
    public func data() -> Data? {
        if let p = self.pduType {
            Logger.warning("Not implemented yet \(#function) \(p)")
        }
        return nil
    }
    
    
    public func decodeData(data:Data) -> DIMSEStatus.Status {
        stream = OffsetInputStream(data: data)
                
        stream.open()
        
        guard let pt = stream.read(length: 1)?.toInt8() else {
            Logger.error("Cannot read PDU Length")
            return .Refused
        }
 
        // fake read PDU type
        stream.forward(by: 1)
        
        // read PDU length
        guard let pduLength = stream.read(length: 4)?.toInt32(byteOrder: .BigEndian) else {
            Logger.error("Cannot read PDU Length")
            return .Refused
        }
        
        self.pduType    = PDUType(rawValue: UInt8(pt))
        self.pduLength  = Int(pduLength)
        
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
