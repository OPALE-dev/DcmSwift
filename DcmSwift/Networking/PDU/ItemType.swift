//
//  ItemType.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation


public enum ItemType: UInt8 {
    case applicationContext     = 0x10;
    case rqPresentationContext  = 0x20;
    case acPresentationContext  = 0x21;
    case abstractSyntax         = 0x30;
    case transferSyntax         = 0x40;
    case userInfo               = 0x50;
    case maxPduLength           = 0x51;
    case implClassUID           = 0x52;
    case asyncOpsWindow         = 0x53;
    case roleSelection          = 0x54;
    case implVersionName        = 0x55;
    case extNeg                 = 0x56;
    case commonExtNeg           = 0x57;
    case rqUserIdentity         = 0x58;
    case acUserIdentity         = 0x59;
}
