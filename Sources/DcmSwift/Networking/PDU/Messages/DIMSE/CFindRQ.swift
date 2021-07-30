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
 
 http://dicom.nema.org/medical/dicom/current/output/chtml/part07/sect_9.3.2.html
 */
public class CFindRQ: DataTF {
    /// the query dataset given by the user
    public var queryDataset:DataSet?
    /// the query results of the C-FIND
    public var queryResults:[Any] = []
    public var resultsDataset:DataSet?
    
    public override func messageName() -> String {
        return "C-FIND-RQ"
    }
    
    
    /**
     This implementation of `data()` encodes PDU and Command part of the `C-FIND-RQ` message.
     */
    public override func data() -> Data? {
        // fetch accepted PC
        guard let pcID = association.acceptedPresentationContexts.keys.first,
              let spc = association.presentationContexts[pcID],
              let transferSyntax = TransferSyntax(TransferSyntax.implicitVRLittleEndian),
              let abstractSyntax = spc.abstractSyntax else {
            return nil
        }
        
        // build comand dataset
        let commandDataset = DataSet()
        _ = commandDataset.set(value: CommandField.C_FIND_RQ.rawValue.bigEndian, forTagName: "CommandField")
        _ = commandDataset.set(value: abstractSyntax as Any, forTagName: "AffectedSOPClassUID")
        _ = commandDataset.set(value: UInt16(1).bigEndian, forTagName: "MessageID")
        _ = commandDataset.set(value: UInt16(0).bigEndian, forTagName: "Priority")
        _ = commandDataset.set(value: UInt16(1).bigEndian, forTagName: "CommandDataSetType")
        
        let pduData = PDUData(
            pduType: self.pduType,
            commandDataset: commandDataset,
            abstractSyntax: abstractSyntax,
            transferSyntax: transferSyntax,
            pcID: pcID, flags: 0x03)
        
        return pduData.data()
    }
    
    
    /**
     This implementation of `messagesData()` encodes the query dataset into a valid `DataTF` message.
     */
    public override func messagesData() -> [Data] {
        // fetch accepted TS from association
        guard let pcID = association.acceptedPresentationContexts.keys.first,
              let spc = association.presentationContexts[pcID],
              let ats = self.association.acceptedTransferSyntax,
              let transferSyntax = TransferSyntax(ats),
              let abstractSyntax = spc.abstractSyntax else {
            return []
        }
                
        // encode query dataset elements
        if let qrDataset = self.queryDataset, qrDataset.allElements.count > 0 {
            let pduData = PDUData(
                pduType: self.pduType,
                commandDataset: qrDataset,
                abstractSyntax: abstractSyntax,
                transferSyntax: transferSyntax,
                pcID: pcID, flags: 0x02)
            
            return [pduData.data()]
        }
        
        return []
    }
    
    
    /**
     Not implemeted yet
     
     TODO: we actually don't read C-FIND-RQ message, yet! (server side)
     */
    public override func decodeData(data: Data) -> DIMSEStatus.Status {
        let status = super.decodeData(data: data)
                
        if stream.readableBytes > 0 {
            let pc = association.acceptedPresentationContexts[association.acceptedPresentationContexts.keys.first!]
            let ts = pc?.transferSyntaxes.first
            
            if ts == nil {
                Logger.error("No transfer syntax found, refused")
                return .Refused
            }
            
            let transferSyntax = TransferSyntax(ts!)
            
            guard let pdvLength = stream.read(length: 4)?.toInt32(byteOrder: .BigEndian) else {
                Logger.error("Cannot read dataset data")
                return .Refused
            }
            
            self.pdvLength = Int(pdvLength)
            
            // jump context + flags
            stream.forward(by: 2)
            
            // read dataset data
            guard let datasetData = stream.read(length: Int(pdvLength - 2)) else {
                Logger.error("Cannot read dataset data")
                return .Refused
            }
            
            let dis = DicomInputStream(data: datasetData)
            
            dis.vrMethod    = transferSyntax!.vrMethod
            dis.byteOrder   = transferSyntax!.byteOrder
            
            if commandField == .C_FIND_RQ {
                if let resultDataset = try? dis.readDataset() {
                    resultsDataset = resultDataset
                }
            }
        }
        
        return status
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
                if let message = PDUDecoder.receiveDIMSEMessage(
                    data: data,
                    pduType: PDUType.dataTF,
                    commandField: .C_FIND_RSP,
                    association: self.association
                ) as? CFindRSP {
                    // fill result with dataset from each DATA-TF message
                    if let studiesDataset = message.resultsDataset {
                        self.queryResults.append(studiesDataset.toJSONArray())
                    }
                    
                    return message
                }
            }
        }
        return nil
    }
}
