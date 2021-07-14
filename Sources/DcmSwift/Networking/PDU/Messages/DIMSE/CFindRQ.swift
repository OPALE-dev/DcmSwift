//
//  CFindRQ.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 The `CFindRQ` class represents a C-FIND-RQ message of the DICOM standard.
 
 It inherits most of its behavior from `DataTF` and `PDUMessage` and their
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 */
public class CFindRQ: DataTF {
    /// the query dataset given by the user
    public var queryDataset:DataSet?
    /// the query results of the C-FIND
    public var queryResults:[Any] = []
    
    public override func messageName() -> String {
        return "C-FIND-RQ"
    }
    
    /**
     This implementation of `data()` encodes PDU and Command part of the `C-FIND-RQ` message.
     */
    public override func data() -> Data? {
        var data = Data()

        // fetch accepted PC
        guard let key = association.acceptedPresentationContexts.keys.first,
              let spc = association.presentationContexts[key] else {
            return nil
        }
        
        // build comand dataset
        let pdvDataset = DataSet()
        _ = pdvDataset.set(value: CommandField.C_FIND_RQ.rawValue.bigEndian, forTagName: "CommandField")
        _ = pdvDataset.set(value: spc.abstractSyntax as Any, forTagName: "AffectedSOPClassUID")
        _ = pdvDataset.set(value: UInt16(1).bigEndian, forTagName: "MessageID")
        _ = pdvDataset.set(value: UInt16(0).bigEndian, forTagName: "Priority")
        _ = pdvDataset.set(value: UInt16(1).bigEndian, forTagName: "CommandDataSetType")

        // get command dataset length for CommandGroupLength element
        let commandGroupLength = pdvDataset.toData(vrMethod: .Implicit, byteOrder: .LittleEndian).count
        _ = pdvDataset.set(value: UInt32(commandGroupLength).bigEndian, forTagName: "CommandGroupLength")

        // build PDV data
        var pdvData = Data()
        let pdvLength = commandGroupLength + 14
        pdvData.append(uint32: UInt32(pdvLength), bigEndian: true)
        pdvData.append(uint8: association.presentationContexts.keys.first!, bigEndian: true) // Context
        pdvData.append(byte: 0x03) // Flags
        pdvData.append(pdvDataset.toData(vrMethod: .Implicit, byteOrder: .LittleEndian))

        // build PDU data
        let pduLength = UInt32(pdvLength + 4)
        data.append(uint8: self.pduType.rawValue, bigEndian: true)
        data.append(byte: 0x00) // reserved
        data.append(uint32: pduLength, bigEndian: true)
        data.append(pdvData)

        return data
    }
    
    /**
     This implementation of `messagesData()` encodes the query dataset into a valid `DataTF` message.
     */
    public override func messagesData() -> [Data] {
        var data = Data()
        
        // fetch accepted TS from association
        guard let ats = self.association.acceptedTransferSyntax,
              let transferSyntax = TransferSyntax(ats) else {
            return []
        }
                
        // encode query dataset elements
        if let qrDataset = self.queryDataset, qrDataset.allElements.count > 0 {
            var datasetData = Data()
                        
            for e in qrDataset.allElements {
                datasetData.append(e.toData(transferSyntax: transferSyntax))
            }
            
            var pdvData2 = Data()
            let pdvLength2 = datasetData.count + 2
            
            pdvData2.append(uint32: UInt32(pdvLength2), bigEndian: true)
            pdvData2.append(uint8: association.presentationContexts.keys.first!, bigEndian: true) // Context
            pdvData2.append(byte: 0x02) // Flags
            pdvData2.append(datasetData)
            
            let pduLength2 = UInt32(pdvLength2 + 4)
            data.append(uint8: self.pduType.rawValue, bigEndian: true)
            data.append(byte: 0x00) // reserved
            data.append(uint32: pduLength2, bigEndian: true)
            data.append(pdvData2)
        }
        
        return [data]
    }
    
    
    /**
     Not implemeted yet
     
     TODO: we actually don't read C-FIND-RQ message, yet! (server side)
     */
    public override func decodeData(data: Data) -> DIMSEStatus.Status {
        return .Success
    }
    
    
    /**
     This implementation of `handleResponse()` decodes the received data as `CFindRSP` using `PDUDecoder`.
     
     This method is called by NIO channelRead() method to decode DIMSE messages.
     The method is directly fired from the originator message of type `CFindRQ`.

     It benefits from the proximity between the originator (`CFindRQ`) message and it response (`CFindRSP`)
     to fill the `queryResults` property with freshly received dataset (`CFindRSP.studiesDataset`).
     */
    override public func handleResponse(data: Data) -> PDUMessage? {
        if let command:UInt8 = data.first {
            if command == self.pduType.rawValue {
                if let message = PDUDecoder.shared.receiveDIMSEMessage(data: data, pduType: PDUType.dataTF, commandField: .C_FIND_RSP, association: self.association) as? CFindRSP {
                                        
                    // fill result with dataset from each DATA_TF message
                    if let studiesDataset = message.studiesDataset {
                        self.queryResults.append(studiesDataset.toJSONArray())
                    }
                    
                    return message
                }
            }
        }
        return nil
    }
}
