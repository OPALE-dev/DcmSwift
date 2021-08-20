//
//  AssociationRQ.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 The `AssociationRQ` class represents a A-ASSOCIATE-RQ message of the DICOM standard.
 
 It inherits most of its behavior from the `PDUMessage` class and its
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/dicom/2013/output/chtml/part08/sect_9.3.html#sect_9.3.2
 */
public class AssociationRQ: PDUMessage {
    public var remoteCalledAETitle:String?
    public var remoteCallingAETitle:String?
    
    
    /// Full name of PDU AssociationRQ
    public override func messageName() -> String {
        return "A-ASSOCIATE-RQ"
    }
    
    
    public override func messageInfos() -> String {
        if let called = remoteCalledAETitle, let calling = remoteCallingAETitle {
            return "\(calling) > \(called)"
        }
        
        return super.messageInfos()
    }
    
    /**
     Builds the ASSOCIATE-RQ message
     
     ASSOCIATE_RQ consists of:
     - pdu type
     - 1 reserved byte
     - pdu length
     - protocol version
     - 2 reserved bytes
     - called AE title
     - 32 reserved bytes
     - variable items : one application item, 1 or more presentation context items and 1 user info item
     
     - Note: The variable items are builded first because we need the length in the 3rd field (the other fields have a fixed length), PDU length
     
     - Returns: the ASSOCIATE-RQ bytes
     */
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
        data.append(association.calledAE.paddedTitleData()!) // Called AET Title
        data.append(association.callingAE!.paddedTitleData()!) // Calling AET Title
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
        do {
            let applicationContext = try ApplicationContext(data: acData)// else {
            //    Logger.error("Missing application context. Abort.")
            //    return .Refused
            //}
            offset += acData.count
            self.association.remoteApplicationContext = applicationContext
        } catch {
            Logger.error("Missing application context. Abort.")
            return .Refused
        }

        
        // parse presentation context
        var pcType = data.subdata(in: offset..<offset + 1).toInt8()
        while pcType == ItemType.rqPresentationContext.rawValue {
            offset += 2
            
            let pcLength = data.subdata(in: offset..<offset + 2).toInt16().bigEndian
            offset += 2
            
            let pcData = data.subdata(in: offset-4..<offset+Int(pcLength))
            
            do {
                let presentationContext = try PresentationContext(data: pcData)// {
                self.association.acceptedPresentationContexts[presentationContext.contextID] = presentationContext
                //}
                
            } catch {
                Logger.error("Can't read presentation context")
            }
            
            offset += Int(pcLength)
            pcType = data.subdata(in: offset..<offset + 1).toInt8()
        }
        
        // read user info
        offset = offset + 4
        let userInfoData = data.subdata(in: offset..<data.count)
        
        do {
            let userInfo = try UserInfo(data: userInfoData)// else {
            //    Logger.warning("No user information values provided. Abort")
            //    return .Refused
            //}
            
            self.association?.maxPDULength = userInfo.maxPDULength
            self.association?.remoteImplementationUID = userInfo.implementationUID
            self.association?.remoteImplementationVersion = userInfo.implementationVersion
            
        } catch {
            Logger.warning("No user information values provided. Abort")
            return .Refused
        }
        

        self.association?.associationAccepted = true
        
        return .Success
    }

    
    
    override public func handleResponse(data:Data) -> PDUMessage?  {
        if let command:UInt8 = data.first {
            if command == PDUType.associationAC.rawValue {
                if let response = PDUDecoder.receiveAssocMessage(
                    data: data,
                    pduType: PDUType.associationAC,
                    association: self.association
                ) as? AssociationAC {
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
                if let response = PDUDecoder.receiveAssocMessage(
                    data: data,
                    pduType: PDUType.associationRJ,
                    association: self.association
                ) as? PDUMessage {
                    return response
                }
            }
        }

        return nil
    }
    
    
    public override func handleRequest() -> PDUMessage? {
        if let response = PDUEncoder.createAssocMessage(
            pduType: PDUType.associationAC,
            association: self.association
        ) as? PDUMessage {
            response.requestMessage = self
            
            return response
        }
        return nil
    }
}
