//
//  Image.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 10/06/2021.
//  Copyright © 2021 OPALE. All rights reserved.
//

import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

#if os(macOS)
public extension NSImage {
    var jpegData: Data? {
        guard let tiffRepresentation = tiffRepresentation, let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmapImage.representation(using: .jpeg2000, properties: [:])
    }
    
    func jpegWrite(to url: URL, options: Data.WritingOptions = .atomic) -> Bool {
        do {
            try jpegData?.write(to: url, options: options)
            return true
        } catch {
            print(error.localizedDescription)
            return false
        }
    }
    
    func writeToFile(file: String, atomically: Bool, usingType type: NSBitmapImageRep.FileType) -> Bool {
        let properties = [NSBitmapImageRep.PropertyKey.compressionFactor: 1.0]
        guard
            let imageData = tiffRepresentation,
            let imageRep = NSBitmapImageRep(data: imageData),
            let fileData = imageRep.representation(using: type, properties: properties) else {
                return false
        }
        
        do {
            try fileData.write(to: URL(fileURLWithPath: file))
            return true
        } catch {
            print(error.localizedDescription)
            return false
        }
    }
}
#endif


extension CGBitmapInfo {
    public static var byteOrder16Host: CGBitmapInfo {
        return CFByteOrderGetCurrent() == Int(CFByteOrderLittleEndian.rawValue) ? .byteOrder16Little : .byteOrder16Big
    }
    
    public static var byteOrder32Host: CGBitmapInfo {
        return CFByteOrderGetCurrent() == Int(CFByteOrderLittleEndian.rawValue) ? .byteOrder32Little : .byteOrder32Big
    }
}
