//
//  PDUType.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 Enum representing the different PDU types of a DICOM message.
 
 See 9.3 DICOM Upper Layer Protocol for TCP/IP Data Units Structure:
 
 http://dicom.nema.org/dicom/2013/output/chtml/part08/sect_9.3.html
 */
public enum PDUType: UInt8 {
    case associationRQ  = 0x01
    case associationAC  = 0x02
    case associationRJ  = 0x03
    case dataTF         = 0x04
    case releaseRQ      = 0x05
    case releaseRP      = 0x06
    case abort          = 0x07
    
    public static func isSupported(_ pduType:UInt8) -> Bool {
        switch pduType {
        case 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07:
            return true
        default:
            return false
        }
    }
}
