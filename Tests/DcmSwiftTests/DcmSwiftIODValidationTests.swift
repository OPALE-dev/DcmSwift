import XCTest
@testable import DcmSwift

/// IOD validation (PS3.3): the specification generated from the 2026d
/// DocBook, the validator, and the receive policy of the archive services.
final class DcmSwiftIODValidationTests: XCTestCase {
    private let secondaryCapture = "1.2.840.10008.5.1.4.1.1.7"

    /// A Secondary Capture Image with every attribute its mandatory modules
    /// require unconditionally.
    private func secondaryCaptureImage() -> DataSet {
        let dataSet = DataSet()
        let values: [(String, Any)] = [
            ("SOPClassUID", secondaryCapture), ("SOPInstanceUID", "1.2.826.0.1.3680043.10.1.1"),
            ("PatientName", "Doe^Jane"), ("PatientID", "P1"), ("PatientBirthDate", ""), ("PatientSex", "F"),
            ("StudyInstanceUID", "1.2.826.0.1.3680043.10.1.2"), ("StudyDate", "20261008"), ("StudyTime", "120000"),
            ("ReferringPhysicianName", ""), ("StudyID", "1"), ("AccessionNumber", ""),
            ("Modality", "OT"), ("SeriesInstanceUID", "1.2.826.0.1.3680043.10.1.3"), ("SeriesNumber", "1"),
            ("ConversionType", "WSD"), ("InstanceNumber", "1"),
            ("SamplesPerPixel", UInt16(1)), ("PhotometricInterpretation", "MONOCHROME2"),
            ("Rows", UInt16(2)), ("Columns", UInt16(2)), ("BitsAllocated", UInt16(8)), ("BitsStored", UInt16(8)),
            ("HighBit", UInt16(7)), ("PixelRepresentation", UInt16(0)),
        ]
        for (name, value) in values { XCTAssertNotNil(dataSet.set(value: value, forTagName: name), name) }
        return dataSet
    }

    func testSpecificationMapsSOPClassesToTheirIODs() throws {
        let specification = DICOMIODSpecification.shared
        XCTAssertEqual(specification.edition, "2026d")
        XCTAssertGreaterThan(specification.sopClassUIDs.count, 150)
        let ct = try XCTUnwrap(specification.iod(forSOPClass: "1.2.840.10008.5.1.4.1.1.2"))
        XCTAssertTrue(ct.name.hasPrefix("CT Image"), ct.name)
        let patient = try XCTUnwrap(ct.modules.first { $0.name == "Patient" })
        XCTAssertEqual(patient.table, "C.7-1")
        XCTAssertEqual(patient.usage, "M")
        XCTAssertTrue(ct.modules.contains { $0.usage == "C" && $0.condition != nil })
        // Enhanced CT has Functional Group Macros.
        let enhanced = try XCTUnwrap(specification.iod(forSOPClass: "1.2.840.10008.5.1.4.1.1.2.1"))
        XCTAssertTrue(enhanced.functionalGroups.contains { $0.name == "Pixel Measures" && $0.usage == "M" })
        // Patient Sex has Enumerated Values; macros are included by reference.
        let entries = try XCTUnwrap(specification.table("C.7-1")).entries
        XCTAssertEqual(entries.first { $0.tag == "00100040" }?.enumeratedValues, ["M", "F", "O"])
        XCTAssertTrue(entries.contains { $0.include != nil })
    }

    func testCompleteInstanceIsValid() {
        let report = DICOMIODValidator().validate(secondaryCaptureImage())
        XCTAssertTrue(report.isValid, report.findings.map(\.description).joined(separator: "\n"))
        XCTAssertEqual(report.sopClassUID, secondaryCapture)
        XCTAssertTrue(report.checkedModules.contains("SC Equipment"))
    }

    func testMissingEmptyAndUnexpectedValuesAreReported() throws {
        let dataSet = secondaryCaptureImage()
        _ = dataSet.remove(dataElement: try XCTUnwrap(dataSet.element(forTagName: "PatientID")))
        _ = dataSet.remove(dataElement: try XCTUnwrap(dataSet.element(forTagName: "ConversionType")))
        _ = dataSet.set(value: "", forTagName: "Modality")
        _ = dataSet.set(value: "X", forTagName: "PatientSex")
        _ = dataSet.set(value: UInt16(2), forTagName: "PixelRepresentation")
        let findings = DICOMIODValidator().validate(dataSet).findings

        func finding(_ tag: String) -> DICOMIODFinding? { findings.first { $0.path == [tag] } }
        XCTAssertEqual(finding("00100020")?.kind, .missing, "Patient ID, Type 2")
        XCTAssertEqual(finding("00100020")?.table, "C.7-1")
        XCTAssertEqual(finding("00100020")?.module, "Patient")
        XCTAssertEqual(finding("00080064")?.kind, .missing, "Conversion Type, Type 1")
        XCTAssertEqual(finding("00080060")?.kind, .empty, "Modality, Type 1")
        XCTAssertEqual(finding("00100040")?.kind, .unexpectedValue, "Patient Sex")
        // Binary Enumerated Values are written in hexadecimal: 0000H, 0001H.
        XCTAssertEqual(finding("00280103")?.kind, .unexpectedValue, "Pixel Representation")
        XCTAssertEqual(findings.count, 5, findings.map(\.description).joined(separator: "\n"))
        XCTAssertTrue(finding("00080064")?.description.contains("PS3.3 Table C.8-24") ?? false)
    }

    func testSequenceItemsAreValidated() throws {
        let dataSet = secondaryCaptureImage()
        // Source Image Sequence (General Reference, a user-optional module):
        // its Items need the Referenced SOP Class and Instance UIDs.
        let sequence = DataSequence(withTag: try XCTUnwrap(DicomSpec.shared.dataTag(forName: "SourceImageSequence")))
        sequence.vr = .SQ
        sequence.length = -1
        let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
        item.length = -1
        sequence.items.append(item)
        let uid = try XCTUnwrap(DataElement(withTagName: "ReferencedSOPClassUID", dataset: dataSet, parent: item))
        uid.vr = .UI
        XCTAssertTrue(uid.setValue(secondaryCapture))
        item.elements.append(uid)
        dataSet.add(element: sequence)
        let findings = DICOMIODValidator().validate(dataSet).findings
        XCTAssertEqual(findings.map(\.path), [["00082112", "00081155"]], findings.map(\.description).joined(separator: "\n"))
        XCTAssertEqual(findings.first?.module, "General Reference")
    }

    func testUnknownSOPClassAndFunctionalGroups() {
        let unknown = DataSet()
        _ = unknown.set(value: "1.2.826.0.1.3680043.10.9.9", forTagName: "SOPClassUID")
        XCTAssertEqual(DICOMIODValidator().validate(unknown).findings.map(\.kind), [.unknownIOD])
        XCTAssertEqual(DICOMIODValidator().validate(DataSet()).findings.map(\.kind), [.unknownIOD])

        // An Enhanced CT Image without Functional Groups lacks the
        // mandatory macros.
        let enhanced = DataSet()
        _ = enhanced.set(value: "1.2.840.10008.5.1.4.1.1.2.1", forTagName: "SOPClassUID")
        let modules = Set(DICOMIODValidator().validate(enhanced).findings.map(\.module))
        XCTAssertTrue(modules.isSuperset(of: ["Pixel Measures", "Frame Content", "Plane Position (Patient)"]), "\(modules)")
    }

    func testConditionalInclusionsFollowTheirCondition() throws {
        let spec = DICOMIODSpecification.shared
        let numeric = try XCTUnwrap(spec.table("C.17-5")).entries.first { $0.include == "C.18.1-1" }
        XCTAssertEqual(numeric?.includeCondition, "if and only if Value Type (0040,A040) is NUM")
        // Numeric Measurement attributes are required in NUM Content Items
        // only.
        let nodes = spec.tree("C.17-5")
        let measured = nodes.first { $0.tag == "0040A300" }
        XCTAssertNotNil(measured?.includeCondition)
    }

    func testReceivePolicy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let incomplete = secondaryCaptureImage()
        _ = incomplete.remove(dataElement: try XCTUnwrap(incomplete.element(forTagName: "ConversionType")))
        func received(_ dataSet: DataSet) throws -> DICOMReceivedInstance {
            let item = try DICOMRetrieveItem(dataSet: dataSet)
            return DICOMReceivedInstance(
                sopClassUID: item.sopClassUID, sopInstanceUID: item.sopInstanceUID,
                transferSyntaxUID: item.transferSyntaxUID, payload: item.payload, moveOriginatorAETitle: nil,
                moveOriginatorMessageID: nil, sourceAETitle: "TEST")
        }
        let instance = try received(incomplete)
        let validDataSet = secondaryCaptureImage()
        _ = validDataSet.set(value: "1.2.826.0.1.3680043.10.1.4", forTagName: "SOPInstanceUID")
        let valid = try received(validDataSet)
        let context = DICOMwebRequestContext(baseURI: "/dicomweb")

        XCTAssertNil(DICOMIODValidationPolicy.off.report(for: instance))
        XCTAssertNil(DICOMIODValidationPolicy.warn.report(for: valid))
        XCTAssertEqual(DICOMIODValidationPolicy.warn.report(for: instance)?.findings.count, 1)

        let archive = DICOMDirectoryArchive(directory: directory)
        let rejecting = DICOMDirectoryArchiveServices(archive: archive, validation: .reject)
        let result = try await rejecting.store(instance, context: context)
        XCTAssertEqual(result, .failed(DICOMwebStoreResponse.dataSetDoesNotMatchSOPClass))
        let refused = await archive.record(instance.sopInstanceUID)
        XCTAssertNil(refused)
        let stored = try await rejecting.store(valid, context: context)
        XCTAssertEqual(stored, .stored)

        let warning = DICOMDirectoryArchiveServices(archive: archive, validation: .warn)
        let warned = try await warning.store(instance, context: context)
        XCTAssertEqual(warned, .storedWithWarning(DICOMwebStoreResponse.dataSetDoesNotMatchSOPClassWarning))
        let kept = await archive.record(instance.sopInstanceUID)
        XCTAssertNotNil(kept)
    }
}
