import XCTest
@testable import DcmSwift

/// De-identification with the Basic Application Level Confidentiality
/// Profile of PS3.15 Annex E.
final class DcmSwiftDeidentificationTests: XCTestCase {
    private let key = Data("a secret shared by the instances of a study".utf8)

    /// A Secondary Capture Image with identifying attributes, a reference to
    /// another instance, and private attributes.
    private func identifiedImage() throws -> DataSet {
        let dataSet = DcmSwiftIODValidationTests.secondaryCaptureImage()
        _ = dataSet.set(value: "MAIN HOSPITAL", forTagName: "InstitutionName")
        _ = dataSet.set(value: "CT01", forTagName: "StationName")
        _ = dataSet.set(value: "A12345", forTagName: "AccessionNumber")
        _ = dataSet.set(value: "19700101", forTagName: "PatientBirthDate")
        _ = dataSet.set(value: "Followed since 2019", forTagName: "PatientComments")

        // Referenced Instance Sequence, not listed in Table E.1-1, holds a
        // Referenced SOP Instance UID, which is.
        let sequence = DataSequence(withTag: try XCTUnwrap(DicomSpec.shared.dataTag(forName: "ReferencedInstanceSequence")))
        sequence.vr = .SQ
        sequence.length = -1
        let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
        item.length = -1
        for (name, value) in [("ReferencedSOPClassUID", DcmSwiftIODValidationTests.secondaryCapture),
                              ("ReferencedSOPInstanceUID", "1.2.826.0.1.3680043.10.1.9")] {
            let element = try XCTUnwrap(DataElement(withTagName: name, dataset: dataSet, parent: item))
            element.vr = .UI
            XCTAssertTrue(element.setValue(value))
            item.elements.append(element)
        }
        sequence.items.append(item)
        dataSet.add(element: sequence)

        // A safe private attribute of Table E.3.10-1, (7053,xx09) of the
        // Philips PET Private Group, and an unsafe one in the same block.
        func add(_ group: String, _ element: String, _ vr: VR.VR, _ value: String) {
            let attribute = DataElement(withTag: DataTag(withGroup: group, element: element), dataset: dataSet)
            attribute.vr = vr
            XCTAssertTrue(attribute.setValue(value))
            dataSet.add(element: attribute)
        }
        add("7053", "0010", .LO, "Philips PET Private Group")
        add("7053", "1009", .DS, "1.5")
        add("7053", "1077", .LO, "Jane Doe")
        dataSet.sortElements()
        return dataSet
    }

    private func value(_ dataSet: DataSet, _ name: String) -> String? {
        dataSet.element(forTagName: name).map { $0.textValues?.first ?? "" }
    }

    func testProfileIsReadFromPS3_15() throws {
        let profile = DICOMDeidentificationProfile.shared
        XCTAssertEqual(profile.edition, "2026d")
        XCTAssertEqual(profile.rules.count, 657)
        XCTAssertEqual(profile.safePrivateAttributes.count, 479)
        XCTAssertEqual(profile.rule(for: "00100010")?.basic, .zero)
        XCTAssertEqual(profile.rule(for: "0020000D")?.basic, .replaceUID)
        XCTAssertEqual(profile.rule(for: "0020000D")?.options["retainUIDs"], .keep)
        XCTAssertEqual(profile.rule(for: "00080080")?.basic, .removeOrZeroOrDummy)
        // Repeating groups: Curve Data (50xx,xxxx), Overlay Data (60xx,3000).
        XCTAssertEqual(profile.rule(for: "50120000")?.name, "Curve Data")
        XCTAssertEqual(profile.rule(for: "60023000")?.name, "Overlay Data")
        XCTAssertEqual(profile.privateRule?.basic, .remove)
        XCTAssertTrue(profile.isSafePrivate(group: "7053", element: "09", creator: "Philips PET Private Group"))
        XCTAssertFalse(profile.isSafePrivate(group: "7053", element: "77", creator: "Philips PET Private Group"))
    }

    func testBasicProfile() throws {
        let dataSet = try identifiedImage()
        let findingsBefore = DICOMIODValidator().validate(dataSet).findings.map(\.path)
        let deidentifier = try DICOMDeidentifier(key: key)
        let report = deidentifier.deidentify(dataSet)

        // Z: emptied; X/Z/D: removed when the IOD makes the attribute
        // Type 3, as Station Name and Institution Name in this IOD.
        XCTAssertEqual(value(dataSet, "PatientName"), "")
        XCTAssertEqual(value(dataSet, "PatientID"), "")
        XCTAssertEqual(value(dataSet, "AccessionNumber"), "")
        XCTAssertEqual(value(dataSet, "PatientBirthDate"), "")
        XCTAssertNil(dataSet.element(forTagName: "StationName"))
        XCTAssertNil(dataSet.element(forTagName: "InstitutionName"))
        XCTAssertNil(dataSet.element(forTagName: "PatientComments"))
        // U: replaced consistently, here and in Sequence Items.
        let study = deidentifier.replacementUID(for: "1.2.826.0.1.3680043.10.1.2")
        XCTAssertEqual(value(dataSet, "StudyInstanceUID"), study)
        XCTAssertTrue(study.hasPrefix("2.25.") && study.count <= 64, study)
        let item = try XCTUnwrap(dataSet.sequence(forTagName: "ReferencedInstanceSequence")?.items.first)
        XCTAssertEqual(item.element(withName: "ReferencedSOPInstanceUID")?.textValues,
                       [deidentifier.replacementUID(for: "1.2.826.0.1.3680043.10.1.9")])
        XCTAssertEqual(item.element(withName: "ReferencedSOPClassUID")?.textValues, [DcmSwiftIODValidationTests.secondaryCapture])
        // Private attributes go, Private Creators too.
        XCTAssertFalse(dataSet.allElements.contains { $0.group == "7053" })
        // The method is recorded (PS3.15 E.1.1).
        XCTAssertEqual(value(dataSet, "PatientIdentityRemoved"), "YES")
        XCTAssertEqual(value(dataSet, "LongitudinalTemporalInformationModified"), "REMOVED")
        let codes = dataSet.sequence(forTagName: "DeidentificationMethodCodeSequence")?.items
            .compactMap { DICOMCode(item: $0) }
        XCTAssertEqual(codes?.map(\.value), ["113100"])
        XCTAssertEqual(codes?.first?.meaning, "Basic Application Confidentiality Profile")
        XCTAssertGreaterThan(report.count(of: .remove), 0)

        // The same key gives the same UIDs, another key others.
        let again = try identifiedImage()
        try DICOMDeidentifier(key: key).deidentify(again)
        XCTAssertEqual(value(again, "StudyInstanceUID"), study)
        let other = try identifiedImage()
        try DICOMDeidentifier(key: Data("another secret".utf8)).deidentify(other)
        XCTAssertNotEqual(value(other, "StudyInstanceUID"), study)

        // De-identification adds no IOD finding: dummy values for Type 1,
        // empty values for Type 2.
        let findings = DICOMIODValidator().validate(dataSet).findings
        XCTAssertTrue(Set(findings.map(\.path)).isSubset(of: Set(findingsBefore)),
                      findings.map(\.description).joined(separator: "\n"))
    }

    func testOptions() throws {
        let retained = try identifiedImage()
        try DICOMDeidentifier(options: [.retainUIDs, .retainSafePrivate, .retainInstitutionIdentity,
                                        .retainLongitudinalFullDates], key: key).deidentify(retained)
        XCTAssertEqual(value(retained, "StudyInstanceUID"), "1.2.826.0.1.3680043.10.1.2")
        XCTAssertEqual(value(retained, "InstitutionName"), "MAIN HOSPITAL")
        XCTAssertEqual(value(retained, "StudyDate"), "20261008")
        XCTAssertEqual(value(retained, "LongitudinalTemporalInformationModified"), "UNMODIFIED")
        // The safe private attribute stays with its Private Creator; the
        // unsafe one goes.
        let privateTags = retained.allElements.filter { $0.group == "7053" }.map { $0.tagCode().uppercased() }
        XCTAssertEqual(privateTags, ["70530010", "70531009"])
        let codes = retained.sequence(forTagName: "DeidentificationMethodCodeSequence")?.items
            .compactMap { DICOMCode(item: $0)?.value }
        XCTAssertEqual(Set(codes ?? []), ["113100", "113110", "113111", "113112", "113106"])

        // Modified dates are shifted by the same number of days.
        let shifted = try identifiedImage()
        try DICOMDeidentifier(options: [.retainLongitudinalModifiedDates], key: key, dateShift: -10).deidentify(shifted)
        XCTAssertEqual(value(shifted, "StudyDate"), "20260928")
        XCTAssertEqual(value(shifted, "LongitudinalTemporalInformationModified"), "MODIFIED")

        XCTAssertThrowsError(try DICOMDeidentifier(options: [.retainLongitudinalFullDates, .retainLongitudinalModifiedDates]))
    }

    func testCleanActionsUseTheCleaner() throws {
        // Clean Descriptors: Patient Comments is X in the Basic Profile, C
        // with the option; without a cleaner, the Basic Profile applies.
        let withoutCleaner = try identifiedImage()
        try DICOMDeidentifier(options: [.cleanDescriptors], key: key).deidentify(withoutCleaner)
        XCTAssertNil(withoutCleaner.element(forTagName: "PatientComments"))

        let cleaned = try identifiedImage()
        var deidentifier = try DICOMDeidentifier(options: [.cleanDescriptors], key: key)
        deidentifier.cleaner = { element in
            guard element.name == "PatientComments" else { return false }
            return element.setValue("Followed for years")
        }
        deidentifier.deidentify(cleaned)
        XCTAssertEqual(value(cleaned, "PatientComments"), "Followed for years")
    }

    func testFileMetaInformationIsReplaced() throws {
        let dataSet = try identifiedImage()
        let meta = try XCTUnwrap(DataElement(withTagName: "SourceApplicationEntityTitle", dataset: dataSet))
        meta.vr = .AE
        XCTAssertTrue(meta.setValue("HOSPITAL_PACS"))
        dataSet.add(element: meta)
        _ = dataSet.set(value: "1.2.826.0.1.3680043.10.1.1", forTagName: "MediaStorageSOPInstanceUID")
        _ = dataSet.set(value: TransferSyntax.explicitVRLittleEndian, forTagName: "TransferSyntaxUID")
        let deidentifier = try DICOMDeidentifier(key: key)
        deidentifier.deidentify(dataSet)
        XCTAssertNil(dataSet.element(forTagName: "SourceApplicationEntityTitle"))
        XCTAssertEqual(value(dataSet, "MediaStorageSOPInstanceUID"), value(dataSet, "SOPInstanceUID"))
        XCTAssertEqual(value(dataSet, "MediaStorageSOPInstanceUID"), deidentifier.replacementUID(for: "1.2.826.0.1.3680043.10.1.1"))
        XCTAssertEqual(value(dataSet, "ImplementationClassUID"), DICOMImplementation.classUID)
    }

    func testReplacementUIDDigits() {
        XCTAssertEqual(DICOMDeidentifier.decimal([0x01, 0x00]), "256")
        XCTAssertEqual(DICOMDeidentifier.decimal([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                                                  0xFF, 0xFF, 0xFF, 0xFF]), "340282366920938463463374607431768211455")
        XCTAssertEqual(DICOMDeidentifier.decimal([0, 0]), "0")
    }
}
