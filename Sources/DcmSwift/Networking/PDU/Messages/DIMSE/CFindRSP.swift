//
//  CFindRSP.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 04/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 The `CFindRSP` class represents a C-FIND-RSP message of the DICOM standard.
 
 It inherits most of its behavior from `DataTF` and `PDUMessage` and their
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/medical/dicom/current/output/chtml/part07/sect_9.3.2.2.html
 */
public class CFindRSP: DataTF {
    public var resultsDataset:DataSet?
    
    
    public override func messageName() -> String {
        return "C-FIND-RSP"
    }
    
    
    public override func messageInfos() -> String {
        return "\(dimseStatus.status)"
    }
    
    public override func data() -> Data? {
        if let pc = self.association.acceptedPresentationContexts.values.first,
           let transferSyntax = TransferSyntax(TransferSyntax.implicitVRLittleEndian) {
            let commandDataset = DataSet()
            _ = commandDataset.set(value: CommandField.C_FIND_RSP.rawValue.bigEndian, forTagName: "CommandField")
            _ = commandDataset.set(value: pc.abstractSyntax as Any, forTagName: "AffectedSOPClassUID")
            
            if let request = self.requestMessage {
                _ = commandDataset.set(value: request.messageID, forTagName: "MessageIDBeingRespondedTo")
            }
            _ = commandDataset.set(value: UInt16(257).bigEndian, forTagName: "CommandDataSetType")
            _ = commandDataset.set(value: UInt16(0).bigEndian, forTagName: "Status")
            
            let pduData = PDUData(
                pduType: self.pduType,
                commandDataset: commandDataset,
                abstractSyntax: pc.abstractSyntax,
                transferSyntax: transferSyntax,
                pcID: pc.contextID, flags: 0x03)
            
            return pduData.data()
        }
        
        return nil
    }
    
    
    override public func decodeData(data: Data) -> DIMSEStatus.Status {
        let status = super.decodeData(data: data)
        
        let pc = association.acceptedPresentationContexts[association.acceptedPresentationContexts.keys.first!]
        let ts = pc?.transferSyntaxes.first
        
        if ts == nil {
            Logger.error("No transfer syntax found, refused")
            return .Refused
        }
        
        let transferSyntax = TransferSyntax(ts!)
                     
        // if the PDU message as been segmented
        if commandDataSetType == nil {
            // read dataset data
            do {
                let datasetData = try stream.read(length: Int(self.pdvLength - 2))// else {
                //    Logger.error("Cannot read dataset data")
                //    return .Refused
                //}
            
            
            
                let dis = DicomInputStream(data: datasetData)
                
                dis.vrMethod    = transferSyntax!.vrMethod
                dis.byteOrder   = transferSyntax!.byteOrder
                
                if commandField == .C_FIND_RSP {
                    if let resultDataset = try? dis.readDataset(enforceVR: false) {
                        resultsDataset = resultDataset
                    }
                }
            } catch {
                Logger.error("Cannot read dataset data")
                return .Refused
            }
            
        // if the PDU message is complete, and commandDataSetType indicates presence of dataset
        } else if commandDataSetType == 0 {
            do {
                // read data PDV length
                let dataPDVLength = try stream.read(length: 4).toInt32(byteOrder: .BigEndian)// else {
                //    Logger.error("Cannot read data PDV Length (CFindRSP)")
                //    return .Refused
                //}
                            
                // jump context + flags
                try stream.forward(by: 2)
                
                // read dataset data
                let datasetData = try stream.read(length: Int(dataPDVLength - 2))// else {
                //    Logger.error("Cannot read dataset data")
                //    return .Refused
                //}
                
                let dis = DicomInputStream(data: datasetData)
                
                dis.vrMethod    = transferSyntax!.vrMethod
                dis.byteOrder   = transferSyntax!.byteOrder
                
                if commandField == .C_FIND_RSP {
                    if let resultDataset = try? dis.readDataset() {
                        resultsDataset = resultDataset
                    }
                }
            } catch {
                Logger.error("Cannot read data PDV Length (CFindRSP)")
                Logger.error("Cannot read dataset data")
                return .Refused
            }
        }
        
        return status
    }
}
