//
//  EchoRSP.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

public class CEchoRSP: DataTF {
    public override func messageName() -> String {
        return "C-ECHO-RSP"
    }
    
    public override func data() -> Data {
        var data = Data()
        
        if let pc = self.association.acceptedPresentationContexts.values.first {
            let pdvDataset = DataSet()
            _ = pdvDataset.set(value: CommandField.C_ECHO_RSP.rawValue.bigEndian, forTagName: "CommandField")
            _ = pdvDataset.set(value: pc.abstractSyntax as Any, forTagName: "AffectedSOPClassUID")
            if let request = self.requestMessage {
                _ = pdvDataset.set(value: request.messageID, forTagName: "MessageIDBeingRespondedTo")
            }
            _ = pdvDataset.set(value: UInt16(257).bigEndian, forTagName: "CommandDataSetType")
            _ = pdvDataset.set(value: UInt16(0).bigEndian, forTagName: "Status")
            
            let commandGroupLength = pdvDataset.toData().count
            _ = pdvDataset.set(value: UInt32(commandGroupLength).bigEndian, forTagName: "CommandGroupLength")
            
            var pdvData = Data()
            let pdvLength = commandGroupLength + 14
            pdvData.append(uint32: UInt32(pdvLength), bigEndian: true)
            pdvData.append(uint8: pc.contextID, bigEndian: true) // Context
            pdvData.append(byte: 0x03) // Flags
            pdvData.append(pdvDataset.toData())
            
            let pduLength = UInt32(pdvLength + 4)
            data.append(uint8: self.pduType.rawValue, bigEndian: true)
            data.append(byte: 0x00) // reserved
            data.append(uint32: pduLength, bigEndian: true)
            data.append(pdvData)
        }
        
        return data
    }

    public override func decodeData(data: Data) -> DIMSEStatus.Status {
        super.decodeDIMSEStatus(data: data)
        
        if let s = self.dimseStatus {
            return s.status
        }
        
        return .Refused
    }
}

