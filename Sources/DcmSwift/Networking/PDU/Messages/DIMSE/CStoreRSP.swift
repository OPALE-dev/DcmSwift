//
//  CStoreRSP.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 08/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 The `CStoreRSP` class represents a C-STORE-RSP message of the DICOM standard.

 It inherits most of its behavior from `DataTF` and `PDUMessage` and their
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/dicom/2013/output/chtml/part07/sect_9.3.html
 */
public class CStoreRSP: DataTF {
    public override func messageName() -> String {
        return "C-STORE-RSP"
    }
    
    
    public override func data() -> Data? {
        if let pc = self.association.acceptedPresentationContexts.values.first,
           let transferSyntax = TransferSyntax(TransferSyntax.implicitVRLittleEndian) {
            let commandDataset = DataSet()
            _ = commandDataset.set(value: CommandField.C_STORE_RSP.rawValue.bigEndian, forTagName: "CommandField")
            _ = commandDataset.set(value: pc.abstractSyntax as Any, forTagName: "AffectedSOPClassUID")
            
            if let request = self.requestMessage {
                _ = commandDataset.set(value: request.messageID, forTagName: "MessageIDBeingRespondedTo")
            }
            _ = commandDataset.set(value: UInt16(257).bigEndian, forTagName: "CommandDataSetType")
            _ = commandDataset.set(value: UInt16(0).bigEndian, forTagName: "Status")
            
            let pduData = PDUData(
                pduType: self.pduType,
                commandDataset: commandDataset,
                abstractSyntax: pc.abstractSyntax,
                transferSyntax: transferSyntax,
                pcID: pc.contextID, flags: 0x03)
            
            return pduData.data()
        }
        
        return nil
    }
    
    
    public override func decodeData(data: Data) -> DIMSEStatus.Status {
        let status = super.decodeData(data: data)
        
        print(data.toHex())
        
        return status
    }
    
    
    public override func handleResponse(data: Data) -> PDUMessage? {
        return nil
    }
}
