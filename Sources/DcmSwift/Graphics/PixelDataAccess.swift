//
//  PixelDataAccess.swift
//  
//
//  Created by Paul on 08/07/2021.
//

import Foundation

// TODO refactor, can't pass byte order https://stackoverflow.com/questions/30195267/how-to-byte-reverse-nsdata-output-in-swift-the-littleendian-way
extension Data {
    var uint32: UInt32 {
        withUnsafeBytes { $0.bindMemory(to: UInt32.self) }[0]
    }
}

/**
 Inspired by dcmtk rt files : https://github.com/DCMTK/dcmtk/blob/master/dcmrt/libsrc/drmdose.cc
 TODO refactor? uint16, int16, uint32, int32
 TODO take into account byte order
 
 
  ```
 let pixel: Int16 = PixelDataAccess.getPixelSigned16(pixelDataElement: pixelData, pixelNumber: pixelNumber, byteOrder: byteOrder)
  ```
 */
public class PixelDataAccess {
    
    // TODO remove
    public static func getPixel(pixelDataElement: DataElement, pixelNumber: Int, length: UInt,
                                pixelRepresentation: DicomImage.PixelRepresentation, byteOrder: ByteOrder) -> Any? {
        
        if pixelRepresentation == .Signed && length == 16 {
            return getPixelSigned16(pixelDataElement: pixelDataElement, pixelNumber: pixelNumber, byteOrder: byteOrder)
            
        } else if pixelRepresentation == .Signed && length == 32 {
            return getPixelSigned32(pixelDataElement: pixelDataElement, pixelNumber: pixelNumber, byteOrder: byteOrder)
            
        } else if pixelRepresentation == .Unsigned && length == 16 {
            return getPixelUnsigned16(pixelDataElement: pixelDataElement, pixelNumber: pixelNumber, byteOrder: byteOrder)
            
        } else if pixelRepresentation == .Unsigned && length == 32 {
            return getPixelUnsigned32(pixelDataElement: pixelDataElement, pixelNumber: pixelNumber, byteOrder: byteOrder)
        }
        
        return nil
    }
    
    public static func getPixelSigned32(pixelDataElement: DataElement, pixelNumber: Int, byteOrder: ByteOrder) -> Int32? {
        let lowerBound = pixelNumber * 4
        let upperBound = pixelNumber * 4 + 32
        let  d = pixelDataElement.data.subdata(in: lowerBound..<upperBound)
        
        return d.toInt32(byteOrder: byteOrder)
    }
    
    public static func getPixelUnsigned32(pixelDataElement: DataElement, pixelNumber: Int, byteOrder: ByteOrder) -> UInt32? {
        let lowerBound = pixelNumber * 4
        let upperBound = pixelNumber * 4 + 32
        let  d = pixelDataElement.data.subdata(in: lowerBound..<upperBound)
            
        // TODO zqmrgiojqemrgijqermgioj refactor
        return d.uint32
    }
    
    public static func getPixelSigned16(pixelDataElement: DataElement, pixelNumber: Int, byteOrder: ByteOrder) -> Int16? {
        let lowerBound = pixelNumber * 4
        let upperBound = pixelNumber * 4 + 16
        let  d = pixelDataElement.data.subdata(in: lowerBound..<upperBound)
        
        return d.toInt16(byteOrder: byteOrder)
    }
    
    public static func getPixelUnsigned16(pixelDataElement: DataElement, pixelNumber: Int, byteOrder: ByteOrder) -> UInt16? {
        let lowerBound = pixelNumber * 4
        let upperBound = pixelNumber * 4 + 16
        let  d = pixelDataElement.data.subdata(in: lowerBound..<upperBound)

        return d.toUInt16(byteOrder: byteOrder)
    }
}
