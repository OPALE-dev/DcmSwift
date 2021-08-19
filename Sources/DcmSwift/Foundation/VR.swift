//
//  VR.swift
//  
//
//  Created by Rafael Warnault, OPALE on 24/06/2021.
//

import Foundation

public class VR: CustomStringConvertible {
    /**
     The list of Value Representations supported by the DICOM standard
     */
    public enum VR {
        case AE
        case AS
        case AT
        case CS
        case DA
        case DS
        case DT
        case FL
        case FD
        case IS
        case LO
        case LT
        case OB
        case OD
        case OF
        case OW
        case PN
        case SH
        case SL
        case SQ
        case SS
        case ST
        case TM
        case UI
        case UL
        case UN
        case US
        case UT
    }
    
    var name:String
    var vr:VR
    var maxLength:Int
    
    public var description: String {
        return name
    }
    
    
    init?(name: String, maxLength:Int) {
        guard let v = DicomSpec.vr(for: name) else {
            Logger.error("Unknow VR")
            return nil
        }
        
        self.vr         = v
        self.name       = name
        self.maxLength  = maxLength
    }
    
    /**
     Unused. Why not.. because enum are bet…faster!
     */
    init?(stream:DicomInputStream) throws {
        let data = try stream.read(length: 2)// else {
        //    return nil
        //}
        
        guard let vr = DicomSpec.vr(for: data.toString()) else {
            return nil
        }
        
        self.vr         = vr
        self.name       = "\(vr)"
        self.maxLength  = DicomSpec.lengthOf(vr: vr)
    }
}
