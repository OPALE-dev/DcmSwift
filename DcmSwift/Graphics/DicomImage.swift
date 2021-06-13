//
//  DicomImage.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 30/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation
import Quartz



#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif


/**
 DicomImage is a wrapper that provides images related features for the DICOM standard.
 */
public class DicomImage {
    public enum PhotometricInterpretation {
        case MONOCHROME1
        case MONOCHROME2
        case PALETTE_COLOR
        case RGB
        case HSV
        case ARGB
        case CMYK
        case YBR_FULL
        case YBR_FULL_422
        case YBR_PARTIAL_422
        case YBR_PARTIAL_420
        case YBR_ICT
        case YBR_RCT
    }
    
    
    
    public enum PixelRepresentation:Int {
        case Unsigned  = 0
        case Signed    = 1
    }
    
    
    private var dataset:DataSet!
    private var frames:[Data] = []
    
    public var photoInter           = PhotometricInterpretation.RGB
    public var pixelRepresentation  = PixelRepresentation.Unsigned
    public var colorSpace           = CGColorSpaceCreateDeviceRGB()
    
    public var isMultiframe     = false
    public var isMonochrome     = false
    
    public var numberOfFrames   = 0
    public var rows             = 0
    public var columns          = 0
    
    public var windowWidth      = -1
    public var windowCenter     = -1
    public var rescaleSlope     = 1
    public var rescaleIntercept = 0
    
    public var samplesPerPixel  = 0
    public var bitsAllocated    = 0
    public var bitsStored       = 0
    public var bitsPerPixel     = 0
    public var bytesPerRow      = 0
    
    
    
    
    init?(_ dataset:DataSet) {
        self.dataset = dataset
        
        if let pi = self.dataset.string(forTag: "PhotometricInterpretation") {
            if pi.trimmingCharacters(in: CharacterSet.whitespaces) == "MONOCHROME1" {
                self.photoInter = .MONOCHROME1
                self.isMonochrome = true
                
            } else if pi.trimmingCharacters(in: CharacterSet.whitespaces) == "MONOCHROME2" {
                self.photoInter = .MONOCHROME2
                self.isMonochrome = true
                
            } else if pi.trimmingCharacters(in: CharacterSet.whitespaces) == "ARGB" {
                self.photoInter = .ARGB
                
            } else if pi.trimmingCharacters(in: CharacterSet.whitespaces) == "RGB" {
                self.photoInter = .RGB
            }
        }
        
        if let v = self.dataset.integer16(forTag: "Rows") {
            self.rows = Int(v)
        }
        
        if let v = self.dataset.integer16(forTag: "Columns") {
            self.columns = Int(v)
        }
        
        if let v = self.dataset.string(forTag: "WindowWidth") {
            self.windowWidth = Int(v) ?? self.windowWidth
        }
        
        if let v = self.dataset.string(forTag: "WindowCenter") {
            self.windowCenter = Int(v) ?? self.windowCenter
        }
        
        if let v = self.dataset.string(forTag: "RescaleSlope") {
            self.rescaleSlope = Int(v) ?? self.rescaleSlope
        }
        
        if let v = self.dataset.string(forTag: "RescaleIntercept") {
            self.rescaleIntercept = Int(v) ?? self.rescaleIntercept
        }
        
        if let v = self.dataset.integer16(forTag: "BitsAllocated") {
            self.bitsAllocated = Int(v)
        }
        
        if let v = self.dataset.integer16(forTag: "BitsStored") {
            self.bitsStored = Int(v)
        }
        
        if let v = self.dataset.integer16(forTag: "SamplesPerPixel") {
            self.samplesPerPixel = Int(v)
        }
        
        if let v = self.dataset.integer16(forTag: "PixelRepresentation") {
            if v == 0 {
                self.pixelRepresentation = .Unsigned
            } else if v == 1 {
                self.pixelRepresentation = .Signed
            }
        }
        
        if self.dataset.hasElement(forTagName: "PixelData") {
            self.numberOfFrames = 1
        }
        
        if let nofString = self.dataset.string(forTag: "NumberOfFrames") {
            if let nof = Int(nofString) {
                self.isMultiframe   = true
                self.numberOfFrames = nof
            }
        }
        
        Logger.verbose("  -> rows : \(self.rows)")
        Logger.verbose("  -> columns : \(self.columns)")
        Logger.verbose("  -> photoInter : \(photoInter)")
        Logger.verbose("  -> isMultiframe : \(isMultiframe)")
        Logger.verbose("  -> numberOfFrames : \(numberOfFrames)")
        Logger.verbose("  -> samplesPerPixel : \(samplesPerPixel)")
        Logger.verbose("  -> bitsAllocated : \(bitsAllocated)")
        Logger.verbose("  -> bitsStored : \(bitsStored)")
        
        self.loadPixelData()
    }

    

    
    
    
#if os(macOS)
    public func image(forFrame frame: Int = 0) -> NSImage? {
        if !frames.indices.contains(frame) {
            Logger.error("  -> No such frame (\(frame))")
            return nil
        }
        
        let size = NSSize(width: self.columns, height: self.rows)
        let data = self.frames[frame]
        
        if DicomConstants.transfersSyntaxes.contains(self.dataset.transferSyntax) {
            if let cgim = self.imageFromPixels(size: size, pixels: data.toUnsigned8Array(), width: self.columns, height: self.rows) {
                return NSImage(cgImage: cgim, size: size)
            }
        }
        else {
            return NSImage(data: data)
        }
        
        return nil
    }
    
#elseif os(iOS)
    public func image(forFrame frame: Int) -> UIImage? {
        if !frames.indices.contains(frame) { return nil }

        let size = NSSize(width: self.columns, height: self.rows)
        let data = self.frames[frame]

        if let cgim = self.imageFromPixels(size: size, pixels: data.toUnsigned8Array(), width: self.columns, height: self.rows) {
            return UIImage(cgImage: cgim, size: size)
        }

        return nil
    }
#endif
    
    
    
    
    
    // MARK: - Private
    
    private func imageFromPixels(size: NSSize, pixels: UnsafeRawPointer, width: Int, height: Int) -> CGImage? {
        var bitmapInfo:CGBitmapInfo = []
        //var __:UnsafeRawPointer = pixels
        
        if self.isMonochrome {
            self.colorSpace = CGColorSpaceCreateDeviceGray()
            
            //bitmapInfo = CGBitmapInfo.byteOrder16Host
            
            if self.photoInter == .MONOCHROME1 {

            } else if self.photoInter == .MONOCHROME2 {

            }
        } else {
            if self.photoInter != .ARGB {
                bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            }
        }
        
        self.bitsPerPixel = self.samplesPerPixel * self.bitsStored
        self.bytesPerRow  = width * (self.bitsAllocated / 8) * samplesPerPixel
        let dataLength = height * bytesPerRow // ??
        
        Logger.verbose("  -> width : \(width)")
        Logger.verbose("  -> height : \(height)")
        Logger.verbose("  -> bytesPerRow : \(bytesPerRow)")
        Logger.verbose("  -> bitsPerPixel : \(bitsPerPixel)")
        Logger.verbose("  -> dataLength : \(dataLength)")
        
        let imageData = NSData(bytes: pixels, length: dataLength)
        let providerRef = CGDataProvider(data: imageData)
        
        if providerRef == nil {
            Logger.error("  -> FATAL: cannot allocate bitmap properly")
            return nil
        }
        
        if let cgim = CGImage(
            width: width,
            height: height,
            bitsPerComponent: self.bitsStored,
            bitsPerPixel: self.bitsPerPixel,
            bytesPerRow: self.bytesPerRow, // -> bytes not bits
            space: self.colorSpace,
            bitmapInfo: bitmapInfo,
            provider: providerRef!,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) {
            return cgim
        }
        
        Logger.error("  -> FATAL: invalid bitmap for CGImage")
        
        return nil
    }
    
    
    
    
    private func processPresentationValues(pixels: [UInt8]) -> [UInt8] {
        var output:[UInt8] = pixels
        
        Logger.verbose("  -> rescaleIntercept : \(self.rescaleIntercept)")
        Logger.verbose("  -> rescaleSlope : \(self.rescaleSlope)")
        Logger.verbose("  -> windowCenter : \(self.windowCenter)")
        Logger.verbose("  -> windowWidth : \(self.windowWidth)")
        
        // sanity checks
        if rescaleIntercept != 0 || rescaleSlope != 1 {
            // pixel_data.collect!{|x| (slope * x) + intercept}
            output = pixels.map { (b) -> UInt8 in
                (UInt8(rescaleSlope) * b) + UInt8(rescaleIntercept)
            }
        }
        
        if self.windowWidth != -1 && self.windowCenter != -1 {
            let low = windowCenter - windowWidth / 2
            let high = windowCenter + windowWidth / 2
            
            Logger.verbose("  -> low  : \(low)")
            Logger.verbose("  -> high : \(high)")

            for i in 0..<output.count {
                if output[i] < low {
                    output[i] = UInt8(low)
                } else if output[i] > high {
                    output[i] = UInt8(high)
                }
            }
        }
        
        return output
    }
    
    
    private func loadPixelData() {
        // refuse NON native DICOM TS for now
//        if !DicomConstants.transfersSyntaxes.contains(self.dataset.transferSyntax) {
//            Logger.error("  -> Unsuppoorted Transfer Syntax")
//            return;
//        }
        
        if let pixelDataElement = self.dataset.element(forTagName: "PixelData") {
            // Pixel Sequence multiframe
            if let seq = pixelDataElement as? DataSequence {
                for i in seq.items {
                    if i.data != nil && i.length > 128 {
                        self.frames.append(i.data)
                    }
                }
            } else {
                // OW/OB multiframe
                if self.numberOfFrames > 1 {
                    let frameSize = pixelDataElement.length / self.numberOfFrames
                    let chuncks = pixelDataElement.data.toUnsigned8Array().chunked(into: frameSize)
                    
                    for c in chuncks {
                        self.frames.append(Data(c))
                    }
                } else {
                    // solo image
                    if pixelDataElement.data != nil {
                        self.frames.append(pixelDataElement.data)
                    }
                }
            }
        }
    }
}
