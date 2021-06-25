//
//  Data.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 17/10/2017.
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
        var data = self
        
        if limit != -1 && limit < data.count-1 {
            data = data.subdata(in: limit..<data.count-1)
        }
        return "0x" + data.reduce("") { $0 + String(format: "%02x", $1) }
    }


    public func toHex() -> String {
        return self.reduce("") { $0 + String(format: "%02x", $1) }
    }
    
    

    
    public func toInt8(byteOrder: ByteOrder = .LittleEndian) -> Int8 {
        return self.withUnsafeBytes( { (ptr : UnsafeRawBufferPointer) in
            let pointer = ptr.baseAddress!.assumingMemoryBound(to: Int8.self).pointee
            return byteOrder == .LittleEndian ? pointer : pointer.bigEndian
        })
    }
    
    
    public func toUInt16(byteOrder: ByteOrder = .LittleEndian) -> UInt16 {
        return self.withUnsafeBytes( { (ptr : UnsafeRawBufferPointer) in
            let pointer = ptr.baseAddress!.assumingMemoryBound(to: UInt16.self).pointee
            return byteOrder == .LittleEndian ? CFSwapInt16HostToLittle(pointer) : CFSwapInt16HostToBig(pointer)
        })
    }
    
    
    public func toInt16(byteOrder: ByteOrder = .LittleEndian) -> Int16 {
        return self.withUnsafeBytes( { (ptr : UnsafeRawBufferPointer) in
            let pointer = ptr.baseAddress!.assumingMemoryBound(to: Int16.self).pointee
            return byteOrder == .LittleEndian ? pointer : pointer.bigEndian
        })
    }
    
    
    public func toInt32(byteOrder: ByteOrder = .LittleEndian) -> Int32 {
        return self.withUnsafeBytes( { (ptr : UnsafeRawBufferPointer) in
            let pointer = ptr.baseAddress!.assumingMemoryBound(to: Int32.self).pointee
            return byteOrder == .LittleEndian ? pointer : pointer.bigEndian
        })
    }
    
    
    public func toFloat32(byteOrder: ByteOrder = .LittleEndian) -> Float32 {
        return self.withUnsafeBytes( { (ptr : UnsafeRawBufferPointer) in
            let pointer = ptr.baseAddress!.assumingMemoryBound(to: UInt32.self).pointee
            return byteOrder == .LittleEndian ? Float32(bitPattern: pointer) : Float32(bitPattern: UInt32(bigEndian: pointer))
        })
    }
    
    
    public func toFloat64(byteOrder: ByteOrder = .LittleEndian) -> Float64 {
        return self.withUnsafeBytes( { (ptr : UnsafeRawBufferPointer) in
            let pointer = ptr.baseAddress!.assumingMemoryBound(to: UInt64.self).pointee
            return byteOrder == .LittleEndian ? Float64(bitPattern: pointer) : Float64(bitPattern: UInt64(bigEndian: pointer))
        })
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
    

    
    mutating func append(uint8 data: UInt8, bigEndian: Bool = true) {
        let value = bigEndian ? data.bigEndian : data.littleEndian
        self.append(Data(from: value))
    }
    
    
    mutating func append(uint16 data: UInt16, bigEndian: Bool = true) {
        let value = bigEndian ? data.bigEndian : data.littleEndian
        self.append(Data(from: value))
    }
    
    
    mutating func append(uint32 data: UInt32, bigEndian: Bool = true) {
        let value = bigEndian ? data.bigEndian : data.littleEndian
        self.append(Data(from: value))
    }
    
    
    mutating func append(uint64 data: UInt64, bigEndian: Bool = true) {
        let value = bigEndian ? data.bigEndian : data.littleEndian
        self.append(Data(from: value))
    }
    
    
    public func chunck(into size:Int) ->  [Data] {
        let dataLen = self.count
        let chunkSize = size
        
        let fullChunks = Int(dataLen / chunkSize)
        let totalChunks = fullChunks + (dataLen % 1024 != 0 ? 1 : 0)
        
        var chunks:[Data] = [Data]()
        
        for chunkCounter in 0..<totalChunks {
            var chunk:Data
            let chunkBase = chunkCounter * chunkSize
            var diff = chunkSize
            if(chunkCounter == totalChunks - 1) {
                diff = dataLen - chunkBase
            }
            
            chunk = self.subdata(in: chunkBase..<(chunkBase + diff))
            chunks.append(chunk)
        }
        return chunks
    }
}


extension Array {
    public func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
