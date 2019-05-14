//
//  CFindRSP.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 04/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation

public class CFindRSP: DataTF {
    public var queryResults:[Any] = []
    
    public override func messageName() -> String {
        return "C-FIND-RSP"
    }
    
    
    override public func decodeData(data: Data) -> Bool {
        super.decodeDIMSEStatus(data: data)
        
        let commandData = data.subdata(in: 12..<data.count)
        
        if commandData.count > 0 {
            if self.flags == 0x02 {
                if let dataset = DataSet(withData: commandData, readHeader: false) {
                    dataset.prefixHeader = false
                    dataset.forceExplicit = true
                    if dataset.loadData() {
                        responseDataset = dataset
                    }
                }
            }
        }
        
        return true
    }
}
