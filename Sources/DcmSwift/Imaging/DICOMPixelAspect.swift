//
//  DICOMPixelAspect.swift
//  DcmSwift
//
//  The shape of a pixel, for showing an image in its proportions: the
//  spacings of a calibration that applies to the whole image (PS3.3
//  10.7.1.3), else Pixel Aspect Ratio (0028,0034), the vertical size of a
//  pixel to its horizontal size (C.7.6.3.1.7), else a square. A Pixel
//  Aspect Ratio that is not two positive numbers is reported, not used.
//

import Foundation

/// The height of a pixel against its width, and where it comes from.
public struct DICOMPixelAspect: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        /// The spacings of a calibration of the whole image.
        case calibration(DICOMPixelCalibration.Source)
        /// Pixel Aspect Ratio (0028,0034).
        case pixelAspectRatio
        /// Neither: square pixels.
        case none
    }

    /// The vertical size of a pixel and its horizontal size, in any unit.
    public let vertical: Double
    public let horizontal: Double
    public let source: Source
    /// Pixel Aspect Ratio as the file gives it, when it cannot be used.
    public let invalidPixelAspectRatio: String?

    /// The height of a pixel for a width of one.
    public var ratio: Double { vertical / horizontal }
    public var isSquare: Bool { abs(ratio - 1) < 1e-9 }

    public init(vertical: Double, horizontal: Double, source: Source, invalidPixelAspectRatio: String? = nil) {
        precondition(vertical > 0 && horizontal > 0 && vertical.isFinite && horizontal.isFinite)
        self.vertical = vertical
        self.horizontal = horizontal
        self.source = source
        self.invalidPixelAspectRatio = invalidPixelAspectRatio
    }

    /// The shape of the pixels of a frame of an image.
    ///
    /// - Parameters:
    ///   - dataset: the image.
    ///   - frame: the frame, for Pixel Spacing in the per-frame functional groups.
    public init(dataset: DataSet, frame: Int = 0) {
        self.init(calibrations: DICOMPixelCalibration.all(in: dataset, frame: frame),
                  pixelAspectRatio: DICOMAttributeScope(dataset: dataset).element("PixelAspectRatio"))
    }

    /// The shape given by the calibrations of a frame and its Pixel Aspect Ratio element.
    public init(calibrations: [DICOMPixelCalibration], pixelAspectRatio element: DataElement?) {
        if let whole = calibrations.first(where: { $0.bounds == nil }) {
            self.init(vertical: whole.rowSpacing, horizontal: whole.columnSpacing, source: .calibration(whole.source))
            return
        }
        guard let element else {
            self.init(vertical: 1, horizontal: 1, source: .none)
            return
        }
        let values = element.decodedNumbers
        if values.count == 2, values.allSatisfy({ $0.isFinite && $0 > 0 }) {
            self.init(vertical: values[0], horizontal: values[1], source: .pixelAspectRatio)
        } else {
            let text = (element.value as? String) ?? values.map { String($0) }.joined(separator: "\\")
            self.init(vertical: 1, horizontal: 1, source: .none, invalidPixelAspectRatio: text)
        }
    }
}
