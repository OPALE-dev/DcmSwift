//
//  CFindRSP.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 04/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

public class CFindRSP: DataTF {
    public var queryResults:[Any] = []
    
    public override func messageName() -> String {
        return "C-FIND-RSP"
    }
    
    
    override public func decodeData(data: Data) -> DIMSEStatus.Status {
        super.decodeDIMSEStatus(data: data)
        
        print("decodeData \(data.toHex())")
                        
        let commandData = data.subdata(in: 12..<data.count)
                        
        if commandData.count > 0 {
            if self.flags == 0x02 {
                let inputStream = DicomInputStream(data: commandData)
            
                if let dataset = try? inputStream.readDataset() {
                    responseDataset = dataset
                }
            }
        }
        
        return self.dimseStatus.status
    }
}
