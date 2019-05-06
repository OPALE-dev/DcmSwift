//
//  DataTF.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 03/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation

public class DataTF: PDUMessage {
    public func decodeDIMSEStatus(data: Data) {
        let flags = data.subdata(in: 11..<12).toInt8().bigEndian
        let commandData = data.subdata(in: 12..<data.count)
        
        if flags == 0x03 && commandData.count > 0 {
            if let dataset = DataSet(withData: commandData, readHeader: false) {
                if dataset.loadData() {
                    if let status = dataset.element(forTagName: "Status") {
                        let s = status.data.toUInt16(byteOrder: .LittleEndian)
                        if let ds = DIMSEStatus.Status(rawValue: s) {
                            self.dimseStatus = DIMSEStatus(status: ds, command: self.commandField!)
                        }
                    }
                }
            }
        }
    }
    
    
    public override func decodeData(data: Data) -> Bool {
        //self.decodeDIMSEStatus(data: data)
        
        return true
    }
}
