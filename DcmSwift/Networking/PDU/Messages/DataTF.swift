//
//  DataTF.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

public class DataTF: PDUMessage {
    public override func messageName() -> String {
        return "DATA-TF"
    }
    
    public func decodeFlags(data: Data) {
        let flags = data.subdata(in: 11..<12).toInt8().bigEndian
        let commandData = data.subdata(in: 12..<data.count)
        
        if commandData.count > 0 {
            self.flags = UInt8(flags)
        }
    }
    
    
    public func decodeDIMSEStatus(data: Data) {
        self.decodeFlags(data: data)
        
        let commandData = data.subdata(in: 12..<data.count)
        
        if commandData.count > 0 {
            if self.flags == 0x03 {
                if let dataset = DataSet(withData: commandData, readHeader: false) {
                    if dataset.loadData() {
                        // decode DIMSE status
                        if let status = dataset.element(forTagName: "Status") {
                            let s = status.data.toUInt16(byteOrder: .LittleEndian)
                            if let ds = DIMSEStatus.Status(rawValue: s) {
                                self.dimseStatus = DIMSEStatus(status: ds, command: self.commandField!)
                            }
                        }
                        
                        // also decode command field
                        // TODO: rename `decodeDIMSEStatus` method
                        if let command = dataset.element(forTagName: "CommandField") {
                            let c = command.data.toUInt16(byteOrder: .LittleEndian)
                            self.commandField = CommandField(rawValue: c)
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
