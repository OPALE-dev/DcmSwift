//
//  PixelDataAccess.swift
//  
//
//  Created by Paul on 08/07/2021.
//

import Foundation

/*
 Inspired by dcmtk rt files : https://github.com/DCMTK/dcmtk/blob/master/dcmrt/libsrc/drmdose.cc
 TODO refactor? uint16, int16, uint32, int32
 */
public class PixelDataAccess {
    
    public static func getPixel(pixelDataElement: DataElement, pixelNumber: Int, length: UInt, pixelRepresentation: DicomImage.PixelRepresentation) -> Any? {
        if pixelRepresentation == .Signed && length == 16 {
            return getPixelSigned16(pixelDataElement: pixelDataElement, pixelNumber: pixelNumber)
        } else if pixelRepresentation == .Signed && length == 32 {
            return getPixelSigned32(pixelDataElement: pixelDataElement, pixelNumber: pixelNumber)
        } else if pixelRepresentation == .Unsigned && length == 16 {
            return getPixelUnsigned16(pixelDataElement: pixelDataElement, pixelNumber: pixelNumber)
        } else if pixelRepresentation == .Unsigned && length == 32 {
            return getPixelUnsigned32(pixelDataElement: pixelDataElement, pixelNumber: pixelNumber)
        }
        
        return nil
    }
    
    public static func getPixelSigned32(pixelDataElement: DataElement, pixelNumber: Int) -> Int32? {
        let reader = DicomInputStream(data: pixelDataElement.data)
        
        reader.forward(by: pixelNumber)
        return reader.read(length: 32) as? Int32
    }
    
    public static func getPixelUnsigned32(pixelDataElement: DataElement, pixelNumber: Int) -> UInt32? {
        let reader = DicomInputStream(data: pixelDataElement.data)
        
        reader.forward(by: pixelNumber)
        return reader.read(length: 32) as? UInt32
    }
    
    public static func getPixelSigned16(pixelDataElement: DataElement, pixelNumber: Int) -> Int16? {
        let reader = DicomInputStream(data: pixelDataElement.data)
        
        reader.forward(by: pixelNumber)
        return reader.read(length: 16) as? Int16
    }
    
    public static func getPixelUnsigned16(pixelDataElement: DataElement, pixelNumber: Int) -> UInt16? {
        let reader = DicomInputStream(data: pixelDataElement.data)
        
        reader.forward(by: pixelNumber)
        return reader.read(length: 16) as? UInt16
    }
}
