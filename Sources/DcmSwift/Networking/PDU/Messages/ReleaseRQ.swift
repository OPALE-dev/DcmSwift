//
//  ReleaseRQ.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 The `ReleaseRQ` class represents a A-RELEASE-RJ message of the DICOM standard.

 It inherits most of its behavior from the `PDUMessage` class and its
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/dicom/2013/output/chtml/part08/sect_9.3.html#sect_9.3.6
 */
public class ReleaseRQ: PDUMessage {
    public override func messageName() -> String {
        return "A-RELEASE-RQ"
    }
    
    
    public override func data() -> Data {
        var data = Data()
        let length = UInt32(4)
        
        data.append(uint8: self.pduType.rawValue, bigEndian: true)
        data.append(byte: 0x00)
        data.append(uint32: length, bigEndian: true)
        data.append(byte: 0x00, count: 4)
        
        return data
    }
    
    public override func decodeData(data: Data) -> DIMSEStatus.Status {
        return super.decodeData(data: data)
    }
    
    public override func handleRequest() -> PDUMessage? {
        if let response = PDUEncoder.shared.createAssocMessage(pduType: .releaseRP, association: self.association) as? PDUMessage {
            response.requestMessage = self
            return response
        }
        return nil
    }
}
