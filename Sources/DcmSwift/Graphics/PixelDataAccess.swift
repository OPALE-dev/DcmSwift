//
//  PixelDataAccess.swift
//  
//
//  Created by Paul on 08/07/2021.
//

import Foundation

/**
 Inspired by dcmtk rt files : https://github.com/DCMTK/dcmtk/blob/master/dcmrt/libsrc/drmdose.cc
 
 - TODO: refactor? uint16, int16, uint32, int32
 
 
  ```
    if let dicomRT = DicomRT.init(forPath: "path/to/file.dicom") {
        if let pixelData = dicomRT.dataset.element(forTagName: "PixelData") {
            let pixel: Int16 = PixelDataAccess.getPixelSigned16(pixelDataElement: pixelData,
                                                                pixelNumber: 12,
                                                                byteOrder: pixelData.byteOrder)
        }
    }
  ```
 */
public class PixelDataAccess {

    /**
     Returns the pixel as Signed 32 bits integer
     
     - Parameters:
        - pixelDataElement: the Pixel Data element
        - pixelNumber: the pixel to get
        - byteOrder: byte order of the stored pixel value
     */
    public static func getPixelSigned32(pixelDataElement: DataElement, pixelNumber: Int, byteOrder: ByteOrder) -> Int32? {
        return pixelBytes(pixelDataElement, pixelNumber: pixelNumber, width: 4)?.toInt32(byteOrder: byteOrder)
    }
    
    /**
     Returns the pixel as Unsigned 32 bits integer
     
     - Returns: the pixel in unsigned 32
     */
    public static func getPixelUnsigned32(pixelDataElement: DataElement, pixelNumber: Int, byteOrder: ByteOrder) -> UInt32? {
        return pixelBytes(pixelDataElement, pixelNumber: pixelNumber, width: 4)?.toUInt32(byteOrder: byteOrder)
    }
    
    /**
     Returns the pixel as Signed 16 bits integer
     */
    public static func getPixelSigned16(pixelDataElement: DataElement, pixelNumber: Int, byteOrder: ByteOrder) -> Int16? {
        return pixelBytes(pixelDataElement, pixelNumber: pixelNumber, width: 2)?.toInt16(byteOrder: byteOrder)
    }
    
    /**
     Returns the pixel as Unsigned 16 integer
     */
    public static func getPixelUnsigned16(pixelDataElement: DataElement, pixelNumber: Int, byteOrder: ByteOrder) -> UInt16? {
        return pixelBytes(pixelDataElement, pixelNumber: pixelNumber, width: 2)?.toUInt16(byteOrder: byteOrder)
    }
    
    
    
    /**
     Get all pixels in a range, as unsigned 16 bits integer
     */
    public static func getUnsigned16Pixels(pixelDataElement: DataElement, from: Int, at: Int, byteOrder: ByteOrder) -> [UInt16] {
        return pixelRange(pixelDataElement, from: from, to: at, width: 2)?.map {
            $0.toUInt16(byteOrder: byteOrder)
        } ?? []
    }
    
    /**
     Get all pixels in a range, as unsigned 32 bits integer
     */
    public static func getUnsigned32Pixels(pixelDataElement: DataElement, from: Int, at: Int, byteOrder: ByteOrder) -> [UInt32] {
        return pixelRange(pixelDataElement, from: from, to: at, width: 4)?.map {
            $0.toUInt32(byteOrder: byteOrder)
        } ?? []
    }
    
    /**
     Get all pixels in a range, as signed 16 bits integer
     */
    public static func getSigned16Pixels(pixelDataElement: DataElement, from: Int, at: Int, byteOrder: ByteOrder) -> [Int16] {
        return pixelRange(pixelDataElement, from: from, to: at, width: 2)?.map {
            $0.toInt16(byteOrder: byteOrder)
        } ?? []
    }
    
    /**
     Get all pixels in a range, as signed 32 bits integer
     */
    public static func getSigned32Pixels(pixelDataElement: DataElement, from: Int, at: Int, byteOrder: ByteOrder) -> [Int32] {
        return pixelRange(pixelDataElement, from: from, to: at, width: 4)?.map {
            $0.toInt32(byteOrder: byteOrder)
        } ?? []
    }

    private static func pixelBytes(_ element: DataElement, pixelNumber: Int, width: Int) -> Data? {
        guard pixelNumber >= 0, let data = element.data else { return nil }
        let (lowerBound, overflow) = pixelNumber.multipliedReportingOverflow(by: width)
        guard !overflow, lowerBound <= data.count, width <= data.count - lowerBound else { return nil }
        return data.subdata(in: lowerBound..<lowerBound + width)
    }

    private static func pixelRange(_ element: DataElement, from: Int, to: Int, width: Int) -> [Data]? {
        guard let data = element.data,
              from >= 0,
              to >= from,
              to <= data.count,
              (to - from).isMultiple(of: width) else { return nil }
        return stride(from: from, to: to, by: width).map {
            data.subdata(in: $0..<$0 + width)
        }
    }
}
