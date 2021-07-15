//
//  PDUData.swift
//  
//
//  Created by Rafael Warnault, OPALE on 15/07/2021.
//

import Foundation

internal class PDUData {
    var pduType:PDUType
    var abstractSyntax:String
    var transferSyntax:TransferSyntax
    var commandDataset:DataSet
    var pcID:UInt8
    var flags:UInt8
    
    init(pduType:PDUType, commandDataset:DataSet, abstractSyntax:String, transferSyntax:TransferSyntax, pcID:UInt8, flags:UInt8) {
        self.flags              = flags
        self.pduType            = pduType
        self.abstractSyntax     = abstractSyntax
        self.transferSyntax     = transferSyntax
        self.commandDataset     = commandDataset
        self.pcID               = pcID
        self.flags              = flags
    }
    
    
    func data() -> Data {
        var data = Data()
        
        // get command dataset length for CommandGroupLength element
        let commandGroupLength = commandDataset.toData(transferSyntax: transferSyntax).count
        _ = commandDataset.set(value: UInt32(commandGroupLength).bigEndian, forTagName: "CommandGroupLength")

        // build PDV data
        var pdvData = Data()
        let pdvLength = commandGroupLength + 14
        pdvData.append(uint32: UInt32(pdvLength), bigEndian: true)
        pdvData.append(uint8: pcID, bigEndian: true) // Context
        pdvData.append(byte: self.flags) // Flags
        pdvData.append(commandDataset.toData(transferSyntax: transferSyntax))

        // build PDU data
        let pduLength = UInt32(pdvLength + 4)
        data.append(uint8: self.pduType.rawValue, bigEndian: true)
        data.append(byte: 0x00) // reserved
        data.append(uint32: pduLength, bigEndian: true)
        data.append(pdvData)

        return data
    }
}
