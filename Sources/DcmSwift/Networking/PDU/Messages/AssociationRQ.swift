//
//  AssociationRQ.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation


public class AssociationRQ: PDUMessage {
    public var remoteCalledAETitle:String?
    public var remoteCallingAETitle:String?
    
    public override func data() -> Data {
        var data = Data()
        
        let apData = association.applicationContext.data()
        var pcData = Data()
        for (_, pc) in association.presentationContexts {
            pcData.append(pc.data())
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
    
    
    override public func decodeData(data: Data) -> DIMSEStatus.Status {
        var offset = 0
        
        // PDU type
        let pcPduType = data.first
        if pcPduType != 0x01 {
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
        self.remoteCalledAETitle = data.subdata(in: offset..<offset+16).toString().trimmingCharacters(in: .whitespaces)
        offset += 16
        self.remoteCallingAETitle = data.subdata(in: offset..<offset+16).toString().trimmingCharacters(in: .whitespaces)
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
        while pcType == ItemType.rqPresentationContext.rawValue {
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
        
        Logger.info(" ")
        
        return .Success
    }
    
    
    public override func messageName() -> String {
        return "A-ASSOCIATE-RQ"
    }
    
    
    override public func handleResponse(data:Data) -> PDUMessage?  {
        if let command:UInt8 = data.first {
            if command == PDUType.associationAC.rawValue {
                if let response = PDUDecoder.shared.receiveAssocMessage(data: data, pduType: PDUType.associationAC, association: self.association) as? AssociationAC {
                    debugDescription = "  -> Called AE Title: \(response.remoteCalledAETitle ?? "UNDEFINED")\n"
                    debugDescription.append("  -> Calling AE Title: \(response.remoteCallingAETitle ?? "UNDEFINED")\n")
                    debugDescription.append("  -> Application Context Name: \(response.association.remoteApplicationContext?.applicationContextName ?? "UNDEFINED")\n")
                    debugDescription.append("  -> Presentation Contexts:\n")
                    for (_,pc) in response.association.acceptedPresentationContexts {
                        debugDescription.append("    -> Context ID: \(pc.contextID ?? 0)\n")
                        debugDescription.append("      -> Accepted Transfer Syntax(es): \(pc.transferSyntaxes.description )\n")
                    }
                    debugDescription.append("  -> User Informations:\n")
                    debugDescription.append("    -> Remote Max PDU: \(response.association.maxPDULength)\n")
                    debugDescription.append("    -> Implementation class UID: \(response.association.remoteImplementationUID ?? "")\n")
                    debugDescription.append("    -> Implementation version: \(self.association.remoteImplementationVersion ?? "")\n")

                    return response
                }
            }
            else if command == PDUType.associationRJ.rawValue {
                if let response = PDUDecoder.shared.receiveAssocMessage(data: data, pduType: PDUType.associationRJ, association: self.association) as? PDUMessage {
                    return response
                }
            }
        }

        return nil
    }
}
