//
//  EchoRQ.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 The `CEchoRQ` class represents a C-ECHO-RQ message of the DICOM standard.
 
 It inherits most of its behavior from `DataTF` and `PDUMessage` and their
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/medical/dicom/current/output/chtml/part07/sect_9.3.5.html
 */
public class CEchoRQ: DataTF {
    public override func messageName() -> String {
        return "C-ECHO-RQ"
    }
    
    
    public override func data() -> Data? {
        // fetch accepted PC
        guard let pcID = association.acceptedPresentationContexts.keys.first,
              let spc = association.presentationContexts[pcID],
              let transferSyntax = TransferSyntax(TransferSyntax.implicitVRLittleEndian),
              let abstractSyntax = spc.abstractSyntax else {
            return nil
        }
          
        
        let commandDataset = DataSet()
        _ = commandDataset.set(value: CommandField.C_ECHO_RQ.rawValue.bigEndian, forTagName: "CommandField")
        _ = commandDataset.set(value: self.association.abstractSyntax, forTagName: "AffectedSOPClassUID")
        _ = commandDataset.set(value: self.messageID, forTagName: "MessageID")
        _ = commandDataset.set(value: UInt16(257).bigEndian, forTagName: "CommandDataSetType")

        let pduData = PDUData(
            pduType: self.pduType,
            commandDataset: commandDataset,
            abstractSyntax: abstractSyntax,
            transferSyntax: transferSyntax,
            pcID: pcID, flags: 0x03)
        
        return pduData.data()
    }
    
    public override func decodeData(data: Data) -> DIMSEStatus.Status {        
        return .Success
    }
    
    public override func handleResponse(data:Data) -> PDUMessage? {
        if let type:UInt8 = data.first {
            if type == PDUType.dataTF.rawValue {
                if let message = PDUDecoder.receiveDIMSEMessage(
                    data: data,
                    pduType: PDUType.dataTF,
                    commandField: .C_ECHO_RSP,
                    association: self.association
                ) as? PDUMessage {
                    return message
                }
            }
        }
        return nil
    }
    
    public override func handleRequest() -> PDUMessage? {
        if let response = PDUEncoder.createDIMSEMessage(
            pduType: .dataTF,
            commandField: .C_ECHO_RSP,
            association: self.association
        ) as? PDUMessage {
            response.dimseStatus = DIMSEStatus(status: .Success, command: .C_ECHO_RSP)
            response.requestMessage = self
            return response
        }
        return nil
        
    }
}
