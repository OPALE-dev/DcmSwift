//
//  Dose.swift
//  
//
//  Created by Paul on 15/07/2021.
//

import Foundation

public class Dose {
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
    
    public static func getDoseImageWidth(dicomRT: DicomRT) -> Int16 {
        return dicomRT.columns
    }
    
    public static func getDoseImageHeight(dicomRT: DicomRT) -> Int16 {
        return dicomRT.rows
    }
    
    public static func getDoseImage(dicomRT: DicomRT, atFrame: UInt) -> [Float64] {
        let theFrame = Int16(atFrame)
        
        let offset = Int((theFrame - 1) * dicomRT.rows * dicomRT.columns * dicomRT.bitsAllocated / 8)
        let end = Int((theFrame) * dicomRT.rows * dicomRT.columns * dicomRT.bitsAllocated / 8)
        
        print(" \(offset)...\(end)")
        
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
    
    public static func getDoseImages(dicomRT: DicomRT) -> [[Float64]] {
        var images: [[Float64]] = []
        
        for f in 1...dicomRT.frames {
            images.append(getDoseImage(dicomRT: dicomRT, atFrame: UInt(f)))
        }
        
        return images
    }
    
    public static func isValid(dicomRT: DicomRT) -> Bool {
        return dicomRT.bitsAllocated == 16 || dicomRT.bitsAllocated == 32
    }
}
