//
//  DicomImage.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 30/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif



extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation = tiffRepresentation, let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmapImage.representation(using: .png, properties: [:])
    }
    func pngWrite(to url: URL, options: Data.WritingOptions = .atomic) -> Bool {
        do {
            try pngData?.write(to: url, options: options)
            return true
        } catch {
            print(error.localizedDescription)
            return false
        }
    }
}


@discardableResult func writeCGImage(_ image: CGImage, to destinationURL: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, kUTTypePNG, 1, nil) else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}




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
    
    
    
    
    private var dataset:DataSet!
    private var pixelDataElement:DataElement!
    
    public var rows         = 0
    public var columns      = 0
    public var photoInter   = PhotometricInterpretation.RGB
    
    
    
    
    
    init(_ dataset:DataSet, withPixelDataElement element:DataElement) {
        self.dataset            = dataset
        self.pixelDataElement   = element
        
        
        if let pi = self.dataset.string(forTag: "PhotometricInterpretation") {
            //Swift.print("PhotometricInterpretation : \(pi)")
            
            if pi.trimmingCharacters(in: CharacterSet.whitespaces) == "MONOCHROME1" {
                self.photoInter = .MONOCHROME1
            } else if pi.trimmingCharacters(in: CharacterSet.whitespaces) == "MONOCHROME2" {
                self.photoInter = .MONOCHROME2
            } else if pi.trimmingCharacters(in: CharacterSet.whitespaces) == "RGB" {
                self.photoInter = .RGB
            }
        }
    }
    
    
    
    
    public func cgImage() -> CGImage? {
        var planes                  = 0
        var bitsPerPixelComponent   = 0
        
        self.rows       = Int(self.dataset.integer16(forTag: "Rows"))
        self.columns    = Int(self.dataset.integer16(forTag: "Columns"))
        let bpp         = Int(self.dataset.integer16(forTag: "BitsAllocated"))
        
        //Swift.print("self.photoInter : \(self.photoInter)")
        
        if self.photoInter == .MONOCHROME1 || self.photoInter == .MONOCHROME2 {
            planes = 1
            bitsPerPixelComponent = 16
        } else {
            planes = 3
            bitsPerPixelComponent = 8
        }
        
        let bytesPerRow = self.rows * (bitsPerPixelComponent/8) * planes
        
//        if (_planes == 1)
//        {
//            dcmImage->getMinMaxValues(_monochromeMinValue, _monochromeMaxValue, 0);
//            dcmImage->getMinMaxValues(_monochromeMinPossibleValue, _monochromeMaxPossibleValue, 1);
//        }
//        else
//        {
//            _monochromeMinValue = (double)0;
//            _monochromeMaxValue = (double)255;
//            _monochromeMinPossibleValue = (double)0;
//            _monochromeMaxPossibleValue = (double)255;
//        }
        
        Swift.print("planes : \(planes)")
        Swift.print("bitsPerPixelComponent : \(bitsPerPixelComponent)")
        Swift.print("bytesPerRow : \(bytesPerRow)")
        Swift.print("bitsPerPixel : \(bpp)")
        
        
        
        return nil
        
        //let bitmapInfo = UInt8(CGImageAlphaInfo.none.rawValue) | UInt8(CGImageByteOrderInfo.order32Little.rawValue)
        
//        let data = self.pixelDataElement.data!
//        let dataRef = CFDataCreate(nil, [UInt8](data), data.count)
//        let theDataProvider = CGDataProvider(data: dataRef!)
//
//        let bitmapInfo = (self.dataset.byteOrder == .LittleEndian) ? CGBitmapInfo(rawValue: CGBitmapInfo.RawValue(UInt16(CGBitmapInfo.byteOrder16Little.rawValue) | UInt16(CGImageAlphaInfo.none.rawValue))) : CGBitmapInfo(rawValue: CGBitmapInfo.RawValue(UInt16(CGBitmapInfo.byteOrder16Big.rawValue) | UInt16(CGImageAlphaInfo.none.rawValue)))
        
//        let iccProfileURL = URL(fileURLWithPath: "/System/Library/ColorSync/Profiles/Generic Gray Profile.icc")
//        let iccProfileData = try? Data(contentsOf: iccProfileURL)
//        let colorSpace = CGColorSpace(iccProfileData: iccProfileData! as CFData)

//        return CGImage(
//            width: Int(self.columns),
//            height: Int(self.rows),
//            bitsPerComponent: bitsPerPixelComponent,
//            bitsPerPixel: Int(bpp),
//            bytesPerRow: bytesPerRow,
//            space: CGColorSpaceCreateDeviceRGB(),
//            bitmapInfo: bitmapInfo,
//            provider: theDataProvider!,
//            decode: nil,
//            shouldInterpolate: false,
//            intent: .defaultIntent)!
    }
    
    
    
#if os(macOS)
    
    public func image() -> NSImage? {
        return NSImage(cgImage: self.cgImage()!, size: NSSize(width: self.columns, height: self.rows))
    }

#elseif os(iOS)
    
    public func image() -> UIImage? {
        return UIImage(cgImage: self.cgImage(), size: NSSize(width: self.columns, height: self.rows))
    }
    
#endif
}
