
//
//  DicomString.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 02/11/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
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
 
//    public var drop0xPrefix:          String { return hasPrefix("0x") ? String(characters.dropFirst(2)) : self }
//    public var drop0bPrefix:          String { return hasPrefix("0b") ? String(characters.dropFirst(2)) : self }
//    public var hexaToDecimal:            Int { return Int(drop0xPrefix, radix: 16) ?? 0 }
//    public var hexaToBinaryString:    String { return String(hexaToDecimal, radix: 2) }
//    public var decimalToHexaString:   String { return String(Int(self) ?? 0, radix: 16) }
//    public var decimalToBinaryString: String { return String(Int(self) ?? 0, radix: 2) }
//    public var binaryToDecimal:          Int { return Int(drop0bPrefix, radix: 2) ?? 0 }
//    public var binaryToHexaString:    String { return String(binaryToDecimal, radix: 16) }
}

//extension Int {
//    public var toBinaryString: String { return String(self, radix: 2) }
//    public var toHexaString:   String { return String(self, radix: 16) }
//}
