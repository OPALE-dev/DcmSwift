//
//  DicomRT.swift
//  
//
//  Created by Paul on 09/07/2021.
//

import Foundation

/**
 For Dicom RT (Radiation Therapy) files
 */
public class DicomRT : DicomFile {
    
    public var frames: Int16
    public var rows: Int16
    public var columns: Int16
    public var bitsAllocated: Int16
    public var bitsStored:Int16
    public var highBit: Int16
    public var pixelRepresentation: DicomImage.PixelRepresentation
    
    public override init?(forPath filepath: String) {
        // can't call super init without initiating the properties first
        // TODO refactor?
        frames = 0
        rows = 0
        columns = 0
        bitsAllocated = 0
        bitsStored = 0
        highBit = 0
        pixelRepresentation = DicomImage.PixelRepresentation.Signed
        
        super.init(forPath: filepath)
        
        guard let numberOfFrames = self.dataset.string(forTag: "NumberOfFrames"),// String, cast to Int16 later
        let rows = self.dataset.integer16(forTag: "Rows"),// Int16
        let columns = self.dataset.integer16(forTag: "Columns"),// Int16
        let bitsAllocated = self.dataset.integer16(forTag: "BitsAllocated"),// Int16
        let bitsStored = self.dataset.integer16(forTag: "BitsStored"),// Int16
        let highBit = self.dataset.integer16(forTag: "HighBit"),// Int16
        let pixelRepresentation = self.dataset.integer16(forTag: "PixelRepresentation") else {// Int16
            
            return nil
        }

        guard let frames = Int16(numberOfFrames) else {
            return nil
        }
        
        self.frames = frames
        self.rows = rows
        self.columns = columns
        self.bitsAllocated = bitsAllocated
        self.bitsStored = bitsStored
        self.highBit = highBit
    
        if self.frames < 0 {
            return nil
        }
        
        if bitsStored != bitsAllocated && (bitsStored != 16 && bitsStored != 32) && (bitsAllocated != 16 && bitsAllocated != 32) {
            return nil
        }
        
        if highBit != bitsStored - 1 {
            return nil
        }
        
        guard let pr = DicomImage.PixelRepresentation.init(rawValue: Int(pixelRepresentation)) else {
            return nil
        }
        self.pixelRepresentation = pr
    }
}
