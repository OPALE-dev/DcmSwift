//
//  AssociationRJ.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 The `AssociationRJ` class represents a A-ASSOCIATE-RJ message of the DICOM standard.

 The message you receive when the association is rejected.
 You can find more context about it in `result`, `source` and `reason` properties.
 
 It inherits most of its behavior from the `PDUMessage` class and its
 related protocols (`PDUResponsable`, `PDUDecodable`, `PDUEncodable`).
 
 http://dicom.nema.org/dicom/2013/output/chtml/part08/sect_9.3.html#sect_9.3.4
 */
public class AssociationRJ: PDUMessage {
    public var result:DicomAssociation.RejectResult = DicomAssociation.RejectResult.RejectedPermanent
    public var source:DicomAssociation.RejectSource = DicomAssociation.RejectSource.DICOMULServiceUser
    public var reason:DicomAssociation.UserReason = DicomAssociation.UserReason.NoReasonGiven
    
    /// Full name of AssociateRJ PDU
    public override func messageName() -> String {
        return "A-ASSOCIATE-RJ"
    }
    
    public override func messageInfos() -> String {
        return "\(self.reason)"
    }
    
    /**
     Builds the A-ASSOCIATE-RJ bytes
     
     A-ASSOCIATE-RJ message consists of:
     - pdu type
     - 1 reserved byte
     - 4 pdu length
     - 1 reserved byte
     - result integer (1: permanent, 2: transient)
     - source integer (1: user, 2: provider asce, 3: provider presentation)
     - reason/diag. integer
     
     Reason integer value can mean the following:
     - 1 no-reason-given
     - 2 application-context-name-not-supported
     - 3 calling-AE-title-not-recognized
     - 4-6 reserved
     - 7 called-AE-title-not-recognized
     - 8-10 reserved
     
     - Returns: A-ASSOCIATE-RJ bytes as `Data`
     */
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
        
        do {
            // dead byte
            _ = try stream.read(length: 1)
            
            // read reject result
            let r = try stream.read(length: 1).toInt8().bigEndian// {
                if let rr = DicomAssociation.RejectResult(rawValue: UInt8(r)) {
                    result = rr
                }
            //}
            
            // read reject source
            let r2 = try stream.read(length: 1).toInt8().bigEndian// {
                if let rr = DicomAssociation.RejectSource(rawValue: UInt8(r2)) {
                    source = rr
                }
            //}
            
            // read reject reason
            let r3 = try stream.read(length: 1).toInt8().bigEndian// {
                if let rr = DicomAssociation.UserReason(rawValue: UInt8(r3)) {
                    reason = rr
                }
            //}
        } catch {
            Logger.error("outOfBound")
        }
        
        
        return status
    }
}
