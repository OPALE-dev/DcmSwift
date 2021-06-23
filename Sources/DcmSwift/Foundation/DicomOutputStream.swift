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
    
    public var vrMethod:DicomConstants.VRMethod     = .Explicit
    public var byteOrder:DicomConstants.ByteOrder   = .LittleEndian
    
    public init(filePath:String) {
        outputStream = OutputStream(toFileAtPath: filePath, append: false)
    }
    
    public init(url:URL) {
        outputStream = OutputStream(url: url, append: false)
    }
    
    public func write(dataset:DataSet) throws -> Bool {
        if outputStream == nil {
            throw StreamError.cannotOpenStream
        }
        
        outputStream.open()
        
        if dataset.transferSyntax.tsUID == DicomConstants.implicitVRLittleEndian {
            vrMethod  = .Implicit
            byteOrder = .LittleEndian
        }
        else if dataset.transferSyntax.tsUID == DicomConstants.explicitVRBigEndian {
            vrMethod  = .Explicit
            byteOrder = .BigEndian
        }
        
        if dataset.hasPreamble {
            // 128 bytes preamble
            try write(data: Data(repeating: 0x00, count: 128))
            
            // DICM magic word
            try write(data: DicomConstants.dicomMagicWord.data(using: .ascii)!)
        }
        
        // make sure element are in correct order
        dataset.sortElements()
        
        // write all elements
        for element in dataset.allElements {
            var elementData = element.toData(vrMethod: vrMethod, byteOrder: byteOrder)
            
            // force Meta Info Group elements in Explicit VR LittleEndian
            if element.group == "0002" {
                elementData = element.toData(vrMethod: .Explicit, byteOrder: .LittleEndian)
            }
            
            try write(data: elementData)
        }
        
        return true
    }
    
    
    private func write(data:Data) throws {
        try data.withUnsafeBytes { (unsafeBytes) in
            let bytes = unsafeBytes.bindMemory(to: UInt8.self).baseAddress!
            
            let written = outputStream.write(bytes, maxLength: data.count)
            
            if written <= 0 {
                throw StreamError.cannotWriteStream
            }
        }
    }
}
