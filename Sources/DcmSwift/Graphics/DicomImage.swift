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
#elseif os(iOS)
import UIKit
#endif


/**
 DicomImage provides image features for a DICOM Data Set.

 Native Pixel Data is rendered on every platform by `DICOMImageRenderer`
 (Modality LUT, VOI LUT or window, MONOCHROME1 polarity, RGB, YBR, and
 Palette Color). Encapsulated Pixel Data has no portable codec yet; on Apple
 platforms its frames are handed to the system image decoders.
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
    /// Encapsulated frames for the Apple system decoders.
    private var encapsulatedFrames: [Data] = []

    /// The portable renderer for native Pixel Data, when the Image Pixel
    /// attributes are valid.
    public private(set) var renderer: DICOMImageRenderer?
    /// Why `renderer` is nil, when it is.
    public private(set) var rendererError: Error?

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


    // MARK: - Initialization

    public init?(_ dataset: DataSet) {
        self.dataset = dataset

        let photometric = dataset.string(forTag: "PhotometricInterpretation") ?? ""
        let interpretations: [String: PhotometricInterpretation] = [
            "MONOCHROME1": .MONOCHROME1, "MONOCHROME2": .MONOCHROME2, "PALETTE COLOR": .PALETTE_COLOR,
            "RGB": .RGB, "HSV": .HSV, "ARGB": .ARGB, "CMYK": .CMYK, "YBR_FULL": .YBR_FULL,
            "YBR_FULL_422": .YBR_FULL_422, "YBR_PARTIAL_422": .YBR_PARTIAL_422,
            "YBR_PARTIAL_420": .YBR_PARTIAL_420, "YBR_ICT": .YBR_ICT, "YBR_RCT": .YBR_RCT
        ]
        if let interpretation = interpretations[photometric] {
            photoInter = interpretation
        }
        isMonochrome = photoInter == .MONOCHROME1 || photoInter == .MONOCHROME2

        rows = dataset.unsignedInteger16(forTag: "Rows").map(Int.init) ?? 0
        columns = dataset.unsignedInteger16(forTag: "Columns").map(Int.init) ?? 0
        bitsAllocated = dataset.unsignedInteger16(forTag: "BitsAllocated").map(Int.init) ?? 0
        bitsStored = dataset.unsignedInteger16(forTag: "BitsStored").map(Int.init) ?? 0
        samplesPerPixel = dataset.unsignedInteger16(forTag: "SamplesPerPixel").map(Int.init) ?? 0
        if dataset.unsignedInteger16(forTag: "PixelRepresentation") == 1 {
            pixelRepresentation = .Signed
        }
        if dataset.hasElement(forTagName: "PixelData") {
            numberOfFrames = 1
        }
        if let frames = dataset.string(forTag: "NumberOfFrames").flatMap({ Int($0) }) {
            isMultiframe = true
            numberOfFrames = frames
        }

        do {
            let renderer = try DICOMImageRenderer(dataset: dataset)
            self.renderer = renderer
            numberOfFrames = renderer.description.numberOfFrames
            if let window = try? renderer.windows().first {
                windowCenter = Int(window.center.rounded())
                windowWidth = Int(window.width.rounded())
            }
            if let rescale = try? renderer.rescale() {
                rescaleSlope = Int(rescale.slope.rounded())
                rescaleIntercept = Int(rescale.intercept.rounded())
            }
        } catch {
            rendererError = error
            loadEncapsulatedFrames()
        }
    }


    // MARK: - Portable rendering

    /// Renders a frame to an 8-bit gray or RGB image on any platform.
    public func renderedImage(
        forFrame frame: Int = 0,
        options: DICOMRenderingOptions = DICOMRenderingOptions()
    ) throws -> DICOMRenderedImage {
        guard let renderer else {
            throw rendererError ?? DICOMPixelDataError.missingPixelData
        }
        return try renderer.render(frame: frame, options: options)
    }

    /// PNG encoding of a rendered frame.
    public func pngData(
        forFrame frame: Int = 0,
        options: DICOMRenderingOptions = DICOMRenderingOptions()
    ) throws -> Data {
        if renderer == nil, let data = systemDecodedPNG(forFrame: frame) {
            return data
        }
        return try renderedImage(forFrame: frame, options: options).pngData()
    }

    /// Baseline JPEG encoding of a rendered frame on every platform.
    public func jpegData(
        forFrame frame: Int = 0, quality: Int = 90,
        options: DICOMRenderingOptions = DICOMRenderingOptions()
    ) throws -> Data {
        try renderedImage(forFrame: frame, options: options).jpegData(quality: quality)
    }

    /// Uncompressed baseline TIFF encoding of a rendered frame.
    public func tiffData(
        forFrame frame: Int = 0,
        options: DICOMRenderingOptions = DICOMRenderingOptions()
    ) throws -> Data {
        try renderedImage(forFrame: frame, options: options).tiffData()
    }

    /// Lossless PGM or PPM encoding of a rendered frame.
    public func pnmData(
        forFrame frame: Int = 0,
        options: DICOMRenderingOptions = DICOMRenderingOptions()
    ) throws -> Data {
        try renderedImage(forFrame: frame, options: options).pnmData()
    }


    // MARK: - CoreGraphics

#if canImport(CoreGraphics)

    /// A CoreGraphics image of a rendered native frame.
    public func cgImage(
        forFrame frame: Int = 0,
        options: DICOMRenderingOptions = DICOMRenderingOptions()
    ) -> CGImage? {
        guard let rendered = try? renderedImage(forFrame: frame, options: options),
              let provider = CGDataProvider(data: Data(rendered.pixels) as CFData) else {
            return nil
        }
        let gray = rendered.format == .gray8
        return CGImage(
            width: rendered.width,
            height: rendered.height,
            bitsPerComponent: 8,
            bitsPerPixel: 8 * rendered.format.bytesPerPixel,
            bytesPerRow: rendered.width * rendered.format.bytesPerPixel,
            space: gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

#endif


    // MARK: - macOS image

#if os(macOS)

    /// An `NSImage` of a frame: rendered from native Pixel Data, or decoded
    /// by AppKit from an encapsulated frame.
    public func image(forFrame frame: Int = 0) -> NSImage? {
        if renderer != nil {
            guard let cgImage = cgImage(forFrame: frame) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        guard encapsulatedFrames.indices.contains(frame) else { return nil }
        return NSImage(data: encapsulatedFrames[frame])
    }

#endif


    // MARK: - iOS image

#if os(iOS)

    /// A `UIImage` of a frame: rendered from native Pixel Data, or decoded by
    /// UIKit from an encapsulated frame.
    public func image(forFrame frame: Int = 0) -> UIImage? {
        if renderer != nil {
            return cgImage(forFrame: frame).map { UIImage(cgImage: $0) }
        }
        guard encapsulatedFrames.indices.contains(frame) else { return nil }
        return UIImage(data: encapsulatedFrames[frame])
    }

#endif


    /// PNG of an encapsulated frame decoded by the platform, when available.
    private func systemDecodedPNG(forFrame frame: Int) -> Data? {
#if os(macOS)
        guard let tiff = image(forFrame: frame)?.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
#elseif os(iOS)
        return image(forFrame: frame)?.pngData()
#else
        return nil
#endif
    }


    // MARK: - PNG export

    /**
     Writes every frame to `<baseName>_<frame>.png` in `path`.

     If `baseName` is nil, a UID is generated. Frames that cannot be
     rendered are skipped and logged.
     */
    public func toPNG(path: String, baseName: String?) {
        exportFrames(path: path, baseName: baseName, extension: "png") { try pngData(forFrame: $0) }
    }

    /// Writes every rendered frame as a quality-controlled baseline JPEG.
    public func toJPEG(path: String, baseName: String?, quality: Int = 90) {
        exportFrames(path: path, baseName: baseName, extension: "jpg") {
            try jpegData(forFrame: $0, quality: quality)
        }
    }

    /// Writes every rendered frame as an uncompressed baseline TIFF.
    public func toTIFF(path: String, baseName: String?) {
        exportFrames(path: path, baseName: baseName, extension: "tiff") { try tiffData(forFrame: $0) }
    }

    /// Writes every rendered frame as lossless PGM (grayscale) or PPM (RGB).
    public func toPNM(path: String, baseName: String?) {
        exportFrames(path: path, baseName: baseName) { frame in
            let image = try renderedImage(forFrame: frame)
            return (image.pnmData(), image.format == .gray8 ? "pgm" : "ppm")
        }
    }

    private func exportFrames(
        path: String, baseName: String?, extension fileExtension: String,
        encode: (Int) throws -> Data
    ) {
        exportFrames(path: path, baseName: baseName) { frame in
            (try encode(frame), fileExtension)
        }
    }

    private func exportFrames(
        path: String, baseName: String?,
        encode: (Int) throws -> (Data, String)
    ) {
        let baseFilename = (baseName ?? UID.generate()) + "_"
        for frame in 0..<numberOfFrames {
            do {
                let (data, actualExtension) = try encode(frame)
                let url = URL(fileURLWithPath: path)
                    .appendingPathComponent(baseFilename + String(frame) + "." + actualExtension)
                try data.write(to: url)
            } catch {
                Logger.error("Cannot export frame \(frame): \(error)")
            }
        }
    }


    // MARK: - Encapsulated Pixel Data

    private func loadEncapsulatedFrames() {
        guard let sequence = dataset.element(forTagName: "PixelData") as? DataSequence else { return }
        // The first Item is the Basic Offset Table. Frames spanning several
        // fragments are not reassembled until a codec layer exists.
        encapsulatedFrames = sequence.items.dropFirst().compactMap { $0.data }
    }
}
