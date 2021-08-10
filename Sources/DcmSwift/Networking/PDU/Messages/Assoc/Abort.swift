//
//  Abort.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 The `Abort` class represents a A-ABORT message of the DICOM standard.

 It inherits most of its behavior from the `PDUMessage` class and its
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/dicom/2013/output/chtml/part08/sect_9.3.html#sect_9.3.8
 */
public class Abort: PDUMessage {
    
    /// Full name of ABORT PDU
    public override func messageName() -> String {
        return "A-ABORT"
    }
    
    /**
     Builds the A-ABORT PDU message
     
     A-ABORT consists of:
     - pdu type
     - 1 reserved byte
     - pdu length
     - 4 reserved bytes
     - 2 reserved bytes
     - the source (0 : user initiated abort, 1 : reserved, 2 : provider initiated abort)
     
     - Returns: A-ABORT bytes
     */
    public override func data() -> Data {
        var data = Data()
        let length = UInt32(4)
        
        data.append(uint8: ItemType.applicationContext.rawValue, bigEndian: true)
        data.append(byte: 0x00)
        data.append(uint32: length, bigEndian: true)
        data.append(byte: 0x00, count: 4)
        
        return data
    }
    
    /// - Returns: Success
    public override func decodeData(data: Data) -> DIMSEStatus.Status {
        return .Success
    }
}
