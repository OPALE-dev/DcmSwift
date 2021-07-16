//
//  PDUDecoder.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 The `PDUDecodable` protocol provides a generic interface to decode PDU messages received as binary data
 */
public protocol PDUDecodable {
    func decodeData(data:Data) -> DIMSEStatus.Status
}


/**
 `PDUDecoder` is a factory class that will create `PDUDecodable` (aka `PDUMessage`) instances based on
 received data, the current association and a given `PDUType` and/or `CommandField` for DATA-TF type of messages.
 
 For example, with data for a given `.associationAC` PDU type, the facory will produce a `AssociationAC` object instance.
 */
public class PDUDecoder {
    private static let shared = PDUDecoder()
    
    /**
     Decode ASSOCIATION related PDU messages
     */
    public class func receiveAssocMessage(data:Data, pduType:PDUType, association:DicomAssociation) -> PDUDecodable? {
        PDUDecoder.shared.receiveAssocMessage(data:data, pduType: pduType, association: association)
    }
    
    /**
     Decode DIMSE related PDU messages
     */
    public class func receiveDIMSEMessage(data:Data, pduType:PDUType, commandField:CommandField, association:DicomAssociation) -> PDUDecodable? {
        PDUDecoder.shared.receiveDIMSEMessage(data:data, pduType: pduType, commandField: commandField, association: association)
    }
    
    /**
     This variation is used on server-side only to identify the received message and return
     the corresponding response type.
     */
    public class func receiveDIMSEMessage(data:Data, pduType:PDUType, association:DicomAssociation) -> PDUDecodable? {
        PDUDecoder.shared.receiveDIMSEMessage(data:data, pduType: pduType, association: association)
    }
}
    

extension PDUDecoder {
    private func receiveAssocMessage(data:Data, pduType:PDUType, association:DicomAssociation) -> PDUDecodable? {
        if pduType == .associationAC {
            return AssociationAC(data: data, pduType: pduType, association: association)
        }
        else if pduType == .associationRQ {
            return AssociationRQ(data: data, pduType: pduType, association: association)
        }
        else if pduType == .associationRJ {
            return AssociationRJ(data: data, pduType: pduType, association: association)
        }
        else if pduType == .dataTF {
            return DataTF(data: data, pduType: pduType, association: association)
        }
        else if pduType == .releaseRQ {
            return ReleaseRQ(data: data, pduType: pduType, association: association)
        }
        else if pduType == .releaseRP {
            return ReleaseRSP(data: data, pduType: pduType, association: association)
        }
        else if pduType == .abort {
            return Abort(data: data, pduType: pduType, association: association)
        }
        else {
            Logger.error("Unknow PDU Type : \(pduType). Fatal.")
        }
        
        return nil
    }

    
    
    private func receiveDIMSEMessage(data:Data, pduType:PDUType, commandField:CommandField, association:DicomAssociation) -> PDUDecodable? {
        var message:PDUMessage? = nil
        
        if pduType == .dataTF {
            if commandField == .C_ECHO_RSP {
                message = CEchoRSP(data: data, pduType: pduType, commandField:commandField, association: association)
            }
            else if commandField == .C_ECHO_RQ {
                message = CEchoRQ(data: data, pduType: pduType, commandField:commandField, association: association)
            }
            else if commandField == .C_FIND_RSP {
                message = CFindRSP(data: data, pduType: pduType, commandField:commandField, association: association)
            }
            else if commandField == .C_FIND_RQ {
                message = CFindRQ(data: data, pduType: pduType, commandField:commandField, association: association)
            }
            else if commandField == .C_STORE_RSP {
                message = CStoreRSP(data: data, pduType: pduType, commandField:commandField, association: association)
            }
            else if commandField == .C_STORE_RQ {
                message = CStoreRQ(data: data, pduType: pduType, commandField:commandField, association: association)
            }
        }
        
        return message
    }
    
    
    private func receiveDIMSEMessage(data:Data, pduType:PDUType, association:DicomAssociation) -> PDUDecodable? {
        // use DataTF class to lazy decode commandField before dispatching to DIMSE subclasses
        guard let dataTF = DataTF(data: data, pduType: pduType, association: association),
              let commandField = dataTF.commandField else {
            return nil
        }
            
        return receiveDIMSEMessage(data: data, pduType: pduType, commandField: commandField, association: association)
    }
}
