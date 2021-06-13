//
//  DicomInputStream.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 10/06/2021.
//  Copyright © 2021 Read-Write.fr. All rights reserved.
//

import Foundation

public class DicomInputStream {
    var data:Data!
    var offset:Int = 0
    var hasBytesAvailable: Bool {
        get {
            return offset < data.count
        }
    }
    
    public init(data:Data) {
        self.data = data
    }
    
    public func read(length: Int) -> Data {
        if offset + length > data.count {
            return Data()
        }
        
        let chunk = data.subdata(in: offset..<(offset + length))
        
        offset += length
        
        return chunk
    }
    
    public func readDataTag(order:DicomConstants.ByteOrder = .LittleEndian) -> DataTag? {
        let tagData = self.read(length: 4)
        
        if tagData.count < 4 {
            return nil
        }
        
        let tag = DataTag(withData:tagData, byteOrder:order)
                        
        return tag
    }
    
    public func forward(by bytes: Int) {
        print("forward \(bytes)")
        offset += bytes
    }
    
    public func backward(by bytes: Int) {
        offset -= bytes
    }
}
