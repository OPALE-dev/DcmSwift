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
        guard let syntax = dataset.transferSyntax,
              syntax.capability.canWriteDataset else {
            throw StreamError.unsupportedTransferSyntax(uid: dataset.transferSyntax?.tsUID ?? "")
        }
        vrMethod = syntax.vrMethod
        byteOrder = syntax.byteOrder
        
        return try writePrepared(
            dataset: dataset,
            vrMethod: vrMethod,
            byteOrder: byteOrder,
            transferSyntaxUID: syntax.tsUID
        )
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
        if vrMethod == nil, byteOrder == nil, let syntax = dataset.transferSyntax {
            guard syntax.capability.canWriteDataset else {
                throw StreamError.unsupportedTransferSyntax(uid: syntax.tsUID)
            }
            return try writePrepared(
                dataset: dataset,
                vrMethod: syntax.vrMethod,
                byteOrder: syntax.byteOrder,
                transferSyntaxUID: syntax.tsUID
            )
        }

        let finalVR = vrMethod ?? dataset.transferSyntax?.vrMethod ?? self.vrMethod
        let finalOrder = byteOrder ?? dataset.transferSyntax?.byteOrder ?? self.byteOrder
        let syntaxUID: String
        switch (finalVR, finalOrder) {
        case (.Implicit, .LittleEndian): syntaxUID = TransferSyntax.implicitVRLittleEndian
        case (.Explicit, .LittleEndian): syntaxUID = TransferSyntax.explicitVRLittleEndian
        case (.Explicit, .BigEndian): syntaxUID = TransferSyntax.explicitVRBigEndian
        case (.Implicit, .BigEndian):
            throw StreamError.unsupportedTransferSyntax(uid: "Implicit VR Big Endian")
        }

        return try writePrepared(
            dataset: dataset,
            vrMethod: finalVR,
            byteOrder: finalOrder,
            transferSyntaxUID: syntaxUID
        )
    }

    private func writePrepared(
        dataset: DataSet,
        vrMethod: VRMethod,
        byteOrder: ByteOrder,
        transferSyntaxUID syntaxUID: String
    ) throws -> Bool {
        if outputStream == nil {
            throw StreamError.cannotOpenStream(message: "Cannot open stream, init failed")
        }

        guard DICOMCapabilities.transferSyntax(syntaxUID).canWriteDataset else {
            throw StreamError.unsupportedTransferSyntax(uid: syntaxUID)
        }
        try dataset.materializeBulkData()
        dataset.transferSyntax = TransferSyntax(syntaxUID)
        if dataset.hasPreamble || !dataset.metaInformationHeaderElements.isEmpty {
            _ = dataset.set(value: syntaxUID, forTagName: "TransferSyntaxUID")
            _ = dataset.recalculateFileMetaInformationGroupLength()
        }

        outputStream.open()
        defer { outputStream.close() }
        
        if dataset.hasPreamble {
            // 128 bytes preamble
            try write(data: Data(repeating: 0x00, count: 128))
            
            // DICM magic word
            try write(data: DicomConstants.dicomMagicWord.data(using: .ascii)!)
        }
        
        // make sure element are in correct order
        dataset.sortElements()

        if syntaxUID == TransferSyntax.deflatedExplicitVRLittleEndian {
            let metaData = dataset.metaInformationHeaderElements.reduce(into: Data()) {
                $0.append($1.toData(vrMethod: .Explicit, byteOrder: .LittleEndian))
            }
            let dataSetBytes = dataset.datasetElements.reduce(into: Data()) {
                $0.append($1.toData(vrMethod: .Explicit, byteOrder: .LittleEndian))
            }
            try write(data: metaData)
            try write(data: DICOMDeflate.compress(dataSetBytes))
        } else {
            // write all elements
            try write(data: dataset.toData(vrMethod: vrMethod, byteOrder: byteOrder))
        }
        
        return true
    }
    
    
    /**
     Writes `Data` in the output stream
     
     - Parameters:
        - data: the `Data` to write
     - Throws: StreamError.cannotWriteStream
     */
    private func write(data:Data) throws {
        if data.isEmpty { return }
        try data.withUnsafeBytes { (unsafeBytes) in
            guard let bytes = unsafeBytes.bindMemory(to: UInt8.self).baseAddress else {
                throw StreamError.cannotWriteStream(message: "Cannot access bytes to write")
            }
            var totalWritten = 0
            while totalWritten < data.count {
                let written = outputStream.write(
                    bytes.advanced(by: totalWritten),
                    maxLength: data.count - totalWritten
                )
                if written <= 0 {
                    throw StreamError.cannotWriteStream(message: "Write to stream failed")
                }
                totalWritten += written
            }
        }
    }
}
