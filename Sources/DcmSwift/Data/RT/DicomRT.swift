//
//  DicomRT.swift
//  
//
//  Created by Paul on 09/07/2021.
//

import Foundation

public class DicomRT : DicomFile {

    public func getImageParameters() -> (Int16, Int16, Int16, Int16, Int16)? {
        guard let numberOfFrames = self.dataset.string(forTag: "NumberOfFrames"),// String, cast to Int16 later
        let rows = self.dataset.integer16(forTag: "Rows"),// Int16
        let columns = self.dataset.integer16(forTag: "Columns"),// Int16
        let bitsAllocated = self.dataset.integer16(forTag: "BitsAllocated"),// Int16
        let bitsStored = self.dataset.integer16(forTag: "BitsStored"),// Int16
        let highBit = self.dataset.integer16(forTag: "HighBit"),// Int16
        let pixelRepresentation = self.dataset.integer16(forTag: "PixelRepresentation") else {// Int16
            return nil
        }

        if pixelRepresentation != 0 && pixelRepresentation != 1 {
            return nil
        }
        
        guard let frameCount = Int16(numberOfFrames) else {
            return nil
        }
    
        if frameCount < 0 {
            return nil
        }
        
        if bitsStored != bitsAllocated {
            return nil
        }
        
        if highBit != bitsStored - 1 {
            return nil
        }
        
        return (frameCount, rows, columns, bitsAllocated, pixelRepresentation)
    }
    
    
    public func getDoseImage() {
        // TODO
    }
    
    public func getDoseImages() {
        // TODO
    }
    
    public func getDoseImageWidth() -> Int16? {
        if let columns = self.dataset.value(forTag: "Columns") {
            return columns as? Int16
        } else {
            Logger.debug("No column data element")
            return nil
        }
    }
    
    public func getDoseImageHeight() -> Int16? {
        if let rows = self.dataset.value(forTag: "Rows") {
            return rows as? Int16
        } else {
            Logger.debug("No row data element")
            return nil
        }
    }
    
    public func isValid() -> Bool {
        guard let imageParams = getImageParameters() else {
            return false
        }
        
        let (_, _, _, bitsAllocated, _) = imageParams
        
        return bitsAllocated == 16 || bitsAllocated == 32
    }
}
