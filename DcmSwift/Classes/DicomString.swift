
//
//  DicomString.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 02/11/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Foundation


extension String {
    func hexData() -> Data? {
        guard self.characters.count % 2 == 0 else { return nil }
        var data = Data()
        var byteLiteral = ""
        for (index, character) in self.characters.enumerated() {
            if index % 2 == 0 {
                byteLiteral = String(character)
            } else {
                byteLiteral.append(character)
                guard let byte = UInt8(byteLiteral, radix: 16) else { return nil }
                data.append(byte)
            }
        }
        return data
    }
}
