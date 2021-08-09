//
//  DicomRT.swift
//  
//
//  Created by Paul on 09/07/2021.
//

import Foundation

/**
 Class for manipulating Dicom RT (Radiation Therapy) files
 
 ```
 if let dicomRT = DicomRT.init(forPath: "/path/to/rt_file.dicom") {
    if Dose.isValid(dicomRT: dicomRT) {
    let height = Dose.getDoseImageHeight(dicomRT: dicomRT)
        print("\(height)")
    }
 
    let unscaledDose = Dose.unscaledDose(dicomRT: dicomRT, row: 5, column: 4, frame: 2)
     
    if let udose = unscaledDose {
        // udose as! UInt32
    }
 }
 ```
 */
public class DicomRT : DicomFile {
    
    public var frames:Int16         = 0
    public var rows:Int16           = 0
    public var columns:Int16        = 0
    public var bitsAllocated:Int16  = 0
    public var bitsStored:Int16     = 0
    public var highBit:Int16        = 0
    public var pixelRepresentation: DicomImage.PixelRepresentation = DicomImage.PixelRepresentation.Signed
    
    /**
     Creates a DICOM RT object
     
     - Todo:
        - give an URL/Path object instead of a string ? more robust
     
     Please refer to dicomiseasy website : https://dicomiseasy.blogspot.com/2012/08/chapter-12-pixel-data.html
     
     Creates a DICOM RT instance if :
      - frames is positive ( > 0)
      - bits stored and bits allocated are either equal to 16 or 32
      - bits stored must be equal to bits allocated (??? check that)
      - highBit must be equal to bitsStored - 1
      - pixel representation must be either 0 or 1
     
     - Parameters:
        - filepath: the path of the DICOM RT file
     - Returns: a DICOM RT object or nil
     */
    public override init?(forPath filepath: String) {
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
        
        // bits stored must be equal to bits allocated; that was like that in dcmtk implementation
        // what's the point then of having 2 values which are the same ?
        if bitsStored != bitsAllocated || (bitsStored != 16 && bitsStored != 32) || (bitsAllocated != 16 && bitsAllocated != 32) {
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
