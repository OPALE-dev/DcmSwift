//
//  DicomError.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 04/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation
import Socket

/**
DicomError represents common errors defined by the DICOM specification
*/
public class DicomError: NSObject {
    /**
     The ErrorLevel enum defines the severity of the error
     */
    public enum ErrorLevel:Int {
        case notice     = 1
        case warning    = 2
        case error      = 3
        case failure    = 4
        case refused    = 5
    }
    
    /**
    The realm of the error, as a meta category
    */
    public enum ErrorRealm:Int {
        case custom     = 0
        case general    = 1
        case network    = 2
        case socket     = 3
    }

    /// the internal error code of the error, depending of the internal error realm
    private var errorCode:Int!
    /// the internal error level
    private var errorLevel:ErrorLevel!
    /// the internal error realm
    private var errorRealm:ErrorRealm!
    /// custom description used for custom realm
    private var customDescription:String?
    
    /// Unknow error default string
    private let unknowErrorString = "Unknow error"
    
    /**
     Create error with code, level and realm
     Realm is `.general` by default
     */
    public init(code:Int, level:ErrorLevel, realm:ErrorRealm = .general) {
        self.errorCode  = code
        self.errorLevel = level
        self.errorRealm = realm
    }
    
    
    public convenience init(description:String, level:ErrorLevel, realm:ErrorRealm = .general) {
        self.init(code: 0, level: level, realm: realm)
        self.customDescription = description
    }
    
    
    public convenience init(socketError error:Socket.Error) {
        self.init(code: Int(error.errorCode), level: .error, realm: .socket)
        self.customDescription = error.description
    }
    
    
    public var errorMeaning:String {
        if self.errorRealm == .general {
            switch self.errorCode {
            case 261:
                return "No such attribute"
            case 262:
                return "Invalid attribute value"
            case 263:
                return "Attribute List Error"
            case 272:
                return "Processing failure"
            case 273:
                return "Duplicate SOP instance"
            case 274:
                return "No such object instance"
            case 275:
                return "No such event type"
            case 276:
                return "No such argument"
            case 277:
                return "Invalid argument value"
            case 278:
                return "Attribute Value Out of Range"
            case 279:
                return "Invalid object instance"
            case 280:
                return "No such SOP class"
            case 281:
                return "Class-instance conflict"
            case 282:
                return "Missing attribute"
            case 283:
                return "Missing attribute value"
            case 284:
                return "SOP class not supported"
            case 285:
                return "No such action type"
            case 528:
                return "Duplicate invocation"
            case 529:
                return "Unrecognized operation"
            case 530:
                return "Mistyped argument"
            case 531:
                return "Resource limitation"
            default:
                return self.unknowErrorString
            }
        }
        else if self.errorRealm == .network {
            switch self.errorCode {
            case 1:
                return "No reason given"
            case 2:
                return "Application Context Name not supported"
            case 3:
                return "Calling AE Title not recognized"
            case 7:
                return "Called AE Title not recognized"
            default:
                return self.unknowErrorString
            }
        }
        else if self.errorRealm == .custom || self.errorRealm == .socket {
            return self.customDescription ?? self.unknowErrorString
        }
        
        return self.unknowErrorString
    }
    
    
    public override var description: String {
        var str = ""
        if  let el = self.errorLevel,
            let er = self.errorRealm,
            let ec = self.errorCode {
            str = "\(el) -> [\(er)] (\(ec)) \(self.errorMeaning)"
        }
        return str
    }
}

