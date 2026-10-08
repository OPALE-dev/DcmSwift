import Foundation
import XCTest
@testable import DcmSwift

/// Segmentations (PS3.3 A.51) and Parametric Maps (PS3.3 A.75).
final class DcmSwiftSegmentationTests: XCTestCase {
    /// Single-frame CT images of 3 × 3 pixels: 9 bits a frame, so packed
    /// frames cross byte boundaries.
    private func sources(_ count: Int) -> [DataSet] {
        (0..<count).map { index in
            let builder = DICOMDataSetBuilder()
            builder.set("SOPClassUID", "1.2.840.10008.5.1.4.1.1.2")
            builder.set("SOPInstanceUID", "1.2.826.0.1.3680043.10.2.\(index + 1)")
            builder.set("SeriesInstanceUID", "1.2.826.0.1.3680043.10.2")
            builder.set("StudyInstanceUID", "1.2.826.0.1.3680043.10.1")
            builder.set("FrameOfReferenceUID", "1.2.826.0.1.3680043.10.3")
            builder.set("PatientName", "Doe^Jane")
            builder.set("Rows", UInt16(3), vr: .US)
            builder.set("Columns", UInt16(3), vr: .US)
            builder.set("PixelSpacing", ["0.5", "0.5"])
            builder.set("ImageOrientationPatient", ["1", "0", "0", "0", "1", "0"])
            builder.set("ImagePositionPatient", ["0", "0", String(index * 2)])
            return builder.finish()
        }
    }

    func testBinaryRoundTrip() throws {
        let images = sources(3)
        let cross: [Bool] = [false, true, false, true, true, true, false, true, false]
        let corner: [Bool] = [true, false, false, false, false, false, false, false, true]
        let dataSet = try DICOMSegmentation.binary(
            sources: images,
            segments: [.init(label: "cross", category: DICOMCode("85756007", scheme: "SCT", meaning: "Tissue"),
                             type: DICOMCode("10200004", scheme: "SCT", meaning: "Liver")),
                       .init(label: "corner", category: DICOMCode("85756007", scheme: "SCT", meaning: "Tissue"),
                             type: DICOMCode("64033007", scheme: "SCT", meaning: "Kidney"))],
            masks: [[cross, nil, cross], [nil, corner, nil]])
        let findings = DICOMIODValidator().validate(dataSet).findings
        XCTAssertTrue(findings.isEmpty, findings.map(\.description).joined(separator: "\n"))

        let segmentation = try XCTUnwrap(DICOMSegmentation(dataSet: dataSet))
        XCTAssertEqual(segmentation.type, .binary)
        XCTAssertEqual(segmentation.segments.map(\.label), ["cross", "corner"])
        XCTAssertEqual(segmentation.segments.last?.type?.meaning, "Kidney")
        XCTAssertEqual(segmentation.frames.map(\.segmentNumber), [1, 1, 2])
        XCTAssertEqual(segmentation.frames.map { $0.sourceImages.first?.sopInstanceUID },
                       ["1.2.826.0.1.3680043.10.2.1", "1.2.826.0.1.3680043.10.2.3", "1.2.826.0.1.3680043.10.2.2"])
        XCTAssertEqual(segmentation.frames.last?.position, [0, 0, 2])
        XCTAssertEqual(try segmentation.mask(frame: 0), cross.map { $0 ? 1 : 0 })
        XCTAssertEqual(try segmentation.mask(frame: 1), cross.map { $0 ? 1 : 0 })
        XCTAssertEqual(try segmentation.mask(frame: 2), corner.map { $0 ? 1 : 0 })

        XCTAssertThrowsError(try DICOMSegmentation.binary(sources: images, segments: [], masks: [[cross, cross, cross]]))
        XCTAssertThrowsError(try DICOMSegmentation.binary(
            sources: images, segments: [.init(label: "x", category: DICOMCode("1", scheme: "99", meaning: "x"),
                                              type: DICOMCode("1", scheme: "99", meaning: "x"))],
            masks: [[nil, nil, nil]]), "every mask absent")
    }

    func testParametricMap() throws {
        let builder = DICOMDataSetBuilder()
        builder.set("SOPClassUID", "1.2.840.10008.5.1.4.1.1.30")
        builder.set("Rows", UInt16(1), vr: .US)
        builder.set("Columns", UInt16(2), vr: .US)
        builder.set("NumberOfFrames", "2")
        builder.sequence("SharedFunctionalGroupsSequence", items: [{ shared in
            builder.sequence("RealWorldValueMappingSequence", in: shared, items: [{ item in
                builder.set("LUTLabel", "ADC", in: item)
                builder.set("RealWorldValueSlope", Data(withUnsafeBytes(of: (2.0).bitPattern.littleEndian) { Array($0) }),
                            vr: .FD, in: item)
                builder.set("RealWorldValueIntercept", Data(withUnsafeBytes(of: (0.5).bitPattern.littleEndian) { Array($0) }),
                            vr: .FD, in: item)
                builder.code("MeasurementUnitsCodeSequence", DICOMCode("mm2/s", scheme: "UCUM", meaning: "mm2/s"), in: item)
            }])
        }])
        let floats: [Float] = [1, -2.5, 3.25, 1e-3]
        builder.set("FloatPixelData", floats.withUnsafeBufferPointer { Data(buffer: $0) }, vr: .OF)
        let map = try XCTUnwrap(DICOMParametricMap(dataSet: builder.finish()))
        XCTAssertEqual(map.mapping(frame: 0)?.label, "ADC")
        XCTAssertEqual(map.mapping(frame: 1)?.units?.value, "mm2/s")
        XCTAssertEqual(try map.values(frame: 0), [2.5, -4.5])
        XCTAssertEqual(try map.values(frame: 1).first, 7)
        XCTAssertEqual(try map.values(frame: 1).last ?? 0, 0.502, accuracy: 1e-6)
    }
}
