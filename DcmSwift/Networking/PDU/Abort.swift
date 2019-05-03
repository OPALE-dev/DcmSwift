//
//  Abort.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 03/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation

class Abort: PDUMessage {
    override func data() -> Data {
        var data = Data()
        let length = UInt32(4)
        
        data.append(uint8: ItemType.applicationContext.rawValue, bigEndian: true)
        data.append(byte: 0x00)
        data.append(uint32: length, bigEndian: true)
        data.append(byte: 0x00, count: 4)
        
        return data
    }
    
    override func decodeData(data: Data) -> Bool {
        return false
    }
}
