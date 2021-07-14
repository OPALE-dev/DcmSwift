//
//  CFindRSP.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 04/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 The `CFindRSP` class represent a C-FIND-RSP message of the DICOM standard.
 
 It inherits most of its behavior from `DataTF` and `PDUMessage` and their
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 */
public class CFindRSP: DataTF {
    public var studiesDataset:DataSet?
    
    
    public override func messageName() -> String {
        return "C-FIND-RSP"
    }
    
    
    override public func decodeData(data: Data) -> DIMSEStatus.Status {
        let status = super.decodeData(data: data)
        
        // if data if available
        if commandDataSetType == 0 {
            let pc = association.acceptedPresentationContexts[association.acceptedPresentationContexts.keys.first!]
            let ts = pc?.transferSyntaxes.first
            
            if ts == nil {
                return .Refused
            }

            let transferSyntax = TransferSyntax(ts!)
                        
            // read data PDV length
            guard let dataPDVLength = stream.read(length: 4)?.toInt32(byteOrder: .BigEndian) else {
                Logger.error("Cannot read data PDV Length")
                return .Refused
            }
            
            // context + flags
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
