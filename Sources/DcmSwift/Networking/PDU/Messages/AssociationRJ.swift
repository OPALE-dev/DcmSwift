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
    public var reason:UInt8 = 0
    
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
        data.append(uint8: self.reason) // reason
        
        return data
    }
    
    
    public override func decodeData(data: Data) -> DIMSEStatus.Status {
//        let pduLength = data.subdata(in: 2..<6).toInt32().bigEndian
//        let result = data.subdata(in: 7..<8).toInt8().bigEndian
//        let source = data.subdata(in: 8..<9).toInt8().bigEndian
        let reason = data.subdata(in: 9..<10).toInt8().bigEndian
        
        // TODO: handle all reason ?
        if reason == 0x07 {
            let error = DicomError(code: 7, level: .error, realm: .network)
            self.errors.append(error)
            return .Success
        }
        
        return .Refused
    }
}
