import Foundation
import XCTest
@testable import DcmSwift

/// Structured Reports (PS3.3 C.17) and TID 1500 (PS3.16).
final class DcmSwiftStructuredReportTests: XCTestCase {
    private let volume = DICOMCode("118565006", scheme: "SCT", meaning: "Volume")
    private let cm3 = DICOMCode("cm3", scheme: "UCUM", meaning: "cm3")

    func testMeasurementReportRoundTrip() throws {
        let image = DcmSwiftIODValidationTests.secondaryCaptureImage()
        let reference = DICOMSRReference(sopClassUID: DcmSwiftIODValidationTests.secondaryCapture,
                                         sopInstanceUID: "1.2.826.0.1.3680043.10.1.1")
        let report = DICOMMeasurementReport(
            procedure: DICOMCode("77477000", scheme: "SCT", meaning: "CT"), observerName: "Doe^John", images: [reference],
            groups: [.init(trackingIdentifier: "lesion", trackingUID: "1.2.3.4",
                           finding: DICOMCode("27925004", scheme: "SCT", meaning: "Nodule"),
                           measurements: [.init(concept: volume, value: 12.5, units: cm3)])])
        let dataSet = report.document().dataSet(context: image)
        XCTAssertEqual(dataSet.string(forTag: "SOPClassUID"), DICOMStructuredReport.comprehensive3DSR)
        XCTAssertEqual(dataSet.string(forTag: "StudyInstanceUID"), image.string(forTag: "StudyInstanceUID"))
        let findings = DICOMIODValidator().validate(dataSet).findings
        XCTAssertTrue(findings.isEmpty, findings.map(\.description).joined(separator: "\n"))

        let document = try XCTUnwrap(DICOMStructuredReport(dataSet: dataSet))
        XCTAssertEqual(document.template?.identifier, "1500")
        XCTAssertEqual(document.root.conceptName?.value, "126000")
        let read = try XCTUnwrap(DICOMMeasurementReport(document: document))
        XCTAssertEqual(read.observerName, "Doe^John")
        XCTAssertEqual(read.procedure.value, "77477000")
        XCTAssertEqual(read.images, [reference])
        XCTAssertEqual(read.groups.map(\.trackingIdentifier), ["lesion"])
        XCTAssertEqual(read.groups.first?.trackingUID, "1.2.3.4")
        XCTAssertEqual(read.groups.first?.finding?.meaning, "Nodule")
        XCTAssertEqual(read.groups.first?.measurements.first?.value, 12.5)
        XCTAssertEqual(read.groups.first?.measurements.first?.units.value, "cm3")
    }

    func testEveryValueTypeRoundTrips() throws {
        let concept = DICOMCode("121071", scheme: "DCM", meaning: "Finding")
        let image = DICOMSRReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3", frames: [2])
        let children: [DICOMSRContentItem] = [
            DICOMSRContentItem("CONTAINS", concept, .text("free text")),
            DICOMSRContentItem("CONTAINS", concept, .code(DICOMCode("27925004", scheme: "SCT", meaning: "Nodule"))),
            DICOMSRContentItem("CONTAINS", volume, .number(0.125, units: cm3, qualifier: nil)),
            DICOMSRContentItem("CONTAINS", volume, .number(nil, units: nil,
                                                           qualifier: DICOMCode("114006", scheme: "DCM", meaning: "Measurement failure"))),
            DICOMSRContentItem("CONTAINS", concept, .dateTime("20261008120000")),
            DICOMSRContentItem("CONTAINS", concept, .date("20261008")),
            DICOMSRContentItem("CONTAINS", concept, .time("120000")),
            DICOMSRContentItem("CONTAINS", concept, .uidReference("1.2.3.4")),
            DICOMSRContentItem("CONTAINS", concept, .personName("Doe^Jane")),
            DICOMSRContentItem("CONTAINS", concept, .image(image), children: [
                DICOMSRContentItem("HAS PROPERTIES", concept, .spatialCoordinates(graphicType: "POINT", points: [1.5, 2.25])),
            ]),
            DICOMSRContentItem("CONTAINS", concept, .spatialCoordinates3D(graphicType: "POINT", points: [1, 2, 3],
                                                                         frameOfReferenceUID: "1.2.5")),
            DICOMSRContentItem("CONTAINS", concept, .temporalCoordinates(rangeType: "POINT", samplePositions: [10],
                                                                        timeOffsets: [], dateTimes: [])),
            DICOMSRContentItem("INFERRED FROM", nil, .reference([1, 3])),
        ]
        let report = DICOMStructuredReport(root: DICOMSRContentItem(
            nil, DICOMCode("126000", scheme: "DCM", meaning: "Imaging Measurement Report"),
            .container(continuity: "SEPARATE"), children: children))
        let read = try XCTUnwrap(DICOMStructuredReport(dataSet: report.dataSet()))
        let items = read.root.children
        XCTAssertEqual(items.map(\.value.valueType), children.map(\.value.valueType))
        XCTAssertEqual(items.map(\.relationship), children.map(\.relationship))
        guard case .text("free text") = items[0].value,
              case .code(let code) = items[1].value, code.value == "27925004",
              case .number(0.125?, let units?, nil) = items[2].value, units.value == "cm3",
              case .number(nil, nil, let qualifier?) = items[3].value, qualifier.value == "114006",
              case .dateTime("20261008120000") = items[4].value,
              case .personName("Doe^Jane") = items[8].value,
              case .image(let reference) = items[9].value, reference == image,
              case .spatialCoordinates("POINT", [1.5, 2.25]) = items[9].children.first?.value,
              case .spatialCoordinates3D("POINT", [1, 2, 3], "1.2.5") = items[10].value,
              case .temporalCoordinates("POINT", [10], [], []) = items[11].value,
              case .reference([1, 3]) = items[12].value else {
            return XCTFail("values differ: \(items.map(\.value))")
        }
        XCTAssertEqual(read.root.flattened().map(\.identifier).last, [1, 13])
    }

    func testDecimalStrings() {
        XCTAssertEqual(DICOMSRContentItem.decimalString(12), "12")
        XCTAssertEqual(DICOMSRContentItem.decimalString(0.125), "0.125")
        XCTAssertLessThanOrEqual(DICOMSRContentItem.decimalString(1.0 / 3.0).count, 16)
        XCTAssertEqual(Double(DICOMSRContentItem.decimalString(1.0 / 3.0)) ?? 0, 1.0 / 3.0, accuracy: 1e-12)
    }
}
