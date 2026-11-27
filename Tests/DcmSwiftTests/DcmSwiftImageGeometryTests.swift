//
//  DcmSwiftImageGeometryTests.swift
//  DcmSwiftTests
//
//  Where pixels lie in the patient (PS3.3 C.7.6.2.1.1) and where two
//  images cross. The positions on an oblique plane were computed apart
//  with NumPy 2.3 by the matrix of equation C.7.6.2.1-1; the reference
//  lines of an axial and a sagittal image are worked by hand.
//

import XCTest
@testable import DcmSwift

final class DcmSwiftImageGeometryTests: XCTestCase {
    /// 512 × 300, rotated 30° about x then 20° about z; rows 0.7 mm apart, columns 0.45 mm.
    private let oblique = DICOMImageGeometry(
        plane: DICOMImagePlane(position: [-120.5, 80.25, 33.0],
                               orientation: [0.939693, 0.34202, 0.0, -0.296198, 0.813798, 0.5])!,
        columns: 512, rows: 300, rowSpacing: 0.7, columnSpacing: 0.45, frameOfReferenceUID: "1.2.3")!

    /// 256 × 256 at z = 10, 1 mm pixels, from x = y = -128.
    private func axial(frameOfReference: String? = "1.2.3") -> DICOMImageGeometry {
        DICOMImageGeometry(plane: DICOMImagePlane(position: [-128, -128, 10], orientation: [1, 0, 0, 0, 1, 0])!,
                           columns: 256, rows: 256, rowSpacing: 1, columnSpacing: 1, frameOfReferenceUID: frameOfReference)!
    }

    /// 200 columns along y from -100, 100 rows down z from 60, at x.
    private func sagittal(x: Double = 5, frameOfReference: String? = "1.2.3") -> DICOMImageGeometry {
        DICOMImageGeometry(plane: DICOMImagePlane(position: [x, -100, 60], orientation: [0, 1, 0, 0, 0, -1])!,
                           columns: 200, rows: 100, rowSpacing: 1, columnSpacing: 1, frameOfReferenceUID: frameOfReference)!
    }

    private func assertEqual(_ a: [Double], _ b: [Double], accuracy: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, file: file, line: line)
        for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
    }

    func testPatientPositionsOfAnObliquePlaneMatchNumPy() {
        assertEqual(oblique.patientPosition(of: .init(column: 0, row: 0)), [-120.5, 80.25, 33.0])
        assertEqual(oblique.patientPosition(of: .init(column: 511, row: 0)), [95.58240535, 158.897499, 33.0])
        assertEqual(oblique.patientPosition(of: .init(column: 100, row: 250)), [-130.048465, 238.05555, 120.5])
        assertEqual(oblique.patientPosition(of: .init(column: 37.5, row: 12.25)), [-107.182578475, 92.99990535, 37.2875])
    }

    func testAPointOfThePatientProjectsBackOnItsPixel() {
        // Pixel 100, 250 moved 7 mm along the normal, as NumPy gives it.
        let (point, distance) = oblique.pixelPosition(of: [-128.8513956312488, 234.7666262343432, 126.56217827105866])
        XCTAssertEqual(point.column, 100, accuracy: 1e-6)
        XCTAssertEqual(point.row, 250, accuracy: 1e-6)
        XCTAssertEqual(distance, 7, accuracy: 1e-6)
        XCTAssertTrue(oblique.contains(point))
        XCTAssertFalse(oblique.contains(.init(column: 511.6, row: 0)))
    }

    func testReferenceLinesOfAnAxialAndASagittalImage() throws {
        // On the axial image, the sagittal one is the column x = 5, as long
        // as the sagittal image spans y: rows -100.5 + 128 to 99.5 + 128.
        let onAxial = try XCTUnwrap(axial().referenceLine(of: sagittal()))
        let rows = [onAxial.start.row, onAxial.end.row].sorted()
        XCTAssertEqual(onAxial.start.column, 133, accuracy: 1e-9)
        XCTAssertEqual(onAxial.end.column, 133, accuracy: 1e-9)
        XCTAssertEqual(rows[0], 27.5, accuracy: 1e-9)
        XCTAssertEqual(rows[1], 227.5, accuracy: 1e-9)

        // On the sagittal image, the axial one is the row z = 10, across
        // the whole width: the axial image spans y wider.
        let onSagittal = try XCTUnwrap(sagittal().referenceLine(of: axial()))
        let columns = [onSagittal.start.column, onSagittal.end.column].sorted()
        XCTAssertEqual(onSagittal.start.row, 50, accuracy: 1e-9)
        XCTAssertEqual(onSagittal.end.row, 50, accuracy: 1e-9)
        XCTAssertEqual(columns[0], -0.5, accuracy: 1e-9)
        XCTAssertEqual(columns[1], 199.5, accuracy: 1e-9)

        // Each end lies on both planes.
        for end in [onAxial.start, onAxial.end] {
            XCTAssertEqual(sagittal().pixelPosition(of: axial().patientPosition(of: end)).distance, 0, accuracy: 1e-9)
        }
    }

    func testNoReferenceLineWithoutACrossing() {
        // Parallel images.
        XCTAssertNil(axial().referenceLine(of: axial()))
        // A sagittal image beside the axial one.
        XCTAssertNil(axial().referenceLine(of: sagittal(x: 500)))
        // Two Frames of Reference: no common coordinates.
        XCTAssertNil(axial().referenceLine(of: sagittal(frameOfReference: "9.9")))
        // One without: the coordinates are taken as they are.
        XCTAssertNotNil(axial(frameOfReference: nil).referenceLine(of: sagittal()))
    }

    func testEdgesAreNamedByTheirPatientDirections() {
        let edges = axial().edgeLabels
        XCTAssertEqual([edges.top, edges.bottom, edges.left, edges.right], ["A", "P", "R", "L"])
        let side = sagittal().edgeLabels
        XCTAssertEqual([side.top, side.bottom, side.left, side.right], ["H", "F", "A", "P"])
        // The oblique row points mostly left, a third posterior.
        XCTAssertEqual(oblique.edgeLabels.right, "LP")
        XCTAssertEqual(DICOMImageGeometry.label([0, 0, 0]), "")
    }

    func testGeometryOfAFrameFromItsFunctionalGroups() throws {
        let builder = DICOMDataSetBuilder()
        builder.set("Rows", [UInt16(4)])
        builder.set("Columns", [UInt16(6)])
        builder.set("FrameOfReferenceUID", ["1.2.3"])
        builder.sequence("SharedFunctionalGroupsSequence", items: [{ item in
            builder.sequence("PixelMeasuresSequence", in: item, items: [{ builder.set("PixelSpacing", ["0.5", "0.25"], in: $0) }])
            builder.sequence("PlaneOrientationSequence", in: item, items: [{ builder.set("ImageOrientationPatient", ["1", "0", "0", "0", "1", "0"], in: $0) }])
        }])
        builder.sequence("PerFrameFunctionalGroupsSequence", items: [0, 1].map { index in { item in
            builder.sequence("PlanePositionSequence", in: item, items: [{ builder.set("ImagePositionPatient", ["0", "0", "\(index * 3)"], in: $0) }])
        } })
        let second = try XCTUnwrap(DICOMImageGeometry(dataset: builder.dataSet, frame: 1))
        XCTAssertEqual(second.plane.position, [0, 0, 3])
        XCTAssertEqual(second.rowSpacing, 0.5)
        XCTAssertEqual(second.columnSpacing, 0.25)
        XCTAssertEqual([second.columns, second.rows], [6, 4])
        XCTAssertEqual(second.frameOfReferenceUID, "1.2.3")
        assertEqual(second.patientPosition(of: .init(column: 2, row: 1)), [0.5, 0.5, 3])
        XCTAssertNil(DICOMImageGeometry(dataset: DataSet()))
    }
}
