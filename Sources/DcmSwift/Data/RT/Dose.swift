//
//  Dose.swift
//  
//
//  Created by Paul on 15/07/2021.
//

import Foundation

/**
 Inspired byt DCMTK DRTDose class : https://support.dcmtk.org/docs/classDRTDose.html
 Helper class to get a dose in a pixel in a frame of the DICOM RT
 */
public class Dose {
    
    /**
     A dose is a pixel. The pixel can be signed or unsigned, on 32 bits or 16 bits
     We multiply the pixel by DoseGridScaling (called the scale), and we get the dose
     Be careful ! row, column and frame starts at 1, not 0
     
     - Parameters:
        - dicomRT: the DICOM RT file to parse
        - row: row where to get the dose to
        - column: column where to get the dose to
        - frame: the frame/image where to get the dose to
     
     - Returns: the dose or nil
     
     ```
     if let dose = Dose.getDose(dicomRT: dicomRT, row: 1, column: 1, frame: 1) {
        // ...
     }
     ```
     */
    public static func getDose(dicomRT: DicomRT, row: Int16, column: Int16, frame: Int16) -> Double? {
        guard let doseGridScaling: String = dicomRT.dataset.string(forTag: "DoseGridScaling") else {
            return nil
        }
        
        guard let dgs = Double(doseGridScaling) else {
            return nil
        }
        
        if dicomRT.pixelRepresentation == .Signed && dicomRT.bitsAllocated == 16 {
            guard let udi16 = unscaledDoseI16(dicomRT: dicomRT, row: row, column: column, frame: frame) else {
                return nil
            }
            return dgs * Double(udi16)
            
        } else if dicomRT.pixelRepresentation == .Signed && dicomRT.bitsAllocated == 32 {
            guard let udi32 = unscaledDoseI32(dicomRT: dicomRT, row: row, column: column, frame: frame) else {
                return nil
            }
            return dgs * Double(udi32)
            
        } else if dicomRT.pixelRepresentation == .Unsigned && dicomRT.bitsAllocated == 16 {
            guard let udu16 = unscaledDoseU16(dicomRT: dicomRT, row: row, column: column, frame: frame) else {
                return nil
            }
            return dgs * Double(udu16)
            
        } else if dicomRT.pixelRepresentation == .Unsigned && dicomRT.bitsAllocated == 32 {
            guard let udu32 = unscaledDoseU32(dicomRT: dicomRT, row: row, column: column, frame: frame) else {
                return nil
            }
            return dgs * Double(udu32)
        }
        
        return nil
    }
    
    public static func unscaledDoseU32(dicomRT: DicomRT, row: Int16, column: Int16, frame: Int16) -> UInt32? {
        return self.unscaledDose(dicomRT: dicomRT, row: row, column: column, frame: frame) as? UInt32
    }
    
    public static func unscaledDoseU16(dicomRT: DicomRT, row: Int16, column: Int16, frame: Int16) -> UInt16? {
        return self.unscaledDose(dicomRT: dicomRT, row: row, column: column, frame: frame) as? UInt16
    }
    
    public static func unscaledDoseI32(dicomRT: DicomRT, row: Int16, column: Int16, frame: Int16) -> Int32? {
        return self.unscaledDose(dicomRT: dicomRT, row: row, column: column, frame: frame) as? Int32
    }
    
    public static func unscaledDoseI16(dicomRT: DicomRT, row: Int16, column: Int16, frame: Int16) -> Int16? {
        return self.unscaledDose(dicomRT: dicomRT, row: row, column: column, frame: frame) as? Int16
    }
    
    /**
     Returns an unscaled dose, meaning we take the pixel out of the pixel data, but we don't multiply it by the scale (the dose grid scaling)
     ```
     if let unscaledDose = Dose.unscaledDose(dicomRT: dicomRT, row: 1, column: 1, frame: 1) {
        // ...
     }
     ```
     */
    public static func unscaledDose(dicomRT: DicomRT, row: Int16, column: Int16, frame: Int16) -> Any? {
        var pixelNumber = (frame - 1) * dicomRT.columns * dicomRT.rows
        pixelNumber += (row - 1) * dicomRT.columns + (column - 1)
        
        guard let pixelData = dicomRT.dataset.element(forTagName: "PixelData") else {
            return nil
        }
        
        switch dicomRT.pixelRepresentation {
        case .Signed:
            if dicomRT.bitsAllocated == 16 {
                return PixelDataAccess.getPixelSigned16(pixelDataElement: pixelData, pixelNumber: Int(pixelNumber), byteOrder: pixelData.byteOrder)
            } else {
                return PixelDataAccess.getPixelSigned32(pixelDataElement: pixelData, pixelNumber: Int(pixelNumber), byteOrder: pixelData.byteOrder)
            }
        case .Unsigned:
            if dicomRT.bitsAllocated == 16 {
                return PixelDataAccess.getPixelUnsigned16(pixelDataElement: pixelData, pixelNumber: Int(pixelNumber), byteOrder: pixelData.byteOrder)
            } else {
                return PixelDataAccess.getPixelUnsigned32(pixelDataElement: pixelData, pixelNumber: Int(pixelNumber), byteOrder: pixelData.byteOrder)
            }
        }
    }
    
    /**
     Width of image
     
     ```
     let width = Dose.getDoseImageWidth(dicomRT: dicomRT)
     ```
     
     - Returns: the width of the image
     */
    public static func getDoseImageWidth(dicomRT: DicomRT) -> Int16 {
        return dicomRT.columns
    }
    
    /**
     Height of image
     
     ```
     let height = Dose.getDoseImageHeight(dicomRT: dicomRT)
     ```
     
     - Returns: the height of the image
     */
    public static func getDoseImageHeight(dicomRT: DicomRT) -> Int16 {
        return dicomRT.rows
    }
    
    /**
     Gets an array of doses for a frame
     
     ```
     let doseImage = Dose.getDoseImage(dicomRT: dicomRT, atFrame: 1)
     ```
     
     - Returns: an array of doubles
     */
    public static func getDoseImage(dicomRT: DicomRT, atFrame: UInt) -> [Float64] {
        let theFrame = Int16(atFrame)
        
        let offset = Int((theFrame - 1) * dicomRT.rows * dicomRT.columns * dicomRT.bitsAllocated / 8)
        let end = Int((theFrame) * dicomRT.rows * dicomRT.columns * dicomRT.bitsAllocated / 8)
                
        guard let doseGridScaling: String = dicomRT.dataset.string(forTag: "DoseGridScaling") else {
            return []
        }
        
        guard let dgs = Float64(doseGridScaling) else {
            return []
        }
        
        guard let pixelData = dicomRT.dataset.element(forTagName: "PixelData") else {
            return []
        }
        
        switch dicomRT.pixelRepresentation {
        case .Signed:
            if dicomRT.bitsAllocated == 16 {
                let p = PixelDataAccess.getSigned16Pixels(pixelDataElement: pixelData, from: offset, at: end, byteOrder: pixelData.byteOrder)
                let a = p.compactMap{ Float64($0) }
                return a.map { $0 * dgs }
                
            } else {
                let p: [Int32] = PixelDataAccess.getSigned32Pixels(pixelDataElement: pixelData, from: offset, at: end, byteOrder: pixelData.byteOrder)
                let a = p.compactMap{ Float64($0) }
                return a.map { $0 * dgs }
                
            }
        case .Unsigned:
            if dicomRT.bitsAllocated == 16 {
                let p: [UInt16] = PixelDataAccess.getUnsigned16Pixels(pixelDataElement: pixelData, from: offset, at: end, byteOrder: pixelData.byteOrder)
                let a = p.compactMap{ Float64($0) }
                return a.map { $0 * dgs }
                
            } else {
                let p: [UInt32] = PixelDataAccess.getUnsigned32Pixels(pixelDataElement: pixelData, from: offset, at: end, byteOrder: pixelData.byteOrder)
                let a = p.compactMap{ Float64($0) }
                
                return a.map { $0 * dgs }
                
            }
        
        }
    }
    
    /**
     Return an array of dose image for all frames
     ```
     let doseImages = Dose.getDoseImages(dicomRT: dicomRT)
     ```
     
     - Returns: a 2D array of doses (doubles)
     */
    public static func getDoseImages(dicomRT: DicomRT) -> [[Float64]] {
        var images: [[Float64]] = []
        
        for f in 1...dicomRT.frames {
            images.append(getDoseImage(dicomRT: dicomRT, atFrame: UInt(f)))
        }
        
        return images
    }
    
    /**
     Check bits allocated is either 16 or 32
     ```
     Dose.isValid(dicomRT: dicomRT)
     ```
     
     - Returns: a boolean indicating success
     */
    public static func isValid(dicomRT: DicomRT) -> Bool {
        return dicomRT.bitsAllocated == 16 || dicomRT.bitsAllocated == 32
    }
}
