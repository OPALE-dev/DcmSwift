//
//  DIMSEStatus.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 05/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

public struct DIMSEStatus {
    // nested Rank enumeration
    public enum Status: UInt16 {
        public typealias RawValue = UInt16
        // C-ECHO
        case Success                            = 0x0000
        case Refused                            = 0x0122
        case DuplicateInvocation                = 0x0210
        case MistypedArgument                   = 0x0212
        case UnrecognizedOperation              = 0x0211
        // C-FIND
        case OutOfResources                     = 0xA700
        case DataSetDoesNotMatchSOPClass        = 0xA900
        case UnableToProcess                    = 0xC000
        case MoreThanOneMatchFound              = 0xC100
        case UnableToSupportRequestedTemplate   = 0xC200
        case Cancel                             = 0xFE00
        case Pending                            = 0xFF00
        case Unknow                             = 0xA800
    }
    
    let status: Status, command: CommandField
}
