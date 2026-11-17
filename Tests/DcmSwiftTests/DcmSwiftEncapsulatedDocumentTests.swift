import Foundation
import XCTest
@testable import DcmSwift

/// Encapsulated Documents (PS3.3 A.45, A.85, C.24).
final class DcmSwiftEncapsulatedDocumentTests: XCTestCase {
    private let pdf = Data("%PDF-1.4\n%%EOF\n".utf8)

    func testWrapAndRead() throws {
        // An odd length, padded in the Value and restored by the length.
        let document = pdf
        XCTAssertEqual(document.count % 2, 1)
        let context = DcmSwiftIODValidationTests.secondaryCaptureImage()
        let dataSet = DICOMEncapsulatedDocument(kind: .pdf, document: document, title: "Report").dataSet(context: context)
        XCTAssertEqual(dataSet.string(forTag: "SOPClassUID"), "1.2.840.10008.5.1.4.1.1.104.1")
        XCTAssertEqual(dataSet.string(forTag: "StudyInstanceUID"), context.string(forTag: "StudyInstanceUID"))
        XCTAssertEqual(dataSet.element(forTagName: "PatientName")?.textValues, ["Doe^Jane"])
        XCTAssertEqual(dataSet.string(forTag: "Modality"), "DOC")
        XCTAssertEqual(dataSet.element(forTagName: "EncapsulatedDocument")?.data.count, document.count + 1)
        let findings = DICOMIODValidator().validate(dataSet).findings
        XCTAssertTrue(findings.isEmpty, findings.map(\.description).joined(separator: "\n"))

        let read = try XCTUnwrap(DICOMEncapsulatedDocument(dataSet: dataSet))
        XCTAssertEqual(read.kind, .pdf)
        XCTAssertEqual(read.document, document)
        XCTAssertEqual(read.title, "Report")

        // Through a Part 10 file.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: url) }
        try dataSet.writePart10(to: url)
        let file = try XCTUnwrap(DicomFile(forPath: url.path))
        XCTAssertEqual(DICOMEncapsulatedDocument(dataSet: try XCTUnwrap(file.dataset))?.document, document)
        XCTAssertEqual(try Data(contentsOf: url).subdata(in: 128..<132), Data("DICM".utf8))
    }

    func testEveryKindConformsToItsIOD() {
        for kind in DICOMEncapsulatedDocument.Kind.allCases {
            let dataSet = DICOMEncapsulatedDocument(kind: kind, document: Data("x".utf8), title: "T").dataSet()
            let findings = DICOMIODValidator().validate(dataSet).findings
            XCTAssertTrue(findings.isEmpty, "\(kind): " + findings.map(\.description).joined(separator: "\n"))
            XCTAssertEqual(dataSet.string(forTag: "MIMETypeOfEncapsulatedDocument"), kind.mimeType)
            XCTAssertEqual(dataSet.string(forTag: "Modality"), kind.isModel ? "M3D" : "DOC")
            // MTL has no Frame of Reference Module.
            XCTAssertEqual(dataSet.element(forTagName: "FrameOfReferenceUID") != nil, kind == .stl || kind == .obj)
        }
    }

    func testCDAAndSTL() {
        let cda = Data(#"<ClinicalDocument><id root="2.16.840.1.113883.19" extension="c266"/></ClinicalDocument>"#.utf8)
        XCTAssertEqual(DICOMEncapsulatedDocument.cdaIdentifier(cda), "2.16.840.1.113883.19^c266")
        let dataSet = DICOMEncapsulatedDocument(kind: .cda, document: cda).dataSet()
        XCTAssertEqual(dataSet.string(forTag: "HL7InstanceIdentifier"), "2.16.840.1.113883.19^c266")

        XCTAssertTrue(DICOMEncapsulatedDocument.isASCIISTL(Data("solid t\nendsolid t\n".utf8)))
        // A binary STL whose header starts with "solid": 84 + 50 bytes.
        var binary = Data("solid binary".utf8) + Data(count: 68) + Data([1, 0, 0, 0]) + Data(count: 50)
        XCTAssertFalse(DICOMEncapsulatedDocument.isASCIISTL(binary))
        binary.append(0)
        XCTAssertTrue(DICOMEncapsulatedDocument.isASCIISTL(binary))
        XCTAssertEqual(DICOMEncapsulatedDocument.Kind(pathExtension: "STL"), .stl)
        XCTAssertNil(DICOMEncapsulatedDocument.Kind(pathExtension: "docx"))
    }
}
