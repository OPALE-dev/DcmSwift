//
//  CStoreRSP.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 08/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

public class CStoreRSP: DataTF {
    public override func messageName() -> String {
        return "C-STORE-RSP"
    }
    
    
    public override func decodeData(data: Data) -> Bool {
        super.decodeDIMSEStatus(data: data)
        
        return true
    }
    
    
    public override func handleResponse(data: Data) -> PDUMessage? {
        return nil
    }
}