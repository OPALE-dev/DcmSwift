//
//  DICOMVolume.swift
//  DcmSwift
//
//  The slices of a regular stack as one volume, and its sections along
//  the three axes of the stack: the slices themselves, and the two planes
//  orthogonal to them, each through a row or a column of every slice
//  (multiplanar reconstruction). A volume needs a stack (PS3.3 C.7.6.2):
//  one orientation, every slice with a plane, the same size and spacing,
//  positions apart by one regular gap along the normal. Anything else is
//  refused with its reason, not resampled.
//

import Foundation

/// The Modality values of a regular stack of slices, in the patient.
public struct DICOMVolume: Sendable {
    /// Why slices do not make a volume.
    public enum Refusal: Error, Equatable, Sendable, CustomStringConvertible {
        /// Fewer than two slices.
        case tooFewSlices(Int)
        /// The order found what keeps the slices from being a stack.
        case notAStack([DICOMSliceOrder.Issue])
        /// A slice without a plane or Pixel Spacing, by its place in the order.
        case missingGeometry(slice: Int)
        /// A slice whose size or pixel spacing differs from the first's.
        case geometryDiffers(slice: Int)
        /// The slices move sideways from one to the next (gantry tilt, or
        /// shifted positions): the angle between their step and the normal,
        /// in degrees.
        case sheared(degrees: Double)
        /// The values would take more memory than allowed, in bytes.
        case tooLarge(bytes: Int, limit: Int)
        /// A slice whose values are not one a pixel.
        case valuesDiffer(slice: Int)

        public var description: String {
            switch self {
            case .tooFewSlices(let count): "\(count) slice(s): a volume needs at least two"
            case .notAStack(let issues): "not a regular stack: " + issues.map(Self.describe).joined(separator: "; ")
            case .missingGeometry(let slice): "slice \(slice + 1) has no plane or no Pixel Spacing"
            case .geometryDiffers(let slice): "slice \(slice + 1) differs in size or pixel spacing from the first"
            case .sheared(let degrees): "slices shifted sideways, \(String(format: "%.2f", degrees))° from the normal"
            case .tooLarge(let bytes, let limit): "\(bytes >> 20) MiB of values, more than \(limit >> 20) MiB"
            case .valuesDiffer(let slice): "slice \(slice + 1) does not give one value a pixel"
            }
        }

        static func describe(_ issue: DICOMSliceOrder.Issue) -> String {
            switch issue {
            case .missingPlanes(let count): "\(count) slice(s) without a plane"
            case .mixedOrientations(let count): "\(count) slice(s) of another orientation"
            case .duplicatePositions(let count): "\(count) position(s) given twice"
            case .irregularSpacing(let smallest, let largest):
                "gaps from \(String(format: "%.3f", smallest)) to \(String(format: "%.3f", largest)) mm"
            case .missingInstanceNumbers(let count): "\(count) slice(s) without Instance Number"
            }
        }
    }

    /// The axis a section is orthogonal to.
    public enum Axis: Sendable, CaseIterable {
        /// A slice of the stack, as acquired.
        case slice
        /// Through one row of every slice: orthogonal to the columns.
        case row
        /// Through one column of every slice: orthogonal to the rows.
        case column
    }

    /// A section of the volume: its values row by row and its geometry.
    public struct Section: Sendable {
        public let width: Int
        public let height: Int
        public let values: [Float]
        public let geometry: DICOMImageGeometry
        /// Whether its rows were interpolated between slices.
        public let isInterpolated: Bool
    }

    public let columns: Int
    public let rows: Int
    /// The number of slices.
    public let depth: Int
    /// The geometry of the first slice in the order.
    public let first: DICOMImageGeometry
    /// The gap between consecutive slices along the normal, in millimeters.
    public let sliceSpacing: Double
    /// Slice by slice, row by row.
    public let values: [Float]

    /// The bytes a volume of slices of a size would take.
    public static func byteCount(columns: Int, rows: Int, depth: Int) -> Int {
        columns * rows * depth * MemoryLayout<Float>.size
    }

    /// Checks that slices make a volume, before reading their values.
    ///
    /// - Parameters:
    ///   - geometries: the slices in the order of `order`.
    ///   - order: their order, whose issues refuse the volume.
    ///   - maximumBytes: the memory the values may take.
    public static func check(_ geometries: [DICOMImageGeometry?], order: DICOMSliceOrder,
                             maximumBytes: Int = 1 << 30) throws(Refusal) -> (first: DICOMImageGeometry, spacing: Double) {
        guard geometries.count >= 2 else { throw .tooFewSlices(geometries.count) }
        guard order.issues.isEmpty, order.criterion == .position, let locations = order.locations,
              locations.count == geometries.count
        else { throw .notAStack(order.issues) }
        guard let first = geometries[0] else { throw .missingGeometry(slice: 0) }
        for (index, geometry) in geometries.enumerated() {
            guard let geometry else { throw .missingGeometry(slice: index) }
            guard geometry.columns == first.columns, geometry.rows == first.rows,
                  abs(geometry.rowSpacing - first.rowSpacing) < 1e-4, abs(geometry.columnSpacing - first.columnSpacing) < 1e-4
            else { throw .geometryDiffers(slice: index) }
        }
        let spacing = (locations[locations.count - 1] - locations[0]) / Double(locations.count - 1)
        // The step from the first slice to the last, against the normal.
        let last = geometries[geometries.count - 1]!.plane.position
        let step = zip(last, first.plane.position).map { $0 - $1 }
        let length = step.reduce(0) { $0 + $1 * $1 }.squareRoot()
        let along = zip(step, first.plane.normal).reduce(0) { $0 + $1.0 * $1.1 }
        let degrees = acos(min(1, abs(along) / max(length, 1e-12))) * 180 / .pi
        guard degrees < 0.1 else { throw .sheared(degrees: degrees) }
        let bytes = byteCount(columns: first.columns, rows: first.rows, depth: geometries.count)
        guard bytes <= maximumBytes else { throw .tooLarge(bytes: bytes, limit: maximumBytes) }
        return (first, spacing)
    }

    /// A volume from the slices of a regular stack.
    ///
    /// - Parameters:
    ///   - geometries: the slices in the order of `order`.
    ///   - order: their order.
    ///   - maximumBytes: the memory the values may take.
    ///   - values: the Modality values of a slice, by its place in the
    ///     order, one a pixel, row by row.
    public init(_ geometries: [DICOMImageGeometry?], order: DICOMSliceOrder, maximumBytes: Int = 1 << 30,
                values: (Int) throws -> [Float]) throws {
        let (first, spacing) = try Self.check(geometries, order: order, maximumBytes: maximumBytes)
        let plane = first.columns * first.rows
        var all = [Float]()
        all.reserveCapacity(plane * geometries.count)
        for index in geometries.indices {
            let slice = try values(index)
            guard slice.count == plane else { throw Refusal.valuesDiffer(slice: index) }
            all.append(contentsOf: slice)
        }
        self.init(first: first, depth: geometries.count, sliceSpacing: spacing, values: all)
    }

    /// A volume from its values, slice by slice, row by row.
    public init(first: DICOMImageGeometry, depth: Int, sliceSpacing: Double, values: [Float]) {
        precondition(values.count == first.columns * first.rows * depth)
        self.first = first
        self.columns = first.columns
        self.rows = first.rows
        self.depth = depth
        self.sliceSpacing = sliceSpacing
        self.values = values
    }

    /// The number of sections along an axis.
    public func count(along axis: Axis) -> Int {
        switch axis {
        case .slice: depth
        case .row: rows
        case .column: columns
        }
    }

    /// The value of a voxel: column, row, slice.
    public func value(column: Int, row: Int, slice: Int) -> Float {
        values[(slice * rows + row) * columns + column]
    }

    /// The geometry of a section, without its values: see `section(_:at:isotropic:)`.
    public func geometry(of axis: Axis, at index: Int, isotropic: Bool = false) -> DICOMImageGeometry {
        let plane = first.plane
        let normal = plane.normal
        func moved(_ point: [Double], _ direction: [Double], _ distance: Double) -> [Double] {
            zip(point, direction).map { $0 + $1 * distance }
        }
        switch axis {
        case .slice:
            return DICOMImageGeometry(
                plane: DICOMImagePlane(position: moved(plane.position, normal, Double(index) * sliceSpacing),
                                       orientation: plane.row + plane.column)!,
                columns: columns, rows: rows, rowSpacing: first.rowSpacing, columnSpacing: first.columnSpacing,
                frameOfReferenceUID: first.frameOfReferenceUID)!
        case .row, .column:
            let across = axis == .row ? first.columnSpacing : first.rowSpacing
            let direction = axis == .row ? plane.row : plane.column
            let height = isotropic ? Int(((Double(depth - 1) * sliceSpacing) / across + 1e-9).rounded(.down)) + 1 : depth
            // The first pixel: the row or column through the last slice.
            let offset = axis == .row ? Double(index) * first.rowSpacing : Double(index) * first.columnSpacing
            let sideways = axis == .row ? plane.column : plane.row
            let position = moved(moved(plane.position, sideways, offset), normal, Double(depth - 1) * sliceSpacing)
            return DICOMImageGeometry(
                plane: DICOMImagePlane(position: position, orientation: direction + normal.map { -$0 })!,
                columns: axis == .row ? columns : rows, rows: height, rowSpacing: isotropic ? across : sliceSpacing,
                columnSpacing: across, frameOfReferenceUID: first.frameOfReferenceUID)!
        }
    }

    /// A section of the volume. The sections across the slices go from the
    /// last slice down to the first, along the normal reversed: for an axial
    /// stack, the head at the top.
    ///
    /// - Parameters:
    ///   - axis: the axis the section is orthogonal to.
    ///   - index: the slice, the row or the column it goes through.
    ///   - isotropic: across the slices, rows interpolated linearly between
    ///     them, as far apart as the pixels of the section; otherwise one row
    ///     a slice, exactly as stored.
    public func section(_ axis: Axis, at index: Int, isotropic: Bool = false) -> Section {
        let geometry = geometry(of: axis, at: index, isotropic: isotropic)
        switch axis {
        case .slice:
            let start = index * rows * columns
            return Section(width: columns, height: rows, values: Array(values[start..<(start + rows * columns)]),
                           geometry: geometry, isInterpolated: false)
        case .row, .column:
            let width = geometry.columns, height = geometry.rows
            let step = geometry.rowSpacing / sliceSpacing
            var section = [Float](repeating: 0, count: width * height)
            let top = Double(depth - 1)
            var interpolated = false
            section.withUnsafeMutableBufferPointer { output in
                values.withUnsafeBufferPointer { voxels in
                    for r in 0..<height {
                        // The place of the row among the slices, from the last.
                        let place = max(0, top - Double(r) * step)
                        var lower = Int(place.rounded(.down))
                        var weight = Float(place - Double(lower))
                        if weight < 1e-6 { weight = 0 } else if weight > 1 - 1e-6 { lower += 1; weight = 0 }
                        if weight > 0 { interpolated = true }
                        let upper = min(depth - 1, lower + 1)
                        for c in 0..<width {
                            let (column, row) = axis == .row ? (c, index) : (index, c)
                            let a = voxels[(lower * rows + row) * columns + column]
                            output[r * width + c] = weight > 0
                                ? a + (voxels[(upper * rows + row) * columns + column] - a) * weight : a
                        }
                    }
                }
            }
            return Section(width: width, height: height, values: section, geometry: geometry, isInterpolated: interpolated)
        }
    }

    /// The voxel of a point of the patient: column, row and slice, nearest;
    /// nil outside the volume.
    public func voxel(at point: [Double]) -> (column: Int, row: Int, slice: Int)? {
        let (pixel, distance) = first.pixelPosition(of: point)
        let slice = (distance / sliceSpacing).rounded()
        let column = pixel.column.rounded(), row = pixel.row.rounded()
        guard column >= 0, row >= 0, slice >= 0, column < Double(columns), row < Double(rows), slice < Double(depth)
        else { return nil }
        return (Int(column), Int(row), Int(slice))
    }
}
