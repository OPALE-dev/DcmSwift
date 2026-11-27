//
//  DICOMPixelCalibration.swift
//  DcmSwift
//
//  The physical size of a pixel and where it comes from (PS3.3 10.7.1.3):
//  Pixel Spacing, in the patient for cross-sectional images or calibrated
//  to a plane for projection images (C.7.6.2.1.1, C.8.11.4.1.1); Imager
//  Pixel Spacing, at the detector, corrected by the Estimated Radiographic
//  Magnification Factor when given (C.8.11.4.1.1); Nominal Scanned Pixel
//  Spacing for secondary capture (C.8.6.1); the regions of an ultrasound
//  image (C.8.5.5.1). An image without any is not an error: its
//  measures stay in pixels.
//

import Foundation

/// The size of a pixel in millimeters, its source, and the pixels it applies to.
public struct DICOMPixelCalibration: Sendable, Equatable {
    /// Where the size comes from.
    public enum Source: Sendable, Equatable {
        /// Pixel Spacing (0028,0030), top level or in the Pixel Measures
        /// functional group; with Pixel Spacing Calibration Type
        /// (0028,0A02) when the image gives one (GEOMETRY, FIDUCIAL).
        case pixelSpacing(calibrationType: String?)
        /// Imager Pixel Spacing (0018,1164), at the front of the detector;
        /// divided by Estimated Radiographic Magnification Factor
        /// (0018,1114) when given, to estimate the size at the isocenter.
        case imagerPixelSpacing(magnification: Double?)
        /// Nominal Scanned Pixel Spacing (0018,2010) of a scanned document or film.
        case nominalScannedPixelSpacing
        /// A region of Sequence of Ultrasound Regions (0018,6011), by its
        /// index, its Physical Delta X and Y in centimeters.
        case ultrasoundRegion(Int)
    }

    /// Pixels of a region, inclusive.
    public struct Bounds: Sendable, Equatable {
        public let minX: Int, minY: Int, maxX: Int, maxY: Int

        public init(minX: Int, minY: Int, maxX: Int, maxY: Int) {
            (self.minX, self.minY, self.maxX, self.maxY) = (minX, minY, maxX, maxY)
        }

        public func contains(x: Int, y: Int) -> Bool {
            x >= minX && x <= maxX && y >= minY && y <= maxY
        }
    }

    /// The distance between the centers of two adjacent rows, in millimeters.
    public let rowSpacing: Double
    /// The distance between the centers of two adjacent columns, in millimeters.
    public let columnSpacing: Double
    public let source: Source
    /// The pixels it applies to; nil for the whole image.
    public let bounds: Bounds?

    /// A calibration from its spacings; nil unless both are positive and finite.
    public init?(rowSpacing: Double, columnSpacing: Double, source: Source, bounds: Bounds? = nil) {
        guard rowSpacing.isFinite, columnSpacing.isFinite, rowSpacing > 0, columnSpacing > 0 else { return nil }
        self.rowSpacing = rowSpacing
        self.columnSpacing = columnSpacing
        self.source = source
        self.bounds = bounds
    }

    /// The distance between the centers of two pixels, in millimeters.
    ///
    /// - Parameters:
    ///   - dx: the difference of their columns.
    ///   - dy: the difference of their rows.
    public func length(dx: Double, dy: Double) -> Double {
        ((dx * columnSpacing) * (dx * columnSpacing) + (dy * rowSpacing) * (dy * rowSpacing)).squareRoot()
    }

    /// The area of a number of pixels, in square millimeters.
    public func area(pixels: Double) -> Double {
        pixels * rowSpacing * columnSpacing
    }

    /// Whether it applies to every pixel given.
    public func applies(to points: [(x: Int, y: Int)]) -> Bool {
        guard let bounds else { return true }
        return points.allSatisfy { bounds.contains(x: $0.x, y: $0.y) }
    }

    // MARK: - From a Data Set

    /// Every calibration an image gives, the most specific first: Pixel
    /// Spacing, Imager Pixel Spacing, Nominal Scanned Pixel Spacing, then
    /// each calibrated ultrasound region. Values that are missing, not two,
    /// or not positive are skipped.
    ///
    /// - Parameters:
    ///   - dataset: the image.
    ///   - frame: the frame, for Pixel Spacing in the per-frame functional groups.
    public static func all(in dataset: DataSet, frame: Int = 0) -> [DICOMPixelCalibration] {
        let scope = DICOMAttributeScope(dataset: dataset)
        var found: [DICOMPixelCalibration] = []

        // Pixel Measures: per frame, else shared, else the top level.
        let perFrame = scope.items("PerFrameFunctionalGroupsSequence")
        let measures = (perFrame.indices.contains(frame) ? perFrame[frame] : nil)
            .flatMap { DICOMAttributeScope(item: $0).items("PixelMeasuresSequence").first }
            ?? scope.items("SharedFunctionalGroupsSequence").first
                .flatMap { DICOMAttributeScope(item: $0).items("PixelMeasuresSequence").first }
        let spacing = measures.flatMap { DICOMAttributeScope(item: $0).doubles("PixelSpacing") } ?? scope.doubles("PixelSpacing")
        let calibrationType = scope.strings("PixelSpacingCalibrationType").first.flatMap { $0.isEmpty ? nil : $0 }
        if let calibration = pair(spacing, .pixelSpacing(calibrationType: calibrationType)) { found.append(calibration) }

        if let imager = scope.doubles("ImagerPixelSpacing"), imager.count == 2 {
            let magnification = scope.doubles("EstimatedRadiographicMagnificationFactor")?.first.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            let factor = magnification ?? 1
            if let calibration = pair(imager.map { $0 / factor }, .imagerPixelSpacing(magnification: magnification)) {
                found.append(calibration)
            }
        }

        if let calibration = pair(scope.doubles("NominalScannedPixelSpacing"), .nominalScannedPixelSpacing) {
            found.append(calibration)
        }

        // Ultrasound regions in centimeters on both axes (units 3).
        for (index, item) in scope.items("SequenceOfUltrasoundRegions").enumerated() {
            let region = DICOMAttributeScope(item: item)
            func number(_ keyword: String) -> Double? { region.element(keyword)?.decodedNumbers.first }
            guard number("PhysicalUnitsXDirection") == 3, number("PhysicalUnitsYDirection") == 3,
                  let deltaX = number("PhysicalDeltaX"), let deltaY = number("PhysicalDeltaY"),
                  let minX = number("RegionLocationMinX0"), let minY = number("RegionLocationMinY0"),
                  let maxX = number("RegionLocationMaxX1"), let maxY = number("RegionLocationMaxY1")
            else { continue }
            let bounds = Bounds(minX: Int(minX), minY: Int(minY), maxX: Int(maxX), maxY: Int(maxY))
            // Centimeters to millimeters; a delta may be signed by the direction of the axis.
            if let calibration = DICOMPixelCalibration(rowSpacing: abs(deltaY) * 10, columnSpacing: abs(deltaX) * 10,
                                                       source: .ultrasoundRegion(index), bounds: bounds) {
                found.append(calibration)
            }
        }
        return found
    }

    /// The calibration of a measure: the first of the image that applies
    /// to all its pixels; nil when none does.
    ///
    /// - Parameters:
    ///   - dataset: the image.
    ///   - points: the pixels of the measure, column and row.
    ///   - frame: the frame measured.
    public static func of(_ dataset: DataSet, points: [(x: Int, y: Int)], frame: Int = 0) -> DICOMPixelCalibration? {
        all(in: dataset, frame: frame).first { $0.applies(to: points) }
    }

    /// Pixel Spacing and its kin give the row spacing first, then the column spacing.
    private static func pair(_ values: [Double]?, _ source: Source) -> DICOMPixelCalibration? {
        guard let values, values.count == 2 else { return nil }
        return DICOMPixelCalibration(rowSpacing: values[0], columnSpacing: values[1], source: source)
    }
}
