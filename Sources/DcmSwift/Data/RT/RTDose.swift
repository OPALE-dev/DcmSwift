//
//  RTDose.swift
//  
//
//  Created by Paul on 07/07/2021.
//

import Foundation





extension Collection where Iterator.Element == Int16 {
    var doubleArray: [Double] {
        return flatMap{ Double($0) }
    }
    var floatArray: [Float] {
        return flatMap{ Float($0) }
    }
}






/**
 Helper functions
 TODO why not extension ?
 */
public class RTDose {
    
    // The following properties are redundant with dose of the same dicom file
    // (the number of columns, rows and frames are the same for example)
    public let dicomRT: DicomRT
    public var pixelRepresentation: DicomImage.PixelRepresentation!
    public var bitsAllocated: Int16
    public var columns: Int16
    public var rows: Int16
    public var frames: Int16
    
    public var column: Int16
    public var row: Int16
    public var frame: Int16

    /// column, row and frame begins at 1 (not 0 !)
    public init?(dicomRTFile: DicomRT, column: Int16, row: Int16, frame: Int16) {

        guard let imageParams = dicomRTFile.getImageParameters() else {
            return nil
        }
        
        let (frames, rows, columns, bitsAllocated, pixelRepresentation) = imageParams
        
        if bitsAllocated != 16 && bitsAllocated != 32 {
            return nil
        }
        
        if frame > frames || column > columns || row > rows {
            Logger.warning("frame > frames, or column > columns, or row > rows")
            Logger.warning("frame: \(frame) / frames: \(frames) ; column: \(column) / columns: \(columns) ; row: \(row) / rows: \(rows)")
            return nil
        }
        
        self.dicomRT = dicomRTFile
        if let p = DicomImage.PixelRepresentation.init(rawValue: Int(pixelRepresentation)) {
            self.pixelRepresentation = p
        }
        self.bitsAllocated = bitsAllocated
        
        self.columns = columns
        self.rows    = rows
        self.frames  = frames
        
        self.column  = column
        self.row     = row
        self.frame   = frame
    }
    
    
    // unscaled dose * grid scaling
    public lazy var dose: Float64? = {
        guard let doseGridScaling: String = self.dicomRT.dataset.string(forTag: "DoseGridScaling") else {
            return nil
        }
        
        guard let dgs = Float64(doseGridScaling) else {
            return nil
        }
        
        if pixelRepresentation == .Signed && bitsAllocated == 16 {
            guard let udi16 = unscaledDoseI16 else {
                return nil
            }
            return dgs * Float64(udi16)
            
        } else if pixelRepresentation == .Signed && bitsAllocated == 32 {
            guard let udi32 = unscaledDoseI32 else {
                return nil
            }
            return dgs * Float64(udi32)
            
        } else if pixelRepresentation == .Unsigned && bitsAllocated == 16 {
            guard let udu16 = unscaledDoseU16 else {
                return nil
            }
            return dgs * Float64(udu16)
            
        } else if pixelRepresentation == .Unsigned && bitsAllocated == 32 {
            guard let udu32 = unscaledDoseU32 else {
                return nil
            }
            return dgs * Float64(udu32)
        }
        
        return nil
    }()

    public lazy var unscaledDoseU32: UInt32? = {
        return self.unscaledDose as! UInt32
    }()
    
    public lazy var unscaledDoseU16: UInt16? = {
        return self.unscaledDose as! UInt16
    }()
    
    public lazy var unscaledDoseI32: Int32? = {
        return self.unscaledDose as! Int32
    }()
    
    public lazy var unscaledDoseI16: Int16? = {
        return self.unscaledDose as! Int16
    }()
    
    public lazy var unscaledDose: Any? = {
        var pixelNumber = (frame - 1) * columns * rows
        pixelNumber += (row - 1) * columns + (column - 1)
        
        guard let pixelData = self.dicomRT.dataset.element(forTagName: "PixelData") else {
            return nil
        }
     
        switch self.pixelRepresentation {
        case .Signed:
            if bitsAllocated == 16 {
                return PixelDataAccess.getPixelSigned16(pixelDataElement: pixelData, pixelNumber: Int(pixelNumber), byteOrder: pixelData.byteOrder)
            } else {
                return PixelDataAccess.getPixelSigned32(pixelDataElement: pixelData, pixelNumber: Int(pixelNumber), byteOrder: pixelData.byteOrder)
            }
        case .Unsigned:
            if bitsAllocated == 16 {
                return PixelDataAccess.getPixelUnsigned16(pixelDataElement: pixelData, pixelNumber: Int(pixelNumber), byteOrder: pixelData.byteOrder)
            } else {
                return PixelDataAccess.getPixelUnsigned32(pixelDataElement: pixelData, pixelNumber: Int(pixelNumber), byteOrder: pixelData.byteOrder)
            }
        case .none:
            return nil
        }
    }()
    
    public lazy var doseImage: [Float64] = {
        let offset = Int((frame - 1) * rows * columns * bitsAllocated)
        let end = Int((frame) * rows * columns * bitsAllocated)

        guard let doseGridScaling: String = self.dicomRT.dataset.string(forTag: "DoseGridScaling") else {
            return []
        }
        
        guard let dgs = Float64(doseGridScaling) else {
            return []
        }
        
        
        guard let pixelData = self.dicomRT.dataset.element(forTagName: "PixelData") else {
            return []
        }
     
        switch self.pixelRepresentation {
        case .Signed:
            if bitsAllocated == 16 {
                var p = PixelDataAccess.getSigned16Pixels(pixelDataElement: pixelData, from: offset, at: end, byteOrder: pixelData.byteOrder)
                let a = p.compactMap{ Float64($0) }
                return a.map { $0 * dgs }
                
            } else {
                var p: [Int32] = PixelDataAccess.getSigned32Pixels(pixelDataElement: pixelData, from: offset, at: end, byteOrder: pixelData.byteOrder)
                let a = p.compactMap{ Float64($0) }
                return a.map { $0 * dgs }
                
            }
        case .Unsigned:
            if bitsAllocated == 16 {
                var p: [UInt16] = PixelDataAccess.getUnsigned16Pixels(pixelDataElement: pixelData, from: offset, at: end, byteOrder: pixelData.byteOrder)
                let a = p.compactMap{ Float64($0) }
                return a.map { $0 * dgs }
                
            } else {
                var p: [UInt32] = PixelDataAccess.getUnsigned32Pixels(pixelDataElement: pixelData, from: offset, at: end, byteOrder: pixelData.byteOrder)
                let a = p.compactMap{ Float64($0) }
                
                return a.map { $0 * dgs }
                
            }
        case .none:
            return []
        }
        
    }()
}
