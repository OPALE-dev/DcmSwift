//
//  AssociationRJ.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 03/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation


public class AssociationRJ: PDUMessage {
    public override func decodeData(data: Data) -> Bool {
//        let pduLength = data.subdata(in: 2..<6).toInt32().bigEndian
//        let result = data.subdata(in: 7..<8).toInt8().bigEndian
//        let source = data.subdata(in: 8..<9).toInt8().bigEndian
        let reason = data.subdata(in: 9..<10).toInt8().bigEndian
        
        if reason == 0x07 {
            let error = DicomError(code: 7, level: .error, realm: .network)
            self.errors.append(error)
            return true
        }
        
        return false
    }
}
