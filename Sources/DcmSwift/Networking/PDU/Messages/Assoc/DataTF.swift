//
//  DataTF.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation


/**
 The `DataTF` class represents a DATA-TF message of the DICOM standard.
 
 This class serves as a base for all the DIMSE messages.
 
 It decodes most of the generic part of the message, like the PDU, the Command dataset and the DIMSE status (see `decodeData()`).
 When inheriting from `DataTF`, `super.decodeData()` must be called in order to primarilly decode this generic attributes.
 
 It inherits most of its behavior from the `PDUMessage` class and its
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/dicom/2013/output/chtml/part08/sect_9.3.html#table_9-22
 */
public class DataTF: PDUMessage {
    
    /// Full name of DataTF PDU
    public override func messageName() -> String {
        return "DATA-TF"
    }
    
    
    /// Decodes the DataTF PDU data : type, 1 reserved byte, length, presentation-data-value items
    /// presentation-data-value contains : item length, presentation context id, presentation-data-value
    override public func decodeData(data: Data) -> DIMSEStatus.Status {
        _ = super.decodeData(data: data)
                                        
        // read PDV length
        guard let pdvLength = stream.read(length: 4)?.toInt32(byteOrder: .BigEndian) else {
            Logger.error("Cannot read PDV Length")
            return .Refused
        }
        
        self.pdvLength = Int(pdvLength)
                                
        // read context
        guard let _ = stream.read(length: 1)?.toInt8(byteOrder: .BigEndian) else {
            //Logger.warning("Cannot read context")
            return .Refused
        }
        
        // read flags
        guard let flags = stream.read(length: 1)?.toInt8(byteOrder: .BigEndian) else {
            Logger.error("Cannot read flags")
            return .Refused
        }
        
        self.flags = UInt8(flags)
                                
        // command fragment
        if self.flags == 0x3 {
            // read dataset data
            guard let commandData = stream.read(length: Int(pdvLength) - 2) else {
                Logger.error("Cannot read dataset data")
                return .Pending
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

            let c = command.data.toUInt16(byteOrder: .LittleEndian)

            guard let commandField = CommandField(rawValue: c) else {
                Logger.error("Cannot read CommandField in command Dataset")
                return .Refused
            }
            
            self.commandField = commandField
            
            guard let commandDataSetType = commandDataset.integer16(forTag: "CommandDataSetType")?.bigEndian else {
                Logger.error("Cannot read Command Data Set Type")
                return .Refused
            }
            
            self.commandDataSetType = commandDataSetType
            
            if let s = commandDataset.element(forTagName: "Status") {
                if let ss = DIMSEStatus.Status(rawValue: s.data.toUInt16(byteOrder: .LittleEndian)) {
                    self.dimseStatus = DIMSEStatus(status: ss, command: commandField)
                    
                    return ss
                }
            }
        }
        else if self.flags == 0x2 {
            // last fragment
            self.dimseStatus = DIMSEStatus(status: .Success, command: .NONE)
            
            // read data left
            guard let data = stream.read(length: Int(pdvLength) - 2) else {
                Logger.error("Cannot read data")
                return .Refused
            }
            
            receivedData = data
        }
        else if self.flags == 0x0 {
            // more data fragment coming
            self.dimseStatus = DIMSEStatus(status: .Pending, command: .NONE)
            
            guard let data = stream.read(length: Int(pdvLength) - 2) else {
                Logger.error("Cannot read data")
                return .Refused
            }
            
            receivedData = data
        }
        
        return .Success
    }
}
