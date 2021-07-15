//
//  AssociationAC.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 The `AssociationAC` class represents a A-ASSOCIATE-AC message of the DICOM standard.

 It inherits most of its behavior from the `PDUMessage` class and its
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/dicom/2013/output/chtml/part08/sect_9.3.html#sect_9.3.3
 */
public class AssociationAC: PDUMessage {
    public var remoteCalledAETitle:String?
    public var remoteCallingAETitle:String?
    
    
    public override func messageName() -> String {
        return "A-ASSOCIATE-AC"
    }
    
    
    public override func data() -> Data {
        var data = Data()
        
        let apData = association.applicationContext.data()
        var pcData = Data()
        
        for (_, pc) in association.acceptedPresentationContexts {
            pc.result = 0x00
            
            // Weird but works:
            // - we don't need AS in assoc-as
            // - but we need it later for message response
            // NOTE : sometimes you understand DICOM years later. It is a fact.
            let asx = pc.abstractSyntax
            pc.abstractSyntax = nil
            pcData.append(pc.data())
            pc.abstractSyntax = asx
        }
        
        let uiData = association.userInfo.data()
        
        let length = UInt32(2 + 2 + 16 + 16 + 32 + apData.count + pcData.count + uiData.count)
        
        data.append(uint8: self.pduType.rawValue, bigEndian: true)
        data.append(byte: 0x00) // 00H
        data.append(uint32: length, bigEndian: true)
        data.append(Data([0x00, 0x01])) // Protocol version
        data.append(byte: 0x00, count: 2)
        data.append(association.calledAET.paddedTitleData()!) // Called AET Title
        data.append(association.callingAET!.paddedTitleData()!) // Calling AET Title
        data.append(Data(repeating: 0x00, count: 32)) // 00H
        
        data.append(apData)
        data.append(pcData)
        data.append(uiData)
        
        return data
    }
    
    
    public override func decodeData(data:Data) -> DIMSEStatus.Status {
        var offset = 0
        
        // PDU type
        let pcPduType = data.first
        if pcPduType != 0x02 {
            Logger.error("ERROR: Waiting for an A-ASSOCIATE-AC message, received \(String(describing: pcPduType))")
            return .Refused
        }
        offset += 2
        
        // get full length
        let _ = data.subdata(in: offset..<6).toInt32(byteOrder: .BigEndian)
        offset += 4 
        
        // check protocol version
        let protocolVersion = data.subdata(in: offset..<offset+2).toInt16(byteOrder: .BigEndian)
        if Int(protocolVersion) != self.association?.protocolVersion {
            Logger.error("WARN: Wrong protocol version")
            return .Refused
        }
        offset += 2
        
        // reserved bytes
        offset += 2
        
        // TODO: Called / Calling AE Titles
        self.remoteCalledAETitle = data.subdata(in: offset..<offset+16).toString()
        offset += 16
        self.remoteCallingAETitle = data.subdata(in: offset..<offset+16).toString()
        offset += 16
        
        // reserved bytes
        offset += 32
        
        // parse app context
        let acLength = Int(data.subdata(in: offset+2..<offset+4).toInt16(byteOrder: .BigEndian))
        let acData = data.subdata(in: offset..<offset+acLength+4)
        guard let applicationContext = ApplicationContext(data: acData) else {
            Logger.error("Missing application context. Abort.")
            return .Refused
        }
        offset += acData.count
        self.association.remoteApplicationContext = applicationContext
        
        // parse presentation context
        var pcType = data.subdata(in: offset..<offset + 1).toInt8()
        
        while pcType == ItemType.acPresentationContext.rawValue {
            offset += 2
            
            let pcLength = data.subdata(in: offset..<offset + 2).toInt16().bigEndian
            offset += 2
            
            let pcData = data.subdata(in: offset-4..<offset+Int(pcLength))
            
            if let presentationContext = PresentationContext(data: pcData) {
                self.association.acceptedPresentationContexts[presentationContext.contextID] = presentationContext
            }
            
            offset += Int(pcLength)
            pcType = data.subdata(in: offset..<offset + 1).toInt8()
        }

        // read user info
        offset = offset + 4
        let userInfoData = data.subdata(in: offset..<data.count)
        
        guard let userInfo = UserInfo(data: userInfoData) else {
            Logger.warning("No user information values provided. Abort")
            return .Refused
        }

        self.association?.maxPDULength = userInfo.maxPDULength
        self.association?.remoteImplementationUID = userInfo.implementationUID
        self.association?.remoteImplementationVersion = userInfo.implementationVersion
        self.association?.associationAccepted = true
        
        return .Success
    }
    
    
    public override func messagesData() -> [Data] {
        return []
    }
    
    
    public override func handleResponse(data: Data) -> PDUMessage? {
        if let command:UInt8 = data.first {
            if command == PDUType.dataTF.rawValue {
                if let response = PDUDecoder.receiveAssocMessage(
                    data: data,
                    pduType: PDUType.associationAC,
                    association: self.association
                ) as? AssociationAC {
                    return response
                }
            }
        }
        return nil
    }
}
