//
//  DICOMSliceOrder.swift
//  DcmSwift
//
//  The plane of an image in the patient (PS3.3 C.7.6.2) and the order of
//  the slices of a series along it: the position of each slice projected on
//  the normal of its orientation (C.7.6.2.1.1). What keeps a series from
//  being a stack (orientations that differ, missing planes, positions
//  given twice, uneven spacing) is reported, not corrected.
//

import Foundation

/// The plane of an image: Image Position (Patient) and Image Orientation
/// (Patient), in millimeters, in the patient-based coordinate system
/// (PS3.3 C.7.6.2.1.1).
public struct DICOMImagePlane: Sendable, Equatable {
    /// The center of the first pixel sent, x, y, z.
    public let position: [Double]
    /// The direction cosines of the first row, then of the first column.
    public let row: [Double]
    public let column: [Double]

    /// A plane from its Values; nil unless there are three coordinates
    /// and six direction cosines, with neither cosine vector null.
    ///
    /// - Parameter position: the three Values of Image Position (Patient).
    /// - Parameter orientation: the six Values of Image Orientation (Patient).
    public init?(position: [Double], orientation: [Double]) {
        guard position.count == 3, orientation.count == 6, (position + orientation).allSatisfy(\.isFinite) else { return nil }
        let row = Array(orientation[0..<3]), column = Array(orientation[3..<6])
        guard Self.length(row) > 1e-6, Self.length(column) > 1e-6 else { return nil }
        self.position = position
        self.row = row
        self.column = column
    }

    /// The plane of the image a Data Set holds, from its top-level Image
    /// Plane Module; nil when either attribute is missing or invalid.
    ///
    /// - Parameter dataset: a single-frame image, or a multi-frame one
    ///   whose plane is the same for every frame.
    public init?(dataset: DataSet) {
        guard let position = dataset.element(forTagName: "ImagePositionPatient")?.decodedNumbers,
              let orientation = dataset.element(forTagName: "ImageOrientationPatient")?.decodedNumbers else { return nil }
        self.init(position: position, orientation: orientation)
    }

    /// The normal of the plane, row × column, of unit length.
    public var normal: [Double] {
        let n = [row[1] * column[2] - row[2] * column[1],
                 row[2] * column[0] - row[0] * column[2],
                 row[0] * column[1] - row[1] * column[0]]
        let length = Self.length(n)
        return length > 0 ? n.map { $0 / length } : n
    }

    /// The position of the plane along a direction: its position projected
    /// on it, in millimeters.
    ///
    /// - Parameter direction: a unit vector, usually the normal of the series.
    public func location(along direction: [Double]) -> Double {
        zip(position, direction).reduce(0) { $0 + $1.0 * $1.1 }
    }

    /// Whether two planes are parallel, their normals within a tolerance.
    ///
    /// - Parameter other: the plane to compare.
    /// - Parameter tolerance: the largest angle between the normals, in radians.
    public func isParallel(to other: DICOMImagePlane, tolerance: Double = 1e-3) -> Bool {
        let cosine = zip(normal, other.normal).reduce(0) { $0 + $1.0 * $1.1 }
        return abs(cosine) >= cos(tolerance)
    }

    private static func length(_ vector: [Double]) -> Double {
        vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
    }
}


/// The order of the slices of a series, and what keeps it from being a
/// regular stack.
public struct DICOMSliceOrder: Sendable, Equatable {
    /// What a slice is known by.
    public struct Slice: Sendable, Equatable {
        public let plane: DICOMImagePlane?
        public let instanceNumber: Int?
        public let sopInstanceUID: String

        /// - Parameter plane: the plane of the slice, if it has one.
        /// - Parameter instanceNumber: Instance Number (0020,0013).
        /// - Parameter sopInstanceUID: SOP Instance UID (0008,0018).
        public init(plane: DICOMImagePlane?, instanceNumber: Int?, sopInstanceUID: String) {
            self.plane = plane
            self.instanceNumber = instanceNumber
            self.sopInstanceUID = sopInstanceUID
        }
    }

    /// What the order follows.
    public enum Criterion: Sendable, Equatable {
        /// The position along the normal of the common orientation.
        case position
        /// Instance Number, the planes not allowing the position.
        case instanceNumber
        /// SOP Instance UID, neither planes nor Instance Numbers allowing better.
        case sopInstanceUID
    }

    /// What keeps the series from being a regular stack.
    public enum Issue: Sendable, Equatable {
        /// Slices without a valid plane.
        case missingPlanes(count: Int)
        /// Slices whose orientation is not parallel to the first's.
        case mixedOrientations(count: Int)
        /// Slices at the same position as another.
        case duplicatePositions(count: Int)
        /// The gaps between consecutive slices differ: the smallest and the
        /// largest, in millimeters.
        case irregularSpacing(smallest: Double, largest: Double)
        /// Slices without an Instance Number, when the order follows it.
        case missingInstanceNumbers(count: Int)
    }

    /// The slices given, by their index, in order.
    public let order: [Int]
    public let criterion: Criterion
    /// The position of each slice in `order` along the normal, when the
    /// order follows the position.
    public let locations: [Double]?
    /// The usual gap between consecutive slices, their median, when the
    /// order follows the position.
    public let spacing: Double?
    public let issues: [Issue]

    /// Orders slices: by position along the normal when every slice has a
    /// plane parallel to the first's; else by Instance Number when every
    /// slice has one; else by SOP Instance UID. Ties keep Instance Number,
    /// then SOP Instance UID, order.
    ///
    /// - Parameter slices: the slices of a series, in any order.
    /// - Parameter tolerance: the gap difference, in millimeters, from
    ///   which spacing is irregular; positions closer than it are the same.
    public init(_ slices: [Slice], tolerance: Double = 0.01) {
        var issues: [Issue] = []
        let missingPlanes = slices.filter { $0.plane == nil }.count
        if missingPlanes > 0 { issues.append(.missingPlanes(count: missingPlanes)) }
        let reference = slices.lazy.compactMap(\.plane).first
        let mixed = reference.map { reference in
            slices.filter { $0.plane.map { !$0.isParallel(to: reference) } ?? false }.count
        } ?? 0
        if mixed > 0 { issues.append(.mixedOrientations(count: mixed)) }

        let byNumberThenUID: (Int, Int) -> Bool = { a, b in
            let left = slices[a], right = slices[b]
            switch (left.instanceNumber, right.instanceNumber) {
            case let (l?, r?) where l != r: return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return Self.uidPrecedes(left.sopInstanceUID, right.sopInstanceUID)
            }
        }

        if let reference, missingPlanes == 0, mixed == 0 {
            let normal = reference.normal
            let location = slices.map { $0.plane!.location(along: normal) }
            let order = slices.indices.sorted { a, b in
                abs(location[a] - location[b]) > tolerance ? location[a] < location[b] : byNumberThenUID(a, b)
            }
            let locations = order.map { location[$0] }
            let gaps = zip(locations, locations.dropFirst()).map { $1 - $0 }
            let duplicates = gaps.filter { $0 <= tolerance }.count
            if duplicates > 0 { issues.append(.duplicatePositions(count: duplicates)) }
            let distinct = gaps.filter { $0 > tolerance }.sorted()
            let spacing = distinct.isEmpty ? nil : distinct[distinct.count / 2]
            if let smallest = distinct.first, let largest = distinct.last, largest - smallest > tolerance {
                issues.append(.irregularSpacing(smallest: smallest, largest: largest))
            }
            self.order = order
            self.criterion = .position
            self.locations = locations
            self.spacing = spacing
            self.issues = issues
            return
        }

        let missingNumbers = slices.filter { $0.instanceNumber == nil }.count
        if missingNumbers == 0 {
            criterion = .instanceNumber
            order = slices.indices.sorted(by: byNumberThenUID)
        } else {
            criterion = .sopInstanceUID
            if missingNumbers < slices.count { issues.append(.missingInstanceNumbers(count: missingNumbers)) }
            order = slices.indices.sorted { Self.uidPrecedes(slices[$0].sopInstanceUID, slices[$1].sopInstanceUID) }
        }
        locations = nil
        spacing = nil
        self.issues = issues
    }

    /// UIDs compared component by component, as numbers (PS3.5 9.1).
    static func uidPrecedes(_ a: String, _ b: String) -> Bool {
        let left = a.split(separator: "."), right = b.split(separator: ".")
        for (l, r) in zip(left, right) where l != r {
            if l.count != r.count { return l.count < r.count }
            return l < r
        }
        return left.count < right.count
    }
}
