//
//  Data.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 17/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation


extension Data {
    public func toString() -> String {
        if let string = String(data: self, encoding: String.Encoding.utf8) {
             return string.trimmingCharacters(in: CharacterSet.init(charactersIn: "\0"))
        }
        return ""
    }
    
    
    public func toHexString(withLimit limit:Int = -1) -> String {
        var data = self
        
        if limit != -1 && limit < data.count-1 {
            data = data.subdata(in: limit..<data.count-1)
        }
        return "0x" + data.reduce("") { $0 + String(format: "%02x", $1) }
    }


    public func toHex() -> String {
        return self.reduce("") { $0 + String(format: "%02x", $1) }
    }

    
    public func toInt8(byteOrder: DicomSpec.ByteOrder = .LittleEndian) -> Int8 {
        let i:Int8 = self.withUnsafeBytes { $0.pointee }
        return byteOrder == .LittleEndian ? i : i.bigEndian
    }
    
    
    public func toInt16(byteOrder: DicomSpec.ByteOrder = .LittleEndian) -> Int16 {
        let i:Int16 = self.withUnsafeBytes { $0.pointee }
        return byteOrder == .LittleEndian ? i : i.bigEndian
    }
    
    
    public func toInt32(byteOrder: DicomSpec.ByteOrder = .LittleEndian) -> Int32 {
        let i:Int32 = self.withUnsafeBytes { $0.pointee }
        return byteOrder == .LittleEndian ? i : i.bigEndian
    }
    
    
    public func toFloat32(byteOrder: DicomSpec.ByteOrder = .LittleEndian) -> Float32 {
        return byteOrder == .LittleEndian ? self.withUnsafeBytes { $0.pointee } :
            Float32(bitPattern: UInt32(bigEndian: self.withUnsafeBytes { $0.pointee } ))
    }
    
    
    public func toFloat64(byteOrder: DicomSpec.ByteOrder = .LittleEndian) -> Float64 {
        return byteOrder == .LittleEndian ? self.withUnsafeBytes { $0.pointee } :
            Float64(bitPattern: UInt64(bigEndian: self.withUnsafeBytes { $0.pointee } ))
    }
    
    public func toUnsigned8Array() -> [UInt8] {
        return self.map { $0 }
    }
    
    public func toSigned8Array() -> [Int8] {
        return self.map { Int8(bitPattern: $0) }
    }
}


extension Array {
    public func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
