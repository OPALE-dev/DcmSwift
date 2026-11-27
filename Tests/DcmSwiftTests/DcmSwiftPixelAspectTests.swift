//
//  DcmSwiftPixelAspectTests.swift
//  DcmSwiftTests
//
//  The shape of a pixel (PS3.3 10.7.1.3, C.7.6.3.1.7): the spacings of a
//  calibration of the whole image, else Pixel Aspect Ratio, else a square.
//

import XCTest
@testable import DcmSwift

final class DcmSwiftPixelAspectTests: XCTestCase {
    func testPixelSpacingComesBeforePixelAspectRatio() {
        let builder = DICOMDataSetBuilder()
        builder.set("PixelSpacing", ["4", "1"])
        builder.set("PixelAspectRatio", ["1", "1"])
        let aspect = DICOMPixelAspect(dataset: builder.dataSet)
        XCTAssertEqual(aspect.ratio, 4)
        XCTAssertEqual(aspect.source, .calibration(.pixelSpacing(calibrationType: nil)))
        XCTAssertFalse(aspect.isSquare)

        let imager = DICOMDataSetBuilder()
        imager.set("ImagerPixelSpacing", ["0.1", "0.2"])
        XCTAssertEqual(DICOMPixelAspect(dataset: imager.dataSet).ratio, 0.5)
    }

    func testPixelAspectRatioWithoutSpacing() {
        let builder = DICOMDataSetBuilder()
        builder.set("PixelAspectRatio", ["4", "3"])
        let aspect = DICOMPixelAspect(dataset: builder.dataSet)
        XCTAssertEqual(aspect.source, .pixelAspectRatio)
        XCTAssertEqual(aspect.ratio, 4.0 / 3, accuracy: 1e-12)
        XCTAssertNil(aspect.invalidPixelAspectRatio)
    }

    func testSquareWithoutEitherAndInvalidRatioReported() {
        let none = DICOMPixelAspect(dataset: DataSet())
        XCTAssertEqual(none.source, .none)
        XCTAssertTrue(none.isSquare)

        let invalid = DICOMDataSetBuilder()
        invalid.set("PixelAspectRatio", ["0", "3"])
        let aspect = DICOMPixelAspect(dataset: invalid.dataSet)
        XCTAssertTrue(aspect.isSquare)
        XCTAssertEqual(aspect.source, .none)
        XCTAssertNotNil(aspect.invalidPixelAspectRatio)

        // An ultrasound region calibrates its own pixels, not the image: not its shape.
        let region = try! XCTUnwrap(DICOMPixelCalibration(rowSpacing: 2, columnSpacing: 1, source: .ultrasoundRegion(0),
                                                          bounds: .init(minX: 0, minY: 0, maxX: 9, maxY: 9)))
        XCTAssertTrue(DICOMPixelAspect(calibrations: [region], pixelAspectRatio: nil).isSquare)
    }
}
