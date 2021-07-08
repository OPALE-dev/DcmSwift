//
//  EchoRQ.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

public class CEchoRQ: DataTF {
    public override func messageName() -> String {
        return "C-ECHO-RQ"
    }
    
    public override func data() -> Data {
        var data = Data()
          
        let pdvDataset = DataSet()
        _ = pdvDataset.set(value: CommandField.C_ECHO_RQ.rawValue.bigEndian, forTagName: "CommandField")
        _ = pdvDataset.set(value: self.association.abstractSyntax, forTagName: "AffectedSOPClassUID")
        _ = pdvDataset.set(value: self.messageID, forTagName: "MessageID")
        _ = pdvDataset.set(value: UInt16(257).bigEndian, forTagName: "CommandDataSetType")

        // Why implicit endian ??.LittleEndian
        let commandGroupLength = pdvDataset.toData(vrMethod: .Implicit, byteOrder: .LittleEndian).count
        _ = pdvDataset.set(value: UInt32(commandGroupLength).bigEndian, forTagName: "CommandGroupLength")
        
        var pdvData = Data()
        let pdvLength = commandGroupLength + 14
        pdvData.append(uint32: UInt32(pdvLength), bigEndian: true)
        pdvData.append(uint8: association.presentationContexts.keys.first!, bigEndian: true) // Context
        pdvData.append(byte: 0x03) // Flags
        pdvData.append(pdvDataset.toData(vrMethod: .Implicit, byteOrder: .LittleEndian))
        
        let pduLength = UInt32(pdvLength + 4)
        data.append(uint8: self.pduType.rawValue, bigEndian: true)
        data.append(byte: 0x00) // reserved
        data.append(uint32: pduLength, bigEndian: true)
        data.append(pdvData)
        
        return data
    }
    
    public override func decodeData(data: Data) -> DIMSEStatus.Status {
        print("TODO: decodeData")
        return .Success
    }
    
    public override func handleResponse(data:Data) -> PDUMessage? {
        if let type:UInt8 = data.first {
            if type == PDUType.dataTF.rawValue {
                if let message = PDUDecoder.shared.receiveDIMSEMessage(data: data, pduType: PDUType.dataTF, commandField: .C_ECHO_RSP, association: self.association) as? PDUMessage {

                    return message
                }
            }
        }
        return nil
    }
    
    public override func handleRequest() -> PDUMessage? {
        if let response = PDUEncoder.shared.createDIMSEMessage(pduType: .dataTF, commandField: .C_ECHO_RSP, association: self.association) as? PDUMessage {
            
            response.requestMessage = self
            
            return response
        }
        return nil
        
    }
}
