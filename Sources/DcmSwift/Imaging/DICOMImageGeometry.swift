//
//  DICOMImageGeometry.swift
//  DcmSwift
//
//  Where the pixels of an image lie in the patient (PS3.3 C.7.6.2.1.1):
//  the plane of the image, its size and the spacing of its pixels give the
//  position of each pixel in millimeters, and back; two images of the same
//  Frame of Reference (C.7.4.1) cross along a line, the reference line of
//  one drawn on the other. The letters of the patient axes name the
//  directions of the edges of an image (C.7.6.1.1.1).
//

import Foundation

/// The plane of an image with its size and the spacing of its pixels.
public struct DICOMImageGeometry: Sendable, Equatable {
    /// A pixel position, column and row, from the center of the first
    /// pixel sent; fractional between centers.
    public struct Point: Sendable, Equatable {
        public let column: Double
        public let row: Double

        public init(column: Double, row: Double) {
            self.column = column
            self.row = row
        }
    }

    public let plane: DICOMImagePlane
    public let columns: Int
    public let rows: Int
    /// The distance between the centers of adjacent rows, in millimeters.
    public let rowSpacing: Double
    /// The distance between the centers of adjacent columns, in millimeters.
    public let columnSpacing: Double
    /// Frame of Reference UID (0020,0052): images share a coordinate
    /// system only when they share it.
    public let frameOfReferenceUID: String?

    /// A geometry; nil unless the size and the spacings are positive.
    public init?(plane: DICOMImagePlane, columns: Int, rows: Int, rowSpacing: Double, columnSpacing: Double,
                 frameOfReferenceUID: String? = nil) {
        guard columns > 0, rows > 0, rowSpacing.isFinite, columnSpacing.isFinite, rowSpacing > 0, columnSpacing > 0
        else { return nil }
        self.plane = plane
        self.columns = columns
        self.rows = rows
        self.rowSpacing = rowSpacing
        self.columnSpacing = columnSpacing
        self.frameOfReferenceUID = frameOfReferenceUID
    }

    /// The geometry of a frame: Plane Position, Plane Orientation and Pixel
    /// Measures of its functional groups, per frame then shared, else the
    /// top-level Image Plane Module. Nil when the plane or Pixel Spacing
    /// is missing or invalid.
    public init?(dataset: DataSet, frame: Int = 0) {
        let scope = DICOMAttributeScope(dataset: dataset)
        let perFrame = scope.items("PerFrameFunctionalGroupsSequence")
        let frameItem = perFrame.indices.contains(frame) ? DICOMAttributeScope(item: perFrame[frame]) : nil
        let shared = scope.items("SharedFunctionalGroupsSequence").first.map { DICOMAttributeScope(item: $0) }
        /// A value in a functional group macro, this frame's first, else shared.
        func grouped(_ macro: String, _ keyword: String) -> [Double]? {
            for group in [frameItem, shared].compactMap({ $0 }) {
                if let item = group.items(macro).first, let values = DICOMAttributeScope(item: item).doubles(keyword) {
                    return values
                }
            }
            return nil
        }
        guard let position = grouped("PlanePositionSequence", "ImagePositionPatient") ?? scope.doubles("ImagePositionPatient"),
              let orientation = grouped("PlaneOrientationSequence", "ImageOrientationPatient") ?? scope.doubles("ImageOrientationPatient"),
              let plane = DICOMImagePlane(position: position, orientation: orientation),
              let spacing = grouped("PixelMeasuresSequence", "PixelSpacing") ?? scope.doubles("PixelSpacing"), spacing.count == 2,
              let rows = scope.integer("Rows"), let columns = scope.integer("Columns")
        else { return nil }
        let frameOfReference = scope.strings("FrameOfReferenceUID").first.flatMap { $0.isEmpty ? nil : $0 }
        self.init(plane: plane, columns: columns, rows: rows, rowSpacing: spacing[0], columnSpacing: spacing[1],
                  frameOfReferenceUID: frameOfReference)
    }

    // MARK: - Pixels and the patient

    /// The position in the patient of a pixel position, in millimeters:
    /// P = S + X Δi i + Y Δj j (PS3.3 equation C.7.6.2.1-1), i the column
    /// and j the row.
    public func patientPosition(of point: Point) -> [Double] {
        (0..<3).map { axis in
            plane.position[axis] + plane.row[axis] * columnSpacing * point.column
                + plane.column[axis] * rowSpacing * point.row
        }
    }

    /// The pixel position of a point of the patient projected on the
    /// image, and its signed distance from the plane along the normal, in
    /// millimeters.
    public func pixelPosition(of point: [Double]) -> (point: Point, distance: Double) {
        let offset = zip(point, plane.position).map { $0 - $1 }
        // Solve offset ≈ a X + b Y in the plane, X and Y not assumed orthogonal.
        let x = plane.row.map { $0 * columnSpacing }, y = plane.column.map { $0 * rowSpacing }
        let xx = Self.dot(x, x), yy = Self.dot(y, y), xy = Self.dot(x, y)
        let ox = Self.dot(offset, x), oy = Self.dot(offset, y)
        let determinant = xx * yy - xy * xy
        let a = determinant != 0 ? (ox * yy - oy * xy) / determinant : 0
        let b = determinant != 0 ? (oy * xx - ox * xy) / determinant : 0
        return (Point(column: a, row: b), Self.dot(offset, plane.normal))
    }

    /// Whether a pixel position lies on the image, up to the outer edges of
    /// its outer pixels.
    public func contains(_ point: Point) -> Bool {
        point.column >= -0.5 && point.column <= Double(columns) - 0.5
            && point.row >= -0.5 && point.row <= Double(rows) - 0.5
    }

    // MARK: - Reference lines

    /// Where another image crosses this one: the segment, in the pixel
    /// positions of this image, common to both images and to the line where
    /// their planes meet. Nil when they are parallel, when they do not
    /// overlap, or when both give a Frame of Reference and they differ.
    ///
    /// - Parameter other: the image whose reference line is drawn on this one.
    /// - Parameter tolerance: the smallest angle between the planes, in radians.
    public func referenceLine(of other: DICOMImageGeometry, tolerance: Double = 1e-3) -> (start: Point, end: Point)? {
        if let mine = frameOfReferenceUID, let theirs = other.frameOfReferenceUID, mine != theirs { return nil }
        guard !plane.isParallel(to: other.plane, tolerance: tolerance) else { return nil }
        let n1 = plane.normal, n2 = other.plane.normal
        let h1 = Self.dot(n1, plane.position), h2 = Self.dot(n2, other.plane.position)
        let direction = Self.cross(n1, n2)
        let cosine = Self.dot(n1, n2)
        let denominator = 1 - cosine * cosine
        // The point of the line nearest the origin, both normals of unit length.
        let c1 = (h1 - h2 * cosine) / denominator, c2 = (h2 - h1 * cosine) / denominator
        let origin = (0..<3).map { c1 * n1[$0] + c2 * n2[$0] }
        let length = Self.dot(direction, direction).squareRoot()
        let unit = direction.map { $0 / length }

        // Along the line, each image allows an interval of t.
        var lower = -Double.infinity, upper = Double.infinity
        for image in [self, other] {
            let start = image.pixelPosition(of: origin).point
            let step = image.pixelPosition(of: zip(origin, unit).map { $0 + $1 }).point
            let ends = [(start.column, step.column - start.column, Double(image.columns)),
                        (start.row, step.row - start.row, Double(image.rows))]
            for (value, slope, count) in ends {
                let (low, high) = (-0.5, count - 0.5)
                if abs(slope) < 1e-12 {
                    if value < low || value > high { return nil }
                    continue
                }
                let a = (low - value) / slope, b = (high - value) / slope
                lower = max(lower, min(a, b))
                upper = min(upper, max(a, b))
            }
        }
        guard lower < upper else { return nil }
        let point = { (t: Double) in self.pixelPosition(of: zip(origin, unit).map { $0 + t * $1 }).point }
        return (point(lower), point(upper))
    }

    // MARK: - Orientation

    /// The edges of the image named by the patient directions they point
    /// to (PS3.3 C.7.6.1.1.1): toward the last row, the first row, the
    /// first column and the last column.
    public var edgeLabels: (top: String, bottom: String, left: String, right: String) {
        (Self.label(plane.column.map { -$0 }), Self.label(plane.column),
         Self.label(plane.row.map { -$0 }), Self.label(plane.row))
    }

    /// The patient directions of a vector, the largest component first:
    /// L or R for x, P or A for y, H or F for z (LPS: x toward the left,
    /// y toward the posterior, z toward the head). Components below the
    /// threshold, in a vector of unit length, are left out.
    public static func label(_ vector: [Double], threshold: Double = 0.25) -> String {
        let length = dot(vector, vector).squareRoot()
        guard length > 0 else { return "" }
        let letters = [("L", "R"), ("P", "A"), ("H", "F")]
        return (0..<3)
            .map { (axis: $0, value: vector[$0] / length) }
            .filter { abs($0.value) >= threshold }
            .sorted { abs($0.value) > abs($1.value) }
            .map { $0.value > 0 ? letters[$0.axis].0 : letters[$0.axis].1 }
            .joined()
    }

    private static func dot(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }

    private static func cross(_ a: [Double], _ b: [Double]) -> [Double] {
        [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
    }
}
