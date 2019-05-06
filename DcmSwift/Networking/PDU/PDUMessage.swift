//
//  PDUMessage.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 02/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation
import SwiftyBeaver

public protocol PDUResponsable {
    func handleResponse(data:Data, completion: (_ accepted:Bool, _ receivedMessage:PDUMessage?, _ error:DicomError?) -> Void) -> PDUMessage?
}


public class PDUMessage: PDUResponsable, PDUDecodable, PDUEncodable {
    public var pduType:PDUType!
    //public var pduLength:Int?
    public var commandField:CommandField?
    public var association:DicomAssociation!
    public var dimseStatus:DIMSEStatus!
    public var errors:[DicomError] = []

    
    public init(pduType:PDUType, association:DicomAssociation) {
        self.pduType = pduType
        self.association = association
    }
    
    
    public convenience init(pduType:PDUType, commandField:CommandField, association:DicomAssociation) {
        self.init(pduType: pduType, association: association)
        self.commandField = commandField
    }


    
    public convenience init?(data:Data, pduType:PDUType, association:DicomAssociation) {
        self.init(pduType: pduType, association: association)
        
        if !decodeData(data: data) {
            return nil
        }
    }
    
    
    public convenience init?(data:Data, pduType:PDUType, commandField:CommandField, association:DicomAssociation) {
        self.init(pduType: pduType, commandField:commandField, association: association)
        
        if !decodeData(data: data) {
            return nil
        }
    }
    
    
    public func messageData() -> Data? {
        SwiftyBeaver.warning("Not implemented yet")
        return nil
    }
    
    
    public func data() -> Data {
        SwiftyBeaver.warning("Not implemented yet")
        return Data()
    }
    
    
    public func decodeData(data:Data) -> Bool {
        SwiftyBeaver.warning("Not implemented yet")
        return false
    }
    
    
    public func handleResponse(data:Data, completion: (_ accepted:Bool, _ receivedMessage:PDUMessage?, _ error:DicomError?) -> Void) -> PDUMessage? {
        SwiftyBeaver.warning("Not implemented yet")
        completion(false, nil, nil)
        return nil
    }
}
