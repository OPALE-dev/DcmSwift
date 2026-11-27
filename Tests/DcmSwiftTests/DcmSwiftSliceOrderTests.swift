//
//  DcmSwiftSliceOrderTests.swift
//  DcmSwiftTests
//
//  The order of the slices of a series along the normal of their plane
//  (PS3.3 C.7.6.2.1.1). Reference positions and locations computed with
//  NumPy 2.3.5 (cross product, projection), independently of DcmSwift.
//

import XCTest
@testable import DcmSwift

final class DcmSwiftSliceOrderTests: XCTestCase {
    /// An oblique plane, tilted 20° about x; its normal by NumPy.
    private let oblique = [1, 0, 0, 0, 0.939693, -0.34202]
    private let positions: [[Double]] = [
        [-120.0, -95.0, 30.0], [-120.0, -94.145, 32.3492], [-120.0, -93.2899, 34.6985], [-120.0, -92.4349, 37.0477],
    ]
    private let locations = [-4.301109, -1.801156, 0.698926, 3.198879]

    private func slice(_ position: [Double]?, _ orientation: [Double]? = nil, number: Int?, uid: String) -> DICOMSliceOrder.Slice {
        let plane = position.flatMap { DICOMImagePlane(position: $0, orientation: orientation ?? oblique) }
        return DICOMSliceOrder.Slice(plane: plane, instanceNumber: number, sopInstanceUID: uid)
    }

    func testThePlaneNormalAndLocationMatchNumPy() throws {
        let plane = try XCTUnwrap(DICOMImagePlane(position: positions[2], orientation: oblique))
        for (value, expected) in zip(plane.normal, [0, 0.342019894888923, 0.9396927112094517]) {
            XCTAssertEqual(value, expected, accuracy: 1e-6)
        }
        XCTAssertEqual(plane.location(along: plane.normal), locations[2], accuracy: 1e-5)
        XCTAssertNil(DICOMImagePlane(position: [0, 0], orientation: oblique))
        XCTAssertNil(DICOMImagePlane(position: [0, 0, 0], orientation: [0, 0, 0, 0, 1, 0]))
    }

    func testThePlaneIsReadFromTheDataSet() throws {
        let dataset = DataSet()
        _ = dataset.set(value: "-120\\-95\\30", forTagName: "ImagePositionPatient")
        _ = dataset.set(value: "1\\0\\0\\0\\0.939693\\-0.34202", forTagName: "ImageOrientationPatient")
        let plane = try XCTUnwrap(DICOMImagePlane(dataset: dataset))
        XCTAssertEqual(plane.position, positions[0])
        XCTAssertNil(DICOMImagePlane(dataset: DataSet()))
    }

    func testSlicesFollowTheirPositionWhateverTheirInstanceNumbers() {
        // Instance Numbers mixed against the positions.
        let slices = [slice(positions[2], number: 1, uid: "1.2.3"), slice(positions[0], number: 4, uid: "1.2.1"),
                      slice(positions[3], number: 2, uid: "1.2.4"), slice(positions[1], number: 3, uid: "1.2.2")]
        let order = DICOMSliceOrder(slices)
        XCTAssertEqual(order.criterion, .position)
        XCTAssertEqual(order.order, [1, 3, 0, 2])
        for (value, expected) in zip(order.locations ?? [], locations) { XCTAssertEqual(value, expected, accuracy: 1e-5) }
        XCTAssertEqual(order.spacing ?? 0, 2.5, accuracy: 1e-3)
        XCTAssertEqual(order.issues, [])
    }

    func testDuplicatePositionsAndUnevenSpacingAreReported() {
        let slices = [slice(positions[0], number: 1, uid: "1.1"), slice(positions[0], number: 2, uid: "1.2"),
                      slice(positions[1], number: 3, uid: "1.3"), slice(positions[3], number: 4, uid: "1.4")]
        let order = DICOMSliceOrder(slices)
        XCTAssertEqual(order.order, [0, 1, 2, 3])
        XCTAssertEqual(order.issues.count, 2)
        XCTAssertEqual(order.issues.first, .duplicatePositions(count: 1))
        guard case .irregularSpacing(let smallest, let largest)? = order.issues.last else { return XCTFail("spacing") }
        XCTAssertEqual(smallest, 2.5, accuracy: 1e-3)
        XCTAssertEqual(largest, 5.0, accuracy: 1e-3)
    }

    func testMixedOrientationsFallBackOnInstanceNumbers() {
        let axial = [1.0, 0, 0, 0, 1, 0]
        let slices = [slice(positions[0], number: 3, uid: "1.1"), slice(positions[1], axial, number: 1, uid: "1.2"),
                      slice(positions[2], number: 2, uid: "1.3")]
        let order = DICOMSliceOrder(slices)
        XCTAssertEqual(order.criterion, .instanceNumber)
        XCTAssertEqual(order.order, [1, 2, 0])
        XCTAssertEqual(order.issues, [.mixedOrientations(count: 1)])
        XCTAssertNil(order.locations)
    }

    func testWithoutPlanesNorNumbersUIDsAreComparedAsNumbers() {
        let slices = [slice(nil, number: nil, uid: "1.2.10"), slice(nil, number: 5, uid: "1.2.9"), slice(nil, number: nil, uid: "1.2.9.1")]
        let order = DICOMSliceOrder(slices)
        XCTAssertEqual(order.criterion, .sopInstanceUID)
        XCTAssertEqual(order.order, [1, 2, 0])
        XCTAssertEqual(order.issues, [.missingPlanes(count: 3), .missingInstanceNumbers(count: 2)])
    }
}
