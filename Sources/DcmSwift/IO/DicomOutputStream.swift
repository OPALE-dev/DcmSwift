//
//  DicomOutputSTream.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 23/06/2021.
//  Copyright © 2021 OPALE. All rights reserved.
//

import Foundation

/**
 Class reponsible for writting DICOM files to output streams (files)
 */
public class DicomOutputStream {
    private var outputStream:OutputStream!
    
    public var vrMethod:VRMethod     = .Explicit
    public var byteOrder:ByteOrder   = .LittleEndian
    
    /**
     Creates a `DicomOutputStream`
     
     - Parameter filePath: the path to write the DICOM file to
     */
    public init(filePath:String) {
        outputStream = OutputStream(toFileAtPath: filePath, append: false)
    }
    
    /**
     - Parameter url: the location to write the DICOM file to
     */
    public init(url:URL) {
        outputStream = OutputStream(url: url, append: false)
    }
    
    /**
     Writes a given `DataSet` in the output stream
     
     - Parameter dataset: the `DataSet` to write
     - Throws: StreamError.cannotOpenStream, StreamError.cannotWriteStream
     - Returns: a boolean indicating success
     */
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
    
    /**
     Writes a given `DataSet` in the output stream, given a VR method (explicit, implicit) and a byte order
     
     - Parameters:
        - dataset: the `DataSet` to write
     - Throws: StreamError.cannotOpenStream, StreamError.cannotWriteStream
     - Returns: a boolean indicating success
     */
    public func write(
        dataset:DataSet,
        vrMethod: VRMethod? = nil,
        byteOrder: ByteOrder? = nil
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
        }
        
        // make sure element are in correct order
        dataset.sortElements()
        
        // write all elements
        try write(data: dataset.toData(vrMethod: nil, byteOrder: nil))
        
        outputStream.close()
        
        return true
    }
    
    
    /**
     Writes `Data` in the output stream
     
     - Parameters:
        - data: the `Data` to write
     - Throws: StreamError.cannotWriteStream
     */
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
