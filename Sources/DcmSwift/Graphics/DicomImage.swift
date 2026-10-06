//
//  DicomImage.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 30/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if os(macOS)
import AppKit

extension NSImage {
    var png: Data? {
        tiffRepresentation?.bitmap?.png
    }
}

extension NSBitmapImageRep {
    var png: Data? {
        representation(using: .png, properties: [:])
    }
}

extension Data {
    var bitmap: NSBitmapImageRep? {
        NSBitmapImageRep(data: self)
    }
}

#elseif os(iOS)
import UIKit
#endif


/**
 DicomImage is a wrapper that provides images related features for the DICOM standard.

 Please refer to dicomiseasy :
 http://dicomiseasy.blogspot.com/2012/08/chapter-12-pixel-data.html
 */
public class DicomImage {

    /// Color space of the image
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

    /// Indicates if a pixel is signed or unsigned
    public enum PixelRepresentation: Int {
        case Unsigned = 0
        case Signed = 1
    }


    // MARK: - DICOM data

    private var dataset: DataSet!
    private var frames: [Data] = []

    public var photoInter = PhotometricInterpretation.RGB
    public var pixelRepresentation = PixelRepresentation.Unsigned

    public var isMultiframe = false
    public var isMonochrome = false

    public var numberOfFrames = 0
    public var rows = 0
    public var columns = 0

    public var windowWidth = -1
    public var windowCenter = -1
    public var rescaleSlope = 1
    public var rescaleIntercept = 0

    public var samplesPerPixel = 0
    public var bitsAllocated = 0
    public var bitsStored = 0
    public var bitsPerPixel = 0
    public var bytesPerRow = 0


    // MARK: - Apple graphics

#if canImport(CoreGraphics)

    public var colorSpace = CGColorSpaceCreateDeviceRGB()

#endif


    // MARK: - Initialization

    public init?(_ dataset: DataSet) {
        self.dataset = dataset

        if let pi = self.dataset.string(forTag: "PhotometricInterpretation") {
            let value = pi.trimmingCharacters(in: CharacterSet.whitespaces)

            if value == "MONOCHROME1" {
                self.photoInter = .MONOCHROME1
                self.isMonochrome = true

            } else if value == "MONOCHROME2" {
                self.photoInter = .MONOCHROME2
                self.isMonochrome = true

            } else if value == "ARGB" {
                self.photoInter = .ARGB

            } else if value == "RGB" {
                self.photoInter = .RGB
            }
        }

        if let v = self.dataset.unsignedInteger16(forTag: "Rows") {
            self.rows = Int(v)
        }

        if let v = self.dataset.unsignedInteger16(forTag: "Columns") {
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

        if let v = self.dataset.unsignedInteger16(forTag: "BitsAllocated") {
            self.bitsAllocated = Int(v)
        }

        if let v = self.dataset.unsignedInteger16(forTag: "BitsStored") {
            self.bitsStored = Int(v)
        }

        if let v = self.dataset.unsignedInteger16(forTag: "SamplesPerPixel") {
            self.samplesPerPixel = Int(v)
        }

        if let v = self.dataset.unsignedInteger16(forTag: "PixelRepresentation") {
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
                self.isMultiframe = true
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


    // MARK: - macOS image

#if os(macOS)

    /**
     Creates an `NSImage` for a given frame.

     - Important: only available on macOS.
     */
    public func image(forFrame frame: Int = 0) -> NSImage? {
        if !frames.indices.contains(frame) {
            Logger.error("  -> No such frame (\(frame))")
            return nil
        }

        let size = NSSize(
            width: self.columns,
            height: self.rows
        )

        let data = self.frames[frame]

        if TransferSyntax.transfersSyntaxes.contains(
            self.dataset.transferSyntax.tsUID
        ) {
            if let cgImage = self.imageFromPixels(
                pixels: data.toUnsigned8Array(),
                width: self.columns,
                height: self.rows
            ) {
                return NSImage(
                    cgImage: cgImage,
                    size: size
                )
            }
        } else {
            return NSImage(data: data)
        }

        return nil
    }

#endif


    // MARK: - iOS image

#if os(iOS)

    /**
     Creates an `UIImage` for a given frame.

     - Important: only available on iOS.
     */
    public func image(forFrame frame: Int = 0) -> UIImage? {
        if !frames.indices.contains(frame) {
            Logger.error("  -> No such frame (\(frame))")
            return nil
        }

        let data = self.frames[frame]

        if TransferSyntax.transfersSyntaxes.contains(
            self.dataset.transferSyntax.tsUID
        ) {
            if let cgImage = self.imageFromPixels(
                pixels: data.toUnsigned8Array(),
                width: self.columns,
                height: self.rows
            ) {
                return UIImage(cgImage: cgImage)
            }
        } else {
            return UIImage(data: data)
        }

        return nil
    }

#endif


    // MARK: - CoreGraphics

#if canImport(CoreGraphics)

    /**
     Creates a CoreGraphics image from raw DICOM pixel data.

     This implementation is only compiled on platforms providing CoreGraphics.
     */
    private func imageFromPixels(
        pixels: UnsafeRawPointer,
        width: Int,
        height: Int
    ) -> CGImage? {

        var bitmapInfo: CGBitmapInfo = []

        if self.isMonochrome {
            self.colorSpace = CGColorSpaceCreateDeviceGray()

            if self.photoInter == .MONOCHROME1 {
                // TODO: implement MONOCHROME1 inversion if required.

            } else if self.photoInter == .MONOCHROME2 {
                // No inversion required.
            }

        } else {
            self.colorSpace = CGColorSpaceCreateDeviceRGB()

            if self.photoInter != .ARGB {
                bitmapInfo = CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.none.rawValue
                )
            }
        }

        self.bitsPerPixel =
            self.samplesPerPixel * self.bitsStored

        self.bytesPerRow =
            width *
            (self.bitsAllocated / 8) *
            self.samplesPerPixel

        let dataLength =
            height * self.bytesPerRow

        Logger.verbose("  -> width : \(width)")
        Logger.verbose("  -> height : \(height)")
        Logger.verbose("  -> bytesPerRow : \(bytesPerRow)")
        Logger.verbose("  -> bitsPerPixel : \(bitsPerPixel)")
        Logger.verbose("  -> dataLength : \(dataLength)")

        let imageData = NSData(
            bytes: pixels,
            length: dataLength
        )

        guard let providerRef = CGDataProvider(
            data: imageData
        ) else {
            Logger.error(
                "  -> FATAL: cannot allocate bitmap properly"
            )
            return nil
        }

        if let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: self.bitsAllocated,
            bitsPerPixel: self.bitsPerPixel,
            bytesPerRow: self.bytesPerRow,
            space: self.colorSpace,
            bitmapInfo: bitmapInfo,
            provider: providerRef,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) {
            return cgImage
        }

        Logger.error(
            "  -> FATAL: invalid bitmap for CGImage"
        )

        return nil
    }

#endif


    // MARK: - Presentation values

    private func processPresentationValues(
        pixels: [UInt8]
    ) -> [UInt8] {

        var output = pixels

        Logger.verbose(
            "  -> rescaleIntercept : \(self.rescaleIntercept)"
        )

        Logger.verbose(
            "  -> rescaleSlope : \(self.rescaleSlope)"
        )

        Logger.verbose(
            "  -> windowCenter : \(self.windowCenter)"
        )

        Logger.verbose(
            "  -> windowWidth : \(self.windowWidth)"
        )

        // Apply rescale values.
        if rescaleIntercept != 0 || rescaleSlope != 1 {
            output = pixels.map { byte -> UInt8 in
                let value =
                    (rescaleSlope * Int(byte)) +
                    rescaleIntercept

                return UInt8(
                    clamping: value
                )
            }
        }

        // Apply window center / width.
        if self.windowWidth != -1 &&
            self.windowCenter != -1 {

            let low =
                windowCenter -
                windowWidth / 2

            let high =
                windowCenter +
                windowWidth / 2

            Logger.verbose(
                "  -> low : \(low)"
            )

            Logger.verbose(
                "  -> high : \(high)"
            )

            for i in output.indices {
                let value = Int(output[i])

                if value < low {
                    output[i] = UInt8(
                        clamping: low
                    )

                } else if value > high {
                    output[i] = UInt8(
                        clamping: high
                    )
                }
            }
        }

        return output
    }


    // MARK: - PNG export

#if os(macOS) || os(iOS)

    /**
     Writes a DICOM image to PNG files.

     There might be multiple frames, hence the `baseName`.

     Files will be named:

         <baseName>_0.png
         <baseName>_1.png
         ...

     If `baseName` is nil, an UID is generated.

     - Parameters:
       - path: Directory where PNG files should be written.
       - baseName: Root name of the PNG file.
     */
    public func toPNG(
        path: String,
        baseName: String?
    ) {

        let baseFilename: String

        if let baseName {
            baseFilename = baseName + "_"
        } else {
            baseFilename = UID.generate() + "_"
        }

        for frame in 0..<numberOfFrames {
            guard let image = image(
                forFrame: frame
            ) else {
                continue
            }

            var url = URL(
                fileURLWithPath: path
            )

            url.appendPathComponent(
                baseFilename +
                String(frame) +
                ".png"
            )

            Logger.debug(
                url.absoluteString
            )

#if os(macOS)

            image.setName(
                url.absoluteString
            )

            if let data = image.png {
                try? data.write(
                    to: url
                )
            }

#elseif os(iOS)

            if let data = image.pngData() {
                do {
                    try data.write(
                        to: url
                    )
                } catch {
                    Logger.error(
                        "Cannot write PNG: \(error)"
                    )
                }
            }

#endif
        }
    }

#endif


    // MARK: - Pixel data

    public func loadPixelData() {

        /*
         Refuse non-native DICOM transfer syntaxes for now.

         if !DicomConstants.transfersSyntaxes.contains(
             self.dataset.transferSyntax
         ) {
             Logger.error(
                 "  -> Unsupported Transfer Syntax"
             )
             return
         }
         */

        guard let pixelDataElement =
            self.dataset.element(
                forTagName: "PixelData"
            )
        else {
            return
        }

        // Pixel Sequence multiframe
        if let sequence =
            pixelDataElement as? DataSequence {

            for item in sequence.items {
                if item.data != nil &&
                    item.length > 128 {

                    self.frames.append(
                        item.data
                    )
                }
            }

            return
        }

        // OW / OB multiframe
        if self.numberOfFrames > 1 {

            let frameSize =
                pixelDataElement.length /
                self.numberOfFrames

            let chunks =
                pixelDataElement.data
                    .toUnsigned8Array()
                    .chunked(
                        into: frameSize
                    )

            for chunk in chunks {
                self.frames.append(
                    Data(chunk)
                )
            }

            return
        }

        // Single frame
        if pixelDataElement.data != nil {
            self.frames.append(
                pixelDataElement.data
            )
        }
    }
}
