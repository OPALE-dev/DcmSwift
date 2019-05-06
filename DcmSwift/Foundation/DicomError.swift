//
//  DicomError.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 04/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa

public class DicomError: NSObject {
    public enum ErrorLevel:Int {
        case notice     = 1
        case warning    = 2
        case error      = 3
        case failure    = 4
        case refused    = 5
    }
    
    public enum ErrorRealm:Int {
        case custom     = 0
        case general    = 1
        case network    = 2
        
    }

    public var errorCode:Int!
    public var errorLevel:ErrorLevel!
    public var errorRealm:ErrorRealm!
    public var customDescription:String?
    
    public init(code:Int, level:ErrorLevel, real:ErrorRealm = .general) {
        self.errorCode = code
        self.errorLevel = level
        self.errorRealm = real
    }
    
    
    public convenience init(description:String, level:ErrorLevel, real:ErrorRealm = .general) {
        self.init(code: 0, level: level, real: real)
        self.customDescription = description
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
                return "Unknow error"
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
                return "Unknow error"
            }
        }
        else if self.errorRealm == .custom {
            return self.customDescription ?? "Unknow error"
        }
        
        return "Unknow error"
    }
    
    
    public override var description: String {
        return "\(self.errorLevel) -> [\(self.errorRealm)] (\(self.errorCode)) \(self.errorMeaning)"
    }
}

