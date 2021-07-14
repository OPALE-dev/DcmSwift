//
//  CommandField.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 03/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation


public enum CommandField: UInt16 {
    case C_STORE_RQ             = 0x0001
    case C_STORE_RSP            = 0x8001
    case C_GET_RQ               = 0x0010
    case C_GET_RSP              = 0x8010
    case C_FIND_RQ              = 0x0020
    case C_FIND_RSP             = 0x8020
    case C_MOVE_RQ              = 0x0021
    case C_MOVE_RSP             = 0x8021
    case C_ECHO_RQ              = 0x0030
    case C_ECHO_RSP             = 0x8030
    case N_EVENT_REPORT_RQ      = 0x0100
    case N_EVENT_REPORT_RSP     = 0x8100
    case N_GET_RQ               = 0x0110
    case N_GET_RSP              = 0x8110
    case N_SET_RQ               = 0x0120
    case N_SET_RSP              = 0x8120
    case N_ACTION_RQ            = 0x0130
    case N_ACTION_RSP           = 0x8130
    case N_CREATE_RQ            = 0x0140
    case N_CREATE_RSP           = 0x8140
    case N_DELETE_RQ            = 0x0150
    case N_DELETE_RSP           = 0x8150
    case C_CANCEL_RQ            = 0x0FFF
}
