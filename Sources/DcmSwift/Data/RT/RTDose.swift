//
//  File.swift
//  
//
//  Created by Paul on 07/07/2021.
//

import Foundation

/*
 Helper functions
 TODO why not extension ?
 */
public class RTDose : DicomFile {
    
    public func getDose(column: UInt, row: UInt, frame: UInt) {
        
    }
    
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
        
        // if pixelRepresentation == 0: unsigned, == 1: signed
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
    
    public func getUnscaledDose(column: Int16, row: Int16, frame: Int16) -> Float64? {
        guard let imageParams = getImageParameters() else {
            Logger.warning("Can't get image parameters")
            return nil
        }
        
        let (frames, rows, columns, bitsAllocated, pixelRepresentation) = imageParams
        
        if frame > frames || column > columns || row > rows {
            Logger.warning("frame > frames, or column > columns, or row > rows")
            return nil
        }
    
        var pixelNumber = frame * columns * rows
        pixelNumber += row * columns + column
        
        if bitsAllocated == 16 {
            if let pixelData = self.dataset.element(forTagName: "PixelData") {
                //
            }
        } else if bitsAllocated == 32 {
            //
        } else {
            Logger.warning("16 or 32 bits, got \(bitsAllocated)")
        }
     
        return nil
    }
    
    public func getDoseImage() {
        // TODO
    }
    
    public func getDoseImages() {
        // TODO
    }
    
    public func getDoseImageWidth() -> Int16? {
        if let columns = self.dataset.value(forTag: "Columns") {
            return columns as! Int16
        } else {
            Logger.debug("No column data element")
            return nil
        }
    }
    
    public func getDoseImageHeight() -> Int16? {
        if let rows = self.dataset.value(forTag: "Rows") {
            return rows as! Int16
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
