import XCTest
@testable import DcmSwift

final class DcmSwiftPersonNameTests: XCTestCase {
    func testPersonNameExposesNamedComponentsAndRepresentations() throws {
        let name = try XCTUnwrap(DICOMPersonName(
            rawValue: "Adams^John Robert Quincy^^Rev.^B.A. M.Div.=山田^太郎=やまだ^たろう"))

        XCTAssertEqual(name.alphabetic?.familyName, "Adams")
        XCTAssertEqual(name.alphabetic?.givenName, "John Robert Quincy")
        XCTAssertNil(name.alphabetic?.middleName)
        XCTAssertEqual(name.alphabetic?.namePrefix, "Rev.")
        XCTAssertEqual(name.alphabetic?.nameSuffix, "B.A. M.Div.")
        XCTAssertEqual(name.ideographic?.familyName, "山田")
        XCTAssertEqual(name.ideographic?.givenName, "太郎")
        XCTAssertEqual(name.phonetic?.familyName, "やまだ")
        XCTAssertEqual(name.rawValue, "Adams^John Robert Quincy^^Rev.^B.A. M.Div.=山田^太郎=やまだ^たろう")
    }

    func testAbsentGroupsAndInteriorComponentsRoundTripCanonically() throws {
        let name = try XCTUnwrap(DICOMPersonName(rawValue: "=王^小東=わん^^太郎"))
        XCTAssertNil(name.alphabetic)
        XCTAssertEqual(name.ideographic?.familyName, "王")
        XCTAssertEqual(name.phonetic?.middleName, "太郎")
        XCTAssertEqual(name.rawValue, "=王^小東=わん^^太郎")
        XCTAssertNil(DICOMPersonName(rawValue: "A=B=C=D"))
        XCTAssertNil(DICOMPersonName(rawValue: "A^B^C^D^E^F"))
    }

    func testDatasetPersonNameConvenienceRoundTripsMultipleUTF8Values() throws {
        let dataset = DataSet()
        XCTAssertNotNil(dataset.set(value: "ISO_IR 192", forTagName: "SpecificCharacterSet"))
        let names = [
            DICOMPersonName(familyName: "Doe", givenName: "Jane", namePrefix: "Dr."),
            DICOMPersonName(
                alphabetic: .init(familyName: "Wang", givenName: "XiaoDong"),
                ideographic: .init(familyName: "王", givenName: "小東"))
        ]

        let element = try XCTUnwrap(dataset.set(personNames: names, forTagName: "PatientName"))
        XCTAssertEqual(element.personNames, names)
        XCTAssertEqual(dataset.personNames(forTag: "PatientName"), names)
        XCTAssertEqual(element.valueMultiplicity, 2)
        XCTAssertEqual(element.textValues, names.map(\.rawValue))

        let encoded = dataset.toData(vrMethod: .Explicit, byteOrder: .LittleEndian)
        let decoded = try XCTUnwrap(try DicomInputStream(data: encoded).readDataset(enforceVR: false))
        XCTAssertEqual(decoded.personNames(forTag: "PatientName"), names)
    }

    func testMultiValuedTextPreservesEmptyValuesAndRejectsEmbeddedDelimiter() throws {
        let dataset = DataSet()
        XCTAssertNotNil(dataset.set(value: "ISO_IR 192", forTagName: "SpecificCharacterSet"))
        let element = try XCTUnwrap(dataset.set(
            textValues: ["alpha", "", "山田"], forTagName: "OtherPatientIDs"))

        XCTAssertEqual(element.textValues, ["alpha", "", "山田"])
        XCTAssertEqual(dataset.textValues(forTag: "OtherPatientIDs"), ["alpha", "", "山田"])
        XCTAssertEqual(element.valueMultiplicity, 3)
        XCTAssertFalse(element.setTextValues(["one\\two"]))
        XCTAssertEqual(element.textValues, ["alpha", "", "山田"])
    }

    func testSingleValuedLongTextRetainsBackslashes() throws {
        let dataset = DataSet()
        let element = try XCTUnwrap(dataset.set(
            textValues: ["left\\right"], forTagName: "AdditionalPatientHistory"))
        XCTAssertEqual(element.vr, .LT)
        XCTAssertEqual(element.textValues, ["left\\right"])
        XCTAssertEqual(element.valueMultiplicity, 1)
        XCTAssertFalse(element.isMultiple)
        XCTAssertNil(dataset.set(textValues: ["one", "two"], forTagName: "AdditionalPatientHistory"))
    }

    func testInvalidStructuredNameIsRejectedWithoutChangingTheElement() throws {
        let dataset = DataSet()
        let element = try XCTUnwrap(dataset.set(
            personNames: [DICOMPersonName(alphabetic: .init(familyName: "Valid", givenName: "Name"))],
            forTagName: "PatientName"))
        let invalid = DICOMPersonName(alphabetic: .init(familyName: "Invalid^Family"))
        XCTAssertFalse(element.setPersonNames([invalid]))
        XCTAssertEqual(element.personNames?.first?.alphabetic?.familyName, "Valid")
    }
}
