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
    public var studiesDataset:DataSet?
    
    
    public override func messageName() -> String {
        return "C-FIND-RSP"
    }
    
    
    public override func messageInfos() -> String {
        return "\(dimseStatus.status)"
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
        
        print("commandDataSetType \(commandDataSetType)")
             
        // if the PDU message as been segmented
        if commandDataSetType == nil {
            // read dataset data
            guard let datasetData = stream.read(length: Int(self.pdvLength - 2)) else {
                Logger.error("Cannot read dataset data")
                return .Refused
            }
            
            let dis = DicomInputStream(data: datasetData)
            
            dis.vrMethod    = transferSyntax!.vrMethod
            dis.byteOrder   = transferSyntax!.byteOrder
            
            if commandField == .C_FIND_RSP {
                if let resultDataset = try? dis.readDataset(enforceVR: false) {
                    studiesDataset = resultDataset
                }
            }
            
        // if the PDU message is complete, and commandDataSetType indicates presence of dataset
        } else if commandDataSetType == 0 {
            // read data PDV length
            guard let dataPDVLength = stream.read(length: 4)?.toInt32(byteOrder: .BigEndian) else {
                Logger.error("Cannot read data PDV Length (CFindRSP)")
                return .Refused
            }
                        
            // jump context + flags
            stream.forward(by: 2)
            
            // read dataset data
            guard let datasetData = stream.read(length: Int(dataPDVLength - 2)) else {
                Logger.error("Cannot read dataset data")
                return .Refused
            }
            
            let dis = DicomInputStream(data: datasetData)
            
            dis.vrMethod    = transferSyntax!.vrMethod
            dis.byteOrder   = transferSyntax!.byteOrder
            
            if commandField == .C_FIND_RSP {
                if let resultDataset = try? dis.readDataset() {
                    studiesDataset = resultDataset
                }
            }
        }
        
        return status
    }
}
