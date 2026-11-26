import XCTest
@testable import DcmSwift

/// Adding, removing and moving elements and Items (PS3.5 7.1, 7.5).
final class DcmSwiftDataSetStructureTests: XCTestCase {
    private let explicitLittle = "1.2.840.10008.1.2.1"

    private func dataSet() -> DataSet {
        let dataSet = DataSet()
        _ = dataSet.set(value: "SYNTHETIC^STRUCTURE", forTagName: "PatientName")
        _ = dataSet.set(value: "1.2.826.0.1.3680043.2.1125.9.1", forTagName: "SOPInstanceUID")
        return dataSet
    }

    private func roundTrip(_ dataSet: DataSet) throws -> DataSet {
        try DICOMDataSetCoding.decode(try DICOMDataSetCoding.encode(dataSet, transferSyntax: explicitLittle),
                                      transferSyntax: explicitLittle)
    }

    func testInsertKeepsTagOrderAndRefusesDuplicates() throws {
        let dataSet = dataSet()
        let id = try dataSet.makeElement(tag: DataTag(withGroup: "0010", element: "0020"))
        XCTAssertEqual(id.vr, .LO)
        try dataSet.insert(id)
        XCTAssertTrue(dataSet.set(value: "SYNTH-1", toElement: id))
        XCTAssertEqual(dataSet.datasetElements.map(\.name), ["SOPInstanceUID", "PatientName", "PatientID"])
        XCTAssertThrowsError(try dataSet.insert(try dataSet.makeElement(tag: DataTag(withGroup: "0010", element: "0020")))) {
            XCTAssertEqual($0 as? DataSetStructureError, .duplicate(tag: "(0010,0020)"))
        }
        let decoded = try roundTrip(dataSet)
        XCTAssertEqual(decoded.string(forTag: "PatientID"), "SYNTH-1")
        XCTAssertEqual(decoded.datasetElements.map(\.name), ["SOPInstanceUID", "PatientName", "PatientID"])
    }

    func testRefusedTags() {
        let dataSet = dataSet()
        XCTAssertThrowsError(try dataSet.makeElement(tag: DataTag(withGroup: "0002", element: "0010"))) {
            XCTAssertEqual($0 as? DataSetStructureError, .fileMetaInformation)
        }
        XCTAssertThrowsError(try dataSet.makeElement(tag: DataTag(withGroup: "0010", element: "0000"))) {
            XCTAssertEqual($0 as? DataSetStructureError, .groupLength)
        }
        XCTAssertThrowsError(try dataSet.makeElement(tag: DataTag(withGroup: "fffe", element: "e000"))) {
            XCTAssertEqual($0 as? DataSetStructureError, .itemOrDelimiter)
        }
        // A private tag the dictionary does not know: UN, or the VR given.
        XCTAssertEqual(try dataSet.makeElement(tag: DataTag(withGroup: "0009", element: "1001")).vr, .UN)
        XCTAssertEqual(try dataSet.makeElement(tag: DataTag(withGroup: "0009", element: "1001"), vr: .LO).vr, .LO)
    }

    func testRemoveAndPutBack() throws {
        let dataSet = dataSet()
        let name = try XCTUnwrap(dataSet.element(forTagName: "PatientName"))
        let container = try dataSet.removeElement(name)
        XCTAssertNil(container)
        XCTAssertNil(dataSet.element(forTagName: "PatientName"))
        XCTAssertNil(try roundTrip(dataSet).string(forTag: "PatientName"))
        try dataSet.insert(name, into: container)
        XCTAssertEqual(try roundTrip(dataSet).string(forTag: "PatientName"), "SYNTHETIC^STRUCTURE")
        XCTAssertThrowsError(try dataSet.removeElement(DataElement(withTag: DataTag(withGroup: "0010", element: "0040")))) {
            XCTAssertEqual($0 as? DataSetStructureError, .notFound)
        }
    }

    func testSequenceItemsAndNestedElements() throws {
        let dataSet = dataSet()
        // Referenced Series Sequence (0008,1115), two Items, an element in each.
        let sequence = try XCTUnwrap(try dataSet.makeElement(tag: DataTag(withGroup: "0008", element: "1115")) as? DataSequence)
        try dataSet.insert(sequence)
        let first = try dataSet.insertItem(into: sequence, at: 0)
        let second = try dataSet.insertItem(into: sequence, at: 1)
        for (item, uid) in [(first, "1.2.3.1"), (second, "1.2.3.2")] {
            let element = try dataSet.makeElement(tag: DataTag(withGroup: "0020", element: "000e"), in: item)
            try dataSet.insert(element, into: item)
            XCTAssertTrue(dataSet.set(value: uid, toElement: element))
        }
        func uids(_ dataSet: DataSet) throws -> [String] {
            let sequence = try XCTUnwrap(dataSet.sequence(forTagName: "ReferencedSeriesSequence"))
            return sequence.items.compactMap { $0.element(withName: "SeriesInstanceUID")?.textValues?.first }
        }
        XCTAssertEqual(try uids(roundTrip(dataSet)), ["1.2.3.1", "1.2.3.2"])

        // Moved: the order of Items is kept on the wire.
        try dataSet.moveItem(in: sequence, from: 0, to: 1)
        XCTAssertEqual(try uids(roundTrip(dataSet)), ["1.2.3.2", "1.2.3.1"])
        XCTAssertThrowsError(try dataSet.moveItem(in: sequence, from: 0, to: 2))

        // A nested element removed and put back in its Item.
        let nested = try XCTUnwrap(first.element(withName: "SeriesInstanceUID"))
        let item = try dataSet.removeElement(nested)
        XCTAssertTrue(item === first)
        XCTAssertEqual(try uids(roundTrip(dataSet)), ["1.2.3.2"])
        try dataSet.insert(nested, into: item)

        // An Item removed and put back where it was.
        let (owner, index) = try dataSet.removeItem(second)
        XCTAssertTrue(owner === sequence)
        XCTAssertEqual(index, 0)
        XCTAssertEqual(try uids(roundTrip(dataSet)), ["1.2.3.1"])
        try dataSet.insertItem(second, into: owner, at: index)
        XCTAssertEqual(try uids(roundTrip(dataSet)), ["1.2.3.2", "1.2.3.1"])

        // An empty Item and an empty Sequence survive the round trip.
        try dataSet.insertItem(into: sequence, at: 2)
        XCTAssertEqual(try roundTrip(dataSet).sequence(forTagName: "ReferencedSeriesSequence")?.items.count, 3)
    }

    func testSpecificCharacterSetFollowsInsertAndRemove() throws {
        let dataSet = dataSet()
        let charset = try dataSet.makeElement(tag: DataTag(withGroup: "0008", element: "0005"))
        try dataSet.insert(charset)
        XCTAssertTrue(dataSet.set(value: "ISO_IR 192", toElement: charset))
        XCTAssertEqual(dataSet.characterSet, DICOMCharacterSet(specificCharacterSet: "ISO_IR 192"))
        try dataSet.removeElement(charset)
        XCTAssertEqual(dataSet.characterSet, DICOMCharacterSet(specificCharacterSet: nil))
    }
}
