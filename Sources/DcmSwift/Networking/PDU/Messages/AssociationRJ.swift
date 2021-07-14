//
//  AssociationRJ.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation


public class AssociationRJ: PDUMessage {
    public var result:DicomAssociation.RejectResult = DicomAssociation.RejectResult.RejectedPermanent
    public var source:DicomAssociation.RejectSource = DicomAssociation.RejectSource.DICOMULServiceUser
    public var reason:DicomAssociation.UserReason = DicomAssociation.UserReason.NoReasonGiven
    
    public override func messageName() -> String {
        return "A-ASSOCIATE-RJ"
    }
    
    
    public override func data() -> Data {
        var data = Data()
        let length = UInt32(4)
        
        data.append(uint8: self.pduType.rawValue, bigEndian: true)
        data.append(byte: 0x00) // reserved
        data.append(uint32: length, bigEndian: true)
        data.append(byte: 0x00) // reserved
        data.append(uint8: self.result.rawValue) // result
        data.append(uint8: self.source.rawValue) // source
        data.append(uint8: self.reason.rawValue) // reason
        
        return data
    }
    
    
    public override func decodeData(data: Data) -> DIMSEStatus.Status {
        let status = super.decodeData(data: data)
        
        // dead byte
        _ = stream.read(length: 1)
        
        // read reject result
        if let r = stream.read(length: 1)?.toInt8().bigEndian {
            if let rr = DicomAssociation.RejectResult(rawValue: UInt8(r)) {
                result = rr
            }
        }
        
        // read reject source
        if let r = stream.read(length: 1)?.toInt8().bigEndian {
            if let rr = DicomAssociation.RejectSource(rawValue: UInt8(r)) {
                source = rr
            }
        }
        
        // read reject reason
        if let r = stream.read(length: 1)?.toInt8().bigEndian {
            if let rr = DicomAssociation.UserReason(rawValue: UInt8(r)) {
                reason = rr
            }
        }
        
        return status
    }
}
