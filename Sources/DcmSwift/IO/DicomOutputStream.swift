//
//  DicomOutputSTream.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 23/06/2021.
//  Copyright © 2021 Read-Write.fr. All rights reserved.
//

import Foundation

public class DicomOutputStream {
    private var outputStream:OutputStream!
    
    public var vrMethod:VRMethod     = .Explicit
    public var byteOrder:ByteOrder   = .LittleEndian
    
    public init(filePath:String) {
        outputStream = OutputStream(toFileAtPath: filePath, append: false)
    }
    
    public init(url:URL) {
        outputStream = OutputStream(url: url, append: false)
    }
    
    public func write(dataset:DataSet) throws -> Bool {
        if dataset.transferSyntax.tsUID == TransferSyntax.implicitVRLittleEndian {
            vrMethod  = .Implicit
            byteOrder = .LittleEndian
        }
        else if dataset.transferSyntax.tsUID == TransferSyntax.explicitVRBigEndian {
            vrMethod  = .Explicit
            byteOrder = .BigEndian
        }
        
        return try write(dataset: dataset, vrMethod: vrMethod, byteOrder: byteOrder)
    }
    
    public func write(
        dataset:DataSet,
        vrMethod: VRMethod,
        byteOrder: ByteOrder
    ) throws -> Bool {
        if outputStream == nil {
            throw StreamError.cannotOpenStream(message: "Cannot open stream, init failed")
        }
        
        outputStream.open()
        
        if dataset.hasPreamble {
            // 128 bytes preamble
            try write(data: Data(repeating: 0x00, count: 128))
            
            // DICM magic word
            try write(data: DicomConstants.dicomMagicWord.data(using: .ascii)!)
        } else {
            // write empty 0008,0000 tag
            try write(data: Data([0x08, 0x00, 0x00, 0x00]))
        }
        
        // make sure element are in correct order
        dataset.sortElements()
        
        // write all elements
        try write(data: dataset.toData(vrMethod: vrMethod, byteOrder: byteOrder))
        
        outputStream.close()
        
        return true
    }
    
    
    
    private func write(data:Data) throws {
        try data.withUnsafeBytes { (unsafeBytes) in
            let bytes = unsafeBytes.bindMemory(to: UInt8.self).baseAddress!
                        
            let written = outputStream.write(bytes, maxLength: data.count)
            
            if written <= 0 {
                throw StreamError.cannotWriteStream(message: "Write to stream failed")
            }
        }
    }
}
