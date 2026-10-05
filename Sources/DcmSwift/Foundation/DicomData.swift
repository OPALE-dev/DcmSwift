//
//  Data.swift
//  DICOM Test
//
//  Created by Rafael Warnault, OPALE on 17/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation




extension Data {
    init<T>(from value: T) {
        self = Swift.withUnsafeBytes(of: value) { Data($0) }
    }

    func to<T>(type: T.Type) -> T? where T: ExpressibleByIntegerLiteral {
        var value: T = 0
        guard count >= MemoryLayout.size(ofValue: value) else { return nil }
        _ = Swift.withUnsafeMutableBytes(of: &value, { copyBytes(to: $0)} )
        return value
    }
}



// https://stackoverflow.com/questions/38023838/round-trip-swift-number-types-to-from-data

extension Data {
    public func toString() -> String {
        if let string = String(data: self, encoding: String.Encoding.utf8) {
             return string.trimmingCharacters(in: CharacterSet.init(charactersIn: "\0"))
        }
        return ""
    }
    
    
    public func toHexString(withLimit limit:Int = -1) -> String {
        let data = limit >= 0 ? prefix(limit) : self[...]
        return "0x" + data.reduce("") { $0 + String(format: "%02x", $1) }
    }


    public func toHex() -> String {
        return self.reduce("") { $0 + String(format: "%02x", $1) }
    }
    
    

    
    public func toInt8(byteOrder: ByteOrder = .LittleEndian) -> Int8 {
        return Int8(bitPattern: toUInt8(byteOrder: byteOrder))
    }
    
    public func toUInt8(byteOrder: ByteOrder = .LittleEndian) -> UInt8 {
        return first ?? 0
    }
    
    
    public func toUInt16(byteOrder: ByteOrder = .LittleEndian) -> UInt16 {
        guard count >= 2 else { return 0 }
        let bytes = prefix(2)
        return byteOrder == .LittleEndian
            ? UInt16(bytes[bytes.startIndex]) | UInt16(bytes[bytes.index(after: bytes.startIndex)]) << 8
            : UInt16(bytes[bytes.startIndex]) << 8 | UInt16(bytes[bytes.index(after: bytes.startIndex)])
    }
    
    
    public func toInt16(byteOrder: ByteOrder = .LittleEndian) -> Int16 {
        return Int16(bitPattern: toUInt16(byteOrder: byteOrder))
    }
    
    
    public func toInt32(byteOrder: ByteOrder = .LittleEndian) -> Int32 {
        return Int32(bitPattern: toUInt32(byteOrder: byteOrder))
    }
    
    public func toUInt32(byteOrder: ByteOrder = .LittleEndian) -> UInt32 {
        guard count >= 4 else { return 0 }
        let bytes = Array(prefix(4))
        if byteOrder == .LittleEndian {
            return bytes.enumerated().reduce(0) { $0 | UInt32($1.element) << UInt32($1.offset * 8) }
        }
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    public func toInt64(byteOrder: ByteOrder = .LittleEndian) -> Int64 {
        return Int64(bitPattern: toUInt64(byteOrder: byteOrder))
    }

    public func toUInt64(byteOrder: ByteOrder = .LittleEndian) -> UInt64 {
        guard count >= 8 else { return 0 }
        let bytes = Array(prefix(8))
        if byteOrder == .LittleEndian {
            return bytes.enumerated().reduce(0) { $0 | UInt64($1.element) << UInt64($1.offset * 8) }
        }
        return bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }
    
    public func toFloat32(byteOrder: ByteOrder = .LittleEndian) -> Float32 {
        return Float32(bitPattern: toUInt32(byteOrder: byteOrder))
    }
    
    
    public func toFloat64(byteOrder: ByteOrder = .LittleEndian) -> Float64 {
        return Float64(bitPattern: toUInt64(byteOrder: byteOrder))
    }
    
    public func toUnsigned8Array() -> [UInt8] {
        return self.map { $0 }
    }
    
    public func toSigned8Array() -> [Int8] {
        return self.map { Int8(bitPattern: $0) }
    }
    

    
    mutating func append(byte data: UInt8, count:Int = 1) {
        self.append(Data(repeating: data, count: count))
    }
    

    
    mutating func append(uint8 data: UInt8, bigEndian: Bool = false) {
        let value = bigEndian ? data.bigEndian : data.littleEndian
        self.append(Data(from: value))
    }
    
    
    mutating func append(uint16 data: UInt16, bigEndian: Bool = false) {
        let value = bigEndian ? data.bigEndian : data.littleEndian
        self.append(Data(from: value))
    }
    
    
    mutating func append(uint32 data: UInt32, bigEndian: Bool = false) {
        let value = bigEndian ? data.bigEndian : data.littleEndian
        self.append(Data(from: value))
    }
    
    
    mutating func append(uint64 data: UInt64, bigEndian: Bool = false) {
        let value = bigEndian ? data.bigEndian : data.littleEndian
        self.append(Data(from: value))
    }
    
    
    public func chunked(into size: Int) -> [Data] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            subdata(in: $0..<Swift.min($0 + size, count))
        }
    }

    @available(*, deprecated, renamed: "chunked(into:)")
    public func chunck(into size:Int) -> [Data] {
        return chunked(into: size)
    }
}


extension Array {
    public func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
