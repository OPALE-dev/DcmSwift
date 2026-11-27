//
//  DcmSwiftVolumeTests.swift
//  DcmSwiftTests
//
//  A regular stack as a volume and its orthogonal sections (multiplanar
//  reconstruction, PS3.3 C.7.6.2), on a synthetic volume whose voxels give
//  their own place: 10000 × slice + 100 × row + column. Every pixel of a
//  section is checked against the voxel its patient position falls in.
//

import XCTest
@testable import DcmSwift

final class DcmSwiftVolumeTests: XCTestCase {
    private let columns = 7, rows = 5

    /// An axial slice at z, 1 mm columns and 2 mm rows, from x = −3, y = −4.
    private func geometry(z: Double, orientation: [Double] = [1, 0, 0, 0, 1, 0], x: Double = -3) -> DICOMImageGeometry {
        DICOMImageGeometry(plane: DICOMImagePlane(position: [x, -4, z], orientation: orientation)!,
                           columns: columns, rows: rows, rowSpacing: 2, columnSpacing: 1, frameOfReferenceUID: "1.2.3")!
    }

    /// Slices at the positions given, in any order; the volume as ordered.
    private func volume(_ zs: [Double], maximumBytes: Int = 1 << 30,
                        geometry make: ((Int, Double) -> DICOMImageGeometry)? = nil) throws -> DICOMVolume {
        var geometries: [DICOMImageGeometry] = []
        for (index, z) in zs.enumerated() {
            geometries.append(make?(index, z) ?? geometry(z: z))
        }
        var slices: [DICOMSliceOrder.Slice] = []
        for (index, geometry) in geometries.enumerated() {
            slices.append(DICOMSliceOrder.Slice(plane: geometry.plane, instanceNumber: index + 1, sopInstanceUID: "1.\(index)"))
        }
        let order = DICOMSliceOrder(slices)
        let ordered: [DICOMImageGeometry?] = order.order.map { geometries[$0] }
        let (rows, columns) = (self.rows, self.columns)
        return try DICOMVolume(ordered, order: order, maximumBytes: maximumBytes) { (k: Int) -> [Float] in
            var values: [Float] = []
            for row in 0..<rows {
                for column in 0..<columns { values.append(Float(10000 * k + 100 * row + column)) }
            }
            return values
        }
    }

    private func expected(_ voxel: (column: Int, row: Int, slice: Int)) -> Float {
        Float(10000 * voxel.slice + 100 * voxel.row + voxel.column)
    }

    func testSectionsAlongEachAxisAreTheVoxelsTheyCross() throws {
        // Given out of order: the volume follows the position, 3 mm apart.
        let volume = try volume([6, 0, 9, 3])
        XCTAssertEqual([volume.columns, volume.rows, volume.depth], [7, 5, 4])
        XCTAssertEqual(volume.sliceSpacing, 3, accuracy: 1e-12)
        for axis in DICOMVolume.Axis.allCases {
            for index in 0..<volume.count(along: axis) {
                let section = volume.section(axis, at: index)
                XCTAssertFalse(section.isInterpolated)
                for r in 0..<section.height {
                    for c in 0..<section.width {
                        let point = section.geometry.patientPosition(of: .init(column: Double(c), row: Double(r)))
                        let voxel = try XCTUnwrap(volume.voxel(at: point), "\(axis) \(index) \(c) \(r)")
                        XCTAssertEqual(section.values[r * section.width + c], expected(voxel), "\(axis) \(index) \(c) \(r)")
                    }
                }
            }
        }
        // Across the slices, the last slice at the top: the head up for an axial stack.
        let coronal = volume.section(.row, at: 2)
        XCTAssertEqual([coronal.width, coronal.height], [7, 4])
        XCTAssertEqual(coronal.values[0], 30200)
        XCTAssertEqual(coronal.geometry.plane.position, [-3, 0, 9])
        XCTAssertEqual(coronal.geometry.rowSpacing, 3)
        XCTAssertEqual(coronal.geometry.edgeLabels.top, "H")
        let sagittal = volume.section(.column, at: 4)
        XCTAssertEqual([sagittal.width, sagittal.height], [5, 4])
        XCTAssertEqual(sagittal.values[sagittal.width * 3 + 1], 104)
        XCTAssertEqual(sagittal.geometry.plane.position, [1, -4, 9])
        XCTAssertEqual([sagittal.geometry.edgeLabels.left, sagittal.geometry.edgeLabels.right], ["A", "P"])
    }

    func testIsotropicSectionsInterpolateBetweenSlices() throws {
        let volume = try volume([0, 3, 6, 9])
        // Columns 1 mm apart: 9 mm across the slices make 10 rows.
        let section = volume.section(.row, at: 0, isotropic: true)
        XCTAssertTrue(section.isInterpolated)
        XCTAssertEqual(section.height, 10)
        XCTAssertEqual(section.geometry.rowSpacing, 1)
        // Row 1 is 1 mm below the last slice: two thirds of slice 3, one third of slice 2.
        XCTAssertEqual(section.values[section.width * 1], Float(30000) - 10000 / 3, accuracy: 0.01)
        XCTAssertEqual(section.values[section.width * 9], 0)
        // Rows 2 mm apart: interpolated every 2 mm, 9 mm give 5 rows.
        XCTAssertEqual(volume.section(.column, at: 0, isotropic: true).height, 5)
    }

    func testStacksThatAreNotRegularAreRefusedWithTheirReason() throws {
        XCTAssertThrowsError(try volume([0])) {
            XCTAssertEqual($0 as? DICOMVolume.Refusal, .tooFewSlices(1))
        }
        XCTAssertThrowsError(try volume([0, 3, 7])) {
            XCTAssertEqual($0 as? DICOMVolume.Refusal, .notAStack([.irregularSpacing(smallest: 3, largest: 4)]))
            XCTAssertTrue(String(describing: $0).contains("gaps from 3.000 to 4.000 mm"))
        }
        XCTAssertThrowsError(try volume([0, 3, 3])) {
            guard case .notAStack(let issues)? = $0 as? DICOMVolume.Refusal else { return XCTFail("\($0)") }
            XCTAssertTrue(issues.contains(.duplicatePositions(count: 1)))
        }
        XCTAssertThrowsError(try volume([0, 3, 6]) { index, z in
            index == 1 ? self.geometry(z: z, orientation: [0, 1, 0, 0, 0, -1]) : self.geometry(z: z)
        }) {
            guard case .notAStack(let issues)? = $0 as? DICOMVolume.Refusal else { return XCTFail("\($0)") }
            XCTAssertTrue(issues.contains(.mixedOrientations(count: 1)))
        }
        // A gantry tilt: each slice 1 mm further along x.
        XCTAssertThrowsError(try volume([0, 3, 6]) { index, z in self.geometry(z: z, x: -3 + Double(index)) }) {
            guard case .sheared(let degrees)? = $0 as? DICOMVolume.Refusal else { return XCTFail("\($0)") }
            XCTAssertEqual(degrees, atan(1.0 / 3) * 180 / .pi, accuracy: 1e-9)
        }
        XCTAssertThrowsError(try volume([0, 3, 6], maximumBytes: 100)) {
            XCTAssertEqual($0 as? DICOMVolume.Refusal, .tooLarge(bytes: 7 * 5 * 3 * 4, limit: 100))
        }
    }

    func testFiveHundredSlicesFitTheDefaultLimit() {
        // 500 slices of 512 × 512, four bytes a value: 500 MiB, under 1 GiB.
        XCTAssertEqual(DICOMVolume.byteCount(columns: 512, rows: 512, depth: 500), 500 << 20)
        XCTAssertLessThan(DICOMVolume.byteCount(columns: 512, rows: 512, depth: 500), 1 << 30)
    }
}
