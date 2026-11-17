//
//  Image.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 10/06/2021.
//  Copyright © 2021 OPALE. All rights reserved.
//

import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(CoreFoundation)
import CoreFoundation
#endif

#if os(macOS)
import AppKit

public extension NSImage {
    var jpegData: Data? {
        guard
            let tiffRepresentation = tiffRepresentation,
            let bitmapImage = NSBitmapImageRep(data: tiffRepresentation)
        else {
            return nil
        }

        return bitmapImage.representation(
            using: .jpeg2000,
            properties: [:]
        )
    }

    func jpegWrite(
        to url: URL,
        options: Data.WritingOptions = .atomic
    ) -> Bool {
        guard let jpegData else {
            return false
        }

        do {
            try jpegData.write(
                to: url,
                options: options
            )
            return true
        } catch {
            print(error.localizedDescription)
            return false
        }
    }

    func writeToFile(
        file: String,
        atomically: Bool,
        usingType type: NSBitmapImageRep.FileType
    ) -> Bool {
        let properties: [NSBitmapImageRep.PropertyKey: Any] = [
            .compressionFactor: 1.0
        ]

        guard
            let imageData = tiffRepresentation,
            let imageRep = NSBitmapImageRep(data: imageData),
            let fileData = imageRep.representation(
                using: type,
                properties: properties
            )
        else {
            return false
        }

        do {
            try fileData.write(
                to: URL(fileURLWithPath: file),
                options: atomically ? .atomic : []
            )
            return true
        } catch {
            print(error.localizedDescription)
            return false
        }
    }
}

#elseif os(iOS)

import UIKit

#endif


// MARK: - CoreGraphics bitmap byte order

#if canImport(CoreGraphics) && canImport(CoreFoundation)

public extension CGBitmapInfo {
    static var byteOrder16Host: CGBitmapInfo {
        CFByteOrderGetCurrent() == Int(CFByteOrderLittleEndian.rawValue)
            ? .byteOrder16Little
            : .byteOrder16Big
    }

    static var byteOrder32Host: CGBitmapInfo {
        CFByteOrderGetCurrent() == Int(CFByteOrderLittleEndian.rawValue)
            ? .byteOrder32Little
            : .byteOrder32Big
    }
}

#endif
