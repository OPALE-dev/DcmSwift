//
//  DicomString.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 02/11/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation


extension String {
    public func hexData() -> Data? {
        guard self.count % 2 == 0 else { return nil }
        var data = Data()
        var byteLiteral = ""
        for (index, character) in self.enumerated() {
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

    public func separate(every stride: Int = 4, with separator: Character = " ") -> String {
        return String(enumerated().map { $0 > 0 && $0 % stride == 0 ? [separator, $1] : [$1]}.joined())
    }
    
    public static func random(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map{ _ in letters.randomElement()! })
    }
    
    public mutating func indent(level:Int) {
        for _ in 0..<level {
            self += "\t"
        }
    }
}
