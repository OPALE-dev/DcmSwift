//
//  PDUEncoder.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 03/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation
import SwiftyBeaver

public protocol PDUEncodable {
    func data() -> Data
}


class PDUEncoder {
    public static let shared = PDUEncoder()
    
    public func createAssocMessage(pduType:PDUType, association:DicomAssociation) -> PDUEncodable? {
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
            return ReleaseRP(pduType: pduType, association: association)
        }
        else if pduType == .abort {
            return Abort(pduType: pduType, association: association)
        }
        else {
            SwiftyBeaver.error("Unknow PDU Type : \(pduType). Fatal.")
        }
        
        return nil
    }
    
    
    public func createDIMSEMessage(pduType:PDUType, commandField:CommandField, association:DicomAssociation) -> PDUEncodable? {
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
            SwiftyBeaver.error("Unsupported PDU Type : \(pduType). Fatal.")
        }
        
        return encodable
    }
}


