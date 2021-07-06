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
        
        var vrMethod: VRMethod = .Explicit
        var byteOrder: ByteOrder  = .LittleEndian

        
        if let transferSyntax = self.association.acceptedTransferSyntax {
            Logger.debug(">>> TRANSFER SYNTAX KNOWN")
            let tsName  = DicomSpec.shared.nameForUID(withUID: transferSyntax)
            Logger.debug(tsName)
            
            if tsName == TransferSyntax.implicitVRLittleEndian {
                vrMethod    = .Implicit
                byteOrder   = .LittleEndian
            } else if tsName == TransferSyntax.explicitVRBigEndian {
                vrMethod    = .Explicit
                byteOrder   = .BigEndian
            } else if tsName == TransferSyntax.explicitVRLittleEndian {
                vrMethod    = .Explicit
                byteOrder   = .LittleEndian
            }
            
        } else {
            Logger.debug(">>> TRANSFER SYNTAX UNKNOWN")
            vrMethod    = .Explicit
            byteOrder   = .LittleEndian
            // TODO warning
            // Little endian explicit
        }
        
        Logger.debug("---------------------------------------------------");
        Logger.debug("(VR METHOD) \(vrMethod), (BYTE ORDER) \(byteOrder)");
        Logger.debug("---------------------------------------------------");
        
        // Why implicit endian ??
        let commandGroupLength = pdvDataset.toData(vrMethod: vrMethod, byteOrder: byteOrder).count
        _ = pdvDataset.set(value: UInt32(commandGroupLength).bigEndian, forTagName: "CommandGroupLength")
        
        var pdvData = Data()
        let pdvLength = commandGroupLength + 14
        pdvData.append(uint32: UInt32(pdvLength), bigEndian: true)
        pdvData.append(uint8: association.presentationContexts.keys.first!, bigEndian: true) // Context
        pdvData.append(byte: 0x03) // Flags
        pdvData.append(pdvDataset.toData(vrMethod: vrMethod, byteOrder: byteOrder))
        
        let pduLength = UInt32(pdvLength + 4)
        data.append(uint8: self.pduType.rawValue, bigEndian: true)
        data.append(byte: 0x00) // reserved
        data.append(uint32: pduLength, bigEndian: true)
        data.append(pdvData)
        
        return data
    }
    
    public override func decodeData(data: Data) -> Bool {
        print("TODO: decodeData")
        return true
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
