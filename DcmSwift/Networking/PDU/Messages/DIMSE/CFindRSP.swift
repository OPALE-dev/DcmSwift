//
//  CFindRSP.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 04/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa

class CFindRSP: DataTF {
    override func decodeData(data: Data) -> Bool {
        super.decodeDIMSEStatus(data: data)
        
        return true
    }
}
