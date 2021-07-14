//
//  CFindRSP.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 04/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

public class CFindRSP: DataTF {
    public var studiesDataset:DataSet?
    
    
    public override func messageName() -> String {
        return "C-FIND-RSP"
    }
    
    
    override public func decodeData(data: Data) -> DIMSEStatus.Status {
        let status = super.decodeData(data: data)
        
        // if data if available
        if commandDataSetType == 0 {
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
                        
            if commandField == .C_FIND_RSP {
                if let resultDataset = try? dis.readDataset() {
                    studiesDataset = resultDataset
                }
            }
        }
        
        return status
    }
}
