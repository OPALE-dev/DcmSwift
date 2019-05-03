//
//  PDUDecoder.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 03/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation
import SwiftyBeaver

public protocol PDUDecodable {
    func decodeData(data:Data) -> Bool
    func data() -> Data
}



public class PDUDecoder {
    private static var sharedDecoder = PDUDecoder()
    class func shared() -> PDUDecoder {
        return sharedDecoder
    }
    
    public func receiveMessage(data:Data, pduType:PDUType, association:DicomAssociation) -> PDUDecodable? {
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
            return ReleaseRP(data: data, pduType: pduType, association: association)
        }
        else if pduType == .abort {
            return Abort(data: data, pduType: pduType, association: association)
        }
        else {
            SwiftyBeaver.error("Unknow PDU Type : \(pduType). Fatal.")
        }
        
        return nil
    }
}
