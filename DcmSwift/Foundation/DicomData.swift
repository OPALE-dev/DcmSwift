//
//  Data.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 17/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation



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
    
    
    var uint8: UInt8 {
        get {
            var number: UInt8 = 0
            self.copyBytes(to:&number, count: MemoryLayout<UInt8>.size)
            return number
        }
    }
    
//    var uint16: UInt16 {
//        get {
//            let i16array = self.withUnsafeBytes {
//                UnsafeBufferPointer<UInt16>(start: $0, count: self.count/2).map(UInt16.init(littleEndian:))
//            }
//            return i16array[0]
//        }
//    }
    
    var uint32: UInt32 {
        get {
            let i32array = self.withUnsafeBytes {
                UnsafeBufferPointer<UInt32>(start: $0, count: self.count/2).map(UInt32.init(littleEndian:))
            }
            return i32array[0]
        }
    }
    

    
    public func toInt8(byteOrder: DicomConstants.ByteOrder = .LittleEndian) -> Int8 {
        let i:Int8 = self.withUnsafeBytes { $0.pointee }
        return byteOrder == .LittleEndian ? i : i.bigEndian
    }
    
    
    public func toUInt16(byteOrder: DicomConstants.ByteOrder = .LittleEndian) -> UInt16 {
        if (byteOrder == .LittleEndian) {
            let i16array = self.withUnsafeBytes {
                return UnsafeBufferPointer<UInt16>(start: $0, count: self.count/2).map(UInt16.init(littleEndian:))
            }
            return i16array[0]
        } else {
            let i16array = self.withUnsafeBytes {
                return UnsafeBufferPointer<UInt16>(start: $0, count: self.count/2).map(UInt16.init(bigEndian:))
                
            }
            return i16array[0]
        }
    }
    
    
    public func toInt16(byteOrder: DicomConstants.ByteOrder = .LittleEndian) -> Int16 {
        let i:Int16 = self.withUnsafeBytes { $0.pointee }
        return byteOrder == .LittleEndian ? i : i.bigEndian
    }
    
    
    public func toInt32(byteOrder: DicomConstants.ByteOrder = .LittleEndian) -> Int32 {
        let i:Int32 = self.withUnsafeBytes { $0.pointee }
        return byteOrder == .LittleEndian ? i : i.bigEndian
    }
    
    
    public func toFloat32(byteOrder: DicomConstants.ByteOrder = .LittleEndian) -> Float32 {
        return byteOrder == .LittleEndian ? self.withUnsafeBytes { $0.pointee } :
            Float32(bitPattern: UInt32(bigEndian: self.withUnsafeBytes { $0.pointee } ))
    }
    
    
    public func toFloat64(byteOrder: DicomConstants.ByteOrder = .LittleEndian) -> Float64 {
        return byteOrder == .LittleEndian ? self.withUnsafeBytes { $0.pointee } :
            Float64(bitPattern: UInt64(bigEndian: self.withUnsafeBytes { $0.pointee } ))
    }
    
    public func toUnsigned8Array() -> [UInt8] {
        return self.map { $0 }
    }
    
    public func toSigned8Array() -> [Int8] {
        return self.map { Int8(bitPattern: $0) }
    }
    

    
    mutating func append(byte data: Int8, count:Int = 1) {
        var data = data
        self.append(UnsafeBufferPointer(start: &data, count: count))
    }
    
    
    mutating func append(uint8 data: UInt8, bigEndian: Bool = true) {
        var data = bigEndian ? data.bigEndian : data.littleEndian
        self.append(UnsafeBufferPointer(start: &data, count: 1))
    }
    
    
    mutating func append(uint16 data: UInt16, bigEndian: Bool = true) {
        var data = bigEndian ? data.bigEndian : data.littleEndian
        self.append(UnsafeBufferPointer(start: &data, count: 1))
    }
    
    
    mutating func append(uint32 data: UInt32, bigEndian: Bool = true) {
        var data = bigEndian ? data.bigEndian : data.littleEndian
        self.append(UnsafeBufferPointer(start: &data, count: 1))
    }
    
    
    mutating func append(uint64 data: UInt64, bigEndian: Bool = true) {
        var data = bigEndian ? data.bigEndian : data.littleEndian
        self.append(UnsafeBufferPointer(start: &data, count: 1))
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
