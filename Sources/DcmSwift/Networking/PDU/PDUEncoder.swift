//
//  PDUEncoder.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 The `PDUEncodable` protocol defines weither or not the message is designed to be encodable in DICOM data.
 */
public protocol PDUEncodable {
    /**
     This method is reponsible from converting the `PDUMessage` object in its actuel corresponding DICOM binary data.
     */
    func data() -> Data?
}

/**
 `PDUEncoder` is a factory class that will create `PDUEncodable` (aka `PDUMessage`) instances based on
 the current association and a given `PDUType` and/or `CommandField` for DATA-TF type of messages.
 
 For example, for a given `.associationAC` PDU type, the facory will produce a `AssociationAC` object instance.
 */
public class PDUEncoder {
    private static let shared = PDUEncoder()
    
    /**
     Encode ASSOCIATION related PDU messages
     */
    public class func createAssocMessage(pduType:PDUType, association:DicomAssociation) -> PDUEncodable? {
        return PDUEncoder.shared.createAssocMessage(pduType:pduType, association:association)
    }
    
    /**
     Encode DIMSE related PDU messages
     */
    public class func createDIMSEMessage(pduType:PDUType, commandField:CommandField, association:DicomAssociation) -> PDUEncodable? {
        return PDUEncoder.shared.createDIMSEMessage(pduType:pduType, commandField:commandField, association:association)
    }
}



private extension PDUEncoder {
    func createAssocMessage(pduType:PDUType, association:DicomAssociation) -> PDUEncodable? {
        if pduType == .associationAC {
            return AssociationAC(pduType: pduType, association: association)
        }
        else if pduType == .associationRQ {
            return AssociationRQ(pduType: pduType, association: association)
        }
        else if pduType == .associationRJ {
            return AssociationRJ(pduType: pduType, association: association)
        }
        else if pduType == .dataTF {
            return DataTF(pduType: pduType, association: association)
        }
        else if pduType == .releaseRQ {
            return ReleaseRQ(pduType: pduType, association: association)
        }
        else if pduType == .releaseRP {
            return ReleaseRSP(pduType: pduType, association: association)
        }
        else if pduType == .abort {
            return Abort(pduType: pduType, association: association)
        }
        else {
            Logger.error("Unknow PDU Type : \(pduType). Fatal.")
        }
        
        return nil
    }
    
    
    func createDIMSEMessage(pduType:PDUType, commandField:CommandField, association:DicomAssociation) -> PDUEncodable? {
        var encodable:PDUMessage? = nil
        
        if pduType == .dataTF {
            if commandField == .C_ECHO_RQ {
                encodable = CEchoRQ(pduType: pduType, commandField:commandField, association: association)
            }
            else if commandField == .C_ECHO_RSP {
                encodable = CEchoRSP(pduType: pduType, commandField:commandField, association: association)
            }
            else if commandField == .C_FIND_RQ {
                encodable = CFindRQ(pduType: pduType, commandField:commandField, association: association)
            }
            else if commandField == .C_FIND_RSP {
                encodable = CFindRSP(pduType: pduType, commandField:commandField, association: association)
            }
            else if commandField == .C_STORE_RQ {
                encodable = CStoreRQ(pduType: pduType, commandField:commandField, association: association)
            }
            else if commandField == .C_STORE_RSP {
                encodable = CStoreRSP(pduType: pduType, commandField:commandField, association: association)
            }
            else {
                 encodable = DataTF(pduType: pduType, commandField:commandField, association: association)
            }
        }
        else {
            Logger.error("Unsupported PDU Type : \(pduType). Fatal.")
        }
        
        return encodable
    }
}


