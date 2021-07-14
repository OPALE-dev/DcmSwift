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
    
    override public func decodeData(data: Data) -> DIMSEStatus.Status {
        var status = super.decodeData(data: data)
                                        
        // read PDV length
        guard let pdvLength = stream.read(length: 4)?.toInt32(byteOrder: .BigEndian) else {
            Logger.error("Cannot read PDV Length")
            return .Refused
        }
        
        self.pdvLength = Int(pdvLength)
                                
        // read context
        guard let _ = stream.read(length: 1)?.toInt8(byteOrder: .BigEndian) else {
            Logger.error("Cannot read context")
            return .Refused
        }
        
        // read flags
        guard let flags = stream.read(length: 1)?.toInt8(byteOrder: .BigEndian) else {
            Logger.error("Cannot read flags")
            return .Refused
        }
        
        self.flags = UInt8(flags)
        
        // read dataset data
        guard let commandData = stream.read(length: Int(pdvLength) - 2) else {
            Logger.error("Cannot read dataset data")
            return .Refused
        }
        
        let dis = DicomInputStream(data: commandData)
        
        // read command dataset
        guard let commandDataset = try? dis.readDataset() else {
            Logger.error("Cannot read command dataset")
            return .Refused
        }
        
        self.commandDataset = commandDataset
                                
        guard let command = commandDataset.element(forTagName: "CommandField") else {
            Logger.error("Cannot read CommandField in command Dataset")
            return .Refused
        }

        // we create a response (PDUMessage of DIMSE family) based on received CommandField value using PDUDecoder
        let c = command.data.toUInt16(byteOrder: .LittleEndian)

        guard let commandField = CommandField(rawValue: c) else {
            Logger.error("Cannot read CommandField in command Dataset")
            return .Refused
        }
        
        self.commandField = commandField
                    
        guard let s = commandDataset.element(forTagName: "Status"),
              let ss = DIMSEStatus.Status(rawValue: s.data.toUInt16(byteOrder: .LittleEndian)) else {
            Logger.error("Cannot read DIMSE Status")
            return .Refused
        }
        
        status = ss
                    
        guard let commandDataSetType = commandDataset.integer16(forTag: "CommandDataSetType")?.bigEndian else {
            Logger.error("Cannot read Command Data Set Type")
            return .Refused
        }
        
        self.commandDataSetType = commandDataSetType
        self.dimseStatus = DIMSEStatus(status: status, command: commandField)
        
        return status
    }
}
