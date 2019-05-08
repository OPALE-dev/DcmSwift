//
//  AssociationRQ.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 03/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation

public class AssociationRQ: PDUMessage {    
    public override func data() -> Data {
        var data = Data()
        
        let apData = association.applicationContext.data()
        let pcData = association.presentationContexts.first!.data()
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
    
    
    override public func handleResponse(data:Data, completion: PDUCompletion) -> PDUMessage?  {
        if let command:UInt8 = data.first {
            if command == PDUType.associationAC.rawValue {
                if let message = PDUDecoder.shared.receiveAssocMessage(data: data, pduType: PDUType.associationAC, association: self.association) as? PDUMessage {
                    completion(true, message, nil)
                    return message
                }
            }
            else if command == PDUType.associationRJ.rawValue {
                if let message = PDUDecoder.shared.receiveAssocMessage(data: data, pduType: PDUType.associationRJ, association: self.association) as? PDUMessage {
                    completion(false, message, message.errors.first)
                    return message
                }
            }
        }
        
        completion(false, nil, nil)
        return nil
    }
}
