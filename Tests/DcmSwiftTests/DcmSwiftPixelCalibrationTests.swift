//
//  DcmSwiftPixelCalibrationTests.swift
//  DcmSwiftTests
//
//  The size of a pixel and its source (PS3.3 10.7.1.3, C.7.6.2.1.1,
//  C.8.11.4.1.1, C.8.5.5.1), on synthetic Data Sets. Expected lengths and
//  areas are worked by hand from the spacings given.
//

import XCTest
@testable import DcmSwift

final class DcmSwiftPixelCalibrationTests: XCTestCase {
    private func double(_ value: Double) -> Data {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { Data($0) }
    }

    func testPixelSpacingGivesTheRowSpacingFirstAndMeasuresAnisotropicPixels() throws {
        let builder = DICOMDataSetBuilder()
        builder.set("PixelSpacing", ["0.5", "0.25"])
        builder.set("PixelSpacingCalibrationType", ["GEOMETRY"])
        let calibration = try XCTUnwrap(DICOMPixelCalibration.all(in: builder.dataSet).first)
        XCTAssertEqual(calibration.rowSpacing, 0.5)
        XCTAssertEqual(calibration.columnSpacing, 0.25)
        XCTAssertEqual(calibration.source, .pixelSpacing(calibrationType: "GEOMETRY"))
        // 4 columns × 0.25 = 1 mm across, 3 rows × 0.5 = 1.5 mm down: √3.25.
        XCTAssertEqual(calibration.length(dx: 4, dy: 3), 3.25.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(calibration.length(dx: 0, dy: -2), 1, accuracy: 1e-12)
        XCTAssertEqual(calibration.area(pixels: 10), 1.25, accuracy: 1e-12)
    }

    func testImagerPixelSpacingIsCorrectedByTheMagnificationWhenGiven() throws {
        let builder = DICOMDataSetBuilder()
        builder.set("ImagerPixelSpacing", ["0.2", "0.1"])
        builder.set("EstimatedRadiographicMagnificationFactor", ["1.25"])
        let calibration = try XCTUnwrap(DICOMPixelCalibration.all(in: builder.dataSet).first)
        XCTAssertEqual(calibration.source, .imagerPixelSpacing(magnification: 1.25))
        XCTAssertEqual(calibration.rowSpacing, 0.16, accuracy: 1e-12)
        XCTAssertEqual(calibration.columnSpacing, 0.08, accuracy: 1e-12)

        let detector = DICOMDataSetBuilder()
        detector.set("ImagerPixelSpacing", ["0.2", "0.1"])
        XCTAssertEqual(DICOMPixelCalibration.all(in: detector.dataSet).first?.source, .imagerPixelSpacing(magnification: nil))
        XCTAssertEqual(DICOMPixelCalibration.all(in: detector.dataSet).first?.rowSpacing, 0.2)

        // Pixel Spacing, calibrated to a plane, comes before the detector.
        detector.set("PixelSpacing", ["0.18", "0.09"])
        let both = DICOMPixelCalibration.all(in: detector.dataSet)
        XCTAssertEqual(both.map(\.source), [.pixelSpacing(calibrationType: nil), .imagerPixelSpacing(magnification: nil)])
    }

    func testNominalScannedPixelSpacingAndInvalidValues() throws {
        let builder = DICOMDataSetBuilder()
        builder.set("NominalScannedPixelSpacing", ["0.1", "0.1"])
        builder.set("PixelSpacing", ["0.5"])
        builder.set("ImagerPixelSpacing", ["0", "0.2"])
        let all = DICOMPixelCalibration.all(in: builder.dataSet)
        XCTAssertEqual(all.map(\.source), [.nominalScannedPixelSpacing])
        // No calibration is an answer, not an error.
        XCTAssertEqual(DICOMPixelCalibration.all(in: DataSet()), [])
        XCTAssertNil(DICOMPixelCalibration.of(DataSet(), points: [(0, 0)]))
    }

    func testPixelMeasuresFollowThePerFrameThenSharedFunctionalGroups() throws {
        let builder = DICOMDataSetBuilder()
        builder.set("PixelSpacing", ["9", "9"])
        builder.sequence("SharedFunctionalGroupsSequence", items: [{ item in
            builder.sequence("PixelMeasuresSequence", in: item, items: [{ builder.set("PixelSpacing", ["0.7", "0.7"], in: $0) }])
        }])
        builder.sequence("PerFrameFunctionalGroupsSequence", items: [{ _ in }, { item in
            builder.sequence("PixelMeasuresSequence", in: item, items: [{ builder.set("PixelSpacing", ["0.9", "0.8"], in: $0) }])
        }])
        XCTAssertEqual(DICOMPixelCalibration.all(in: builder.dataSet, frame: 0).first?.rowSpacing, 0.7)
        let second = try XCTUnwrap(DICOMPixelCalibration.all(in: builder.dataSet, frame: 1).first)
        XCTAssertEqual(second.rowSpacing, 0.9)
        XCTAssertEqual(second.columnSpacing, 0.8)
    }

    func testUltrasoundRegionsCalibrateTheirOwnPixelsOnly() throws {
        let builder = DICOMDataSetBuilder()
        func region(_ item: DataItem, units: UInt16, box: [UInt32], deltaX: Double, deltaY: Double) {
            builder.set("RegionLocationMinX0", box[0], vr: .UL, in: item)
            builder.set("RegionLocationMinY0", box[1], vr: .UL, in: item)
            builder.set("RegionLocationMaxX1", box[2], vr: .UL, in: item)
            builder.set("RegionLocationMaxY1", box[3], vr: .UL, in: item)
            builder.set("PhysicalUnitsXDirection", units, vr: .US, in: item)
            builder.set("PhysicalUnitsYDirection", units, vr: .US, in: item)
            builder.set("PhysicalDeltaX", double(deltaX), vr: .FD, in: item)
            builder.set("PhysicalDeltaY", double(deltaY), vr: .FD, in: item)
        }
        builder.sequence("SequenceOfUltrasoundRegions", items: [
            { region($0, units: 3, box: [10, 20, 200, 300], deltaX: 0.03, deltaY: -0.04) },
            // Seconds and hertz (a spectral Doppler region): not a length.
            { region($0, units: 4, box: [10, 310, 200, 400], deltaX: 0.01, deltaY: 0.5) },
        ])
        let all = DICOMPixelCalibration.all(in: builder.dataSet)
        XCTAssertEqual(all.count, 1)
        let calibration = try XCTUnwrap(all.first)
        XCTAssertEqual(calibration.source, .ultrasoundRegion(0))
        XCTAssertEqual(calibration.columnSpacing, 0.3, accuracy: 1e-12)
        XCTAssertEqual(calibration.rowSpacing, 0.4, accuracy: 1e-12)
        XCTAssertEqual(calibration.bounds, .init(minX: 10, minY: 20, maxX: 200, maxY: 300))
        XCTAssertNotNil(DICOMPixelCalibration.of(builder.dataSet, points: [(10, 20), (200, 300)]))
        // A measure leaving the region has no calibration.
        XCTAssertNil(DICOMPixelCalibration.of(builder.dataSet, points: [(10, 20), (201, 300)]))
    }
}
