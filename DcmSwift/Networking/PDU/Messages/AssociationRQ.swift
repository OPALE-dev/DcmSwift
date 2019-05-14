//
//  AssociationRQ.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 03/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation
import SwiftyBeaver

public class AssociationRQ: PDUMessage {    
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
        data.append(Data(bytes: [0x00, 0x01])) // Protocol version
        data.append(byte: 0x00, count: 2)
        data.append(association.calledAET.paddedTitleData()!) // Called AET Title
        data.append(association.callingAET.paddedTitleData()!) // Calling AET Title
        data.append(Data(repeating: 0x00, count: 32)) // 00H
        
        data.append(apData)
        data.append(pcData)
        data.append(uiData)
        
        return data
    }
    
    
    override public func decodeData(data: Data) -> Bool {
        return true
    }
    
    
    public override func messageName() -> String {
        return "A-ASSOCIATE-RQ"
    }
    
    
    override public func handleResponse(data:Data, completion: PDUCompletion) -> PDUMessage?  {
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

                    completion(true, response, nil)
                    return response
                }
            }
            else if command == PDUType.associationRJ.rawValue {
                if let response = PDUDecoder.shared.receiveAssocMessage(data: data, pduType: PDUType.associationRJ, association: self.association) as? PDUMessage {
                    completion(false, response, response.errors.first)
                    return response
                }
            }
        }
        
        completion(false, nil, nil)
        return nil
    }
}
