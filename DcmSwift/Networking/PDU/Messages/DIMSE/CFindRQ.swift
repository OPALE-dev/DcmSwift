//
//  CFindRQ.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 03/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation


class CFindRQ: DataTF {
    public var queryDataset:DataSet?
    
    public override func data() -> Data {
        var data = Data()
        
        let pdvDataset = DataSet()
        _ = pdvDataset.set(value: CommandField.C_FIND_RQ.rawValue.bigEndian, forTagName: "CommandField")
        _ = pdvDataset.set(value: self.association.sop, forTagName: "AffectedSOPClassUID")
        _ = pdvDataset.set(value: UInt16(1).bigEndian, forTagName: "MessageID")
        _ = pdvDataset.set(value: UInt16(0).bigEndian, forTagName: "Priority")
        _ = pdvDataset.set(value: UInt16(1).bigEndian, forTagName: "CommandDataSetType")
        
        let commandGroupLength = pdvDataset.toData().count
        _ = pdvDataset.set(value: UInt32(commandGroupLength).bigEndian, forTagName: "CommandGroupLength")
        
        var pdvData = Data()
        let pdvLength = commandGroupLength + 14
        pdvData.append(uint32: UInt32(pdvLength), bigEndian: true)
        pdvData.append(uint8: association.contextID, bigEndian: true) // Context
        pdvData.append(byte: 0x03) // Flags
        pdvData.append(pdvDataset.toData())
        
        let pduLength = UInt32(pdvLength + 4)
        data.append(uint8: self.pduType.rawValue, bigEndian: true)
        data.append(byte: 0x00) // reserved
        data.append(uint32: pduLength, bigEndian: true)
        data.append(pdvData)
        
        return data
    }
    
    
    public override func messageData() -> Data? {
        var data = Data()
        
        if let qrDataset = self.queryDataset, qrDataset.allElements.count > 0 {
            var datasetData = Data()
            
            for e in qrDataset.allElements {
                datasetData.append(e.toData(vrMethod: .Explicit, byteOrder: .LittleEndian))
            }
            
            var pdvData2 = Data()
            let pdvLength2 = datasetData.count + 2
            
            pdvData2.append(uint32: UInt32(pdvLength2), bigEndian: true)
            pdvData2.append(uint8: association.contextID, bigEndian: true) // Context
            pdvData2.append(byte: 0x02) // Flags
            pdvData2.append(datasetData)
            
            let pduLength2 = UInt32(pdvLength2 + 4)
            data.append(uint8: self.pduType.rawValue, bigEndian: true)
            data.append(byte: 0x00) // reserved
            data.append(uint32: pduLength2, bigEndian: true)
            data.append(pdvData2)
        }
        
        return data
    }
    
    
    public override func decodeData(data: Data) -> Bool {
        return false
    }
    
    
    override public func handleResponse(data: Data, completion: (Bool, PDUMessage?, DicomError?) -> Void) -> PDUMessage? {
        if let command:UInt8 = data.first {
            if command == self.pduType.rawValue {
                if let message = PDUDecoder.shared.receiveDIMSEMessage(data: data, pduType: PDUType.dataTF, commandField: CommandField.C_FIND_RSP, association: self.association) as? PDUMessage {
                    return message
                }
            }
        }
        //completion(false, nil, nil)
        return nil
    }
}
