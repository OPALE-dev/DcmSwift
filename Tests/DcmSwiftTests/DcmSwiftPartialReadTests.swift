import XCTest
@testable import DcmSwift

/// Reading a malformed data set as far as possible, as pydicom does with a
/// truncated file (Scripts/crosscheck/pydicom_partial.py).
final class DcmSwiftPartialReadTests: XCTestCase {
    typealias Writer = DcmSwiftFuzzTests.Writer

    private func basic(_ writer: inout Writer) {
        writer.text(0x0008, 0x0016, "UI", "1.2.840.10008.5.1.4.1.1.7")
        writer.text(0x0010, 0x0010, "PN", "Doe^Jane")
    }

    private func part10(_ writer: Writer) -> [UInt8] {
        DcmSwiftFuzzTests.part10(transferSyntax: TransferSyntax.explicitVRLittleEndian, dataSet: writer.bytes)
    }

    func testCompleteDataSetHasNoFailure() throws {
        var writer = Writer()
        basic(&writer)
        let stream = DicomInputStream(data: Data(part10(writer)))
        let (dataSet, failure) = stream.readPartialDataset()

        XCTAssertNil(failure)
        XCTAssertNil(stream.readFailure)
        XCTAssertFalse(dataSet.isCorrupted)
        XCTAssertEqual(dataSet.string(forTag: "PatientName"), "Doe^Jane")
    }

    func testElementsBeforeAnOverflowingLengthAreKept() throws {
        var writer = Writer()
        basic(&writer)
        writer.header(0x0010, 0x0020, "LO", 400)
        writer.bytes += Array("SHORT".utf8) + [0x20]
        let bytes = part10(writer)

        XCTAssertThrowsError(try DicomInputStream(data: Data(bytes)).readDataset())
        let (dataSet, failure) = DicomInputStream(data: Data(bytes)).readPartialDataset()

        let unwrapped = try XCTUnwrap(failure)
        XCTAssertEqual(unwrapped.tag, "00100020")
        XCTAssertTrue(unwrapped.message.contains("overflows"), unwrapped.message)
        // The reader stopped after the element header.
        XCTAssertEqual(unwrapped.offset, bytes.count - 6)
        XCTAssertTrue(dataSet.isCorrupted)
        XCTAssertEqual(dataSet.string(forTag: "TransferSyntaxUID"), TransferSyntax.explicitVRLittleEndian)
        XCTAssertEqual(dataSet.string(forTag: "SOPClassUID"), "1.2.840.10008.5.1.4.1.1.7")
        XCTAssertEqual(dataSet.string(forTag: "PatientName"), "Doe^Jane")
        XCTAssertNil(dataSet.element(forTagName: "PatientID"))
    }

    func testSequenceKeepsItsItemsBeforeTheFailure() throws {
        var writer = Writer()
        writer.text(0x0008, 0x0016, "UI", "1.2.840.10008.5.1.4.1.1.7")
        // An undefined-length Sequence whose second Item is never started:
        // the data set goes on without Sequence Delimitation Item.
        writer.header(0x0008, 0x1115, "SQ", 0xFFFF_FFFF)
        writer.header(0xFFFE, 0xE000, "", 0xFFFF_FFFF)
        writer.text(0x0020, 0x000E, "UI", "1.2.3")
        writer.header(0xFFFE, 0xE00D, "", 0)
        writer.text(0x0010, 0x0010, "PN", "Doe^Jane")
        let (dataSet, failure) = DicomInputStream(data: Data(part10(writer))).readPartialDataset()

        let unwrapped = try XCTUnwrap(failure)
        XCTAssertTrue(unwrapped.message.contains("expected Item tag"), unwrapped.message)
        let sequence = try XCTUnwrap(dataSet.element(forTagName: "ReferencedSeriesSequence") as? DataSequence)
        XCTAssertEqual(sequence.items.count, 1)
        XCTAssertEqual(sequence.items.first?.elements.first?.value as? String, "1.2.3")
        XCTAssertEqual(dataSet.string(forTag: "SOPClassUID"), "1.2.840.10008.5.1.4.1.1.7")
    }

    func testUnsupportedTransferSyntaxKeepsTheFileMetaInformation() throws {
        var writer = Writer()
        basic(&writer)
        let bytes = DcmSwiftFuzzTests.part10(transferSyntax: "1.2.3.4.5.6", dataSet: writer.bytes)
        let (dataSet, failure) = DicomInputStream(data: Data(bytes)).readPartialDataset()

        XCTAssertEqual(failure?.message, "Unsupported Transfer Syntax 1.2.3.4.5.6")
        XCTAssertNotNil(dataSet.element(forTagName: "FileMetaInformationVersion"))
        XCTAssertNil(dataSet.element(forTagName: "PatientName"))
    }

    func testOnlyTheFirstFailureIsKept() throws {
        var writer = Writer()
        basic(&writer)
        writer.header(0x0010, 0x0020, "LO", 400)
        let stream = DicomInputStream(data: Data(part10(writer)))
        let first = stream.readPartialDataset().failure
        XCTAssertEqual(stream.readFailure, first)
        XCTAssertEqual(first?.tag, "00100020")
    }

    func testTolerantFileKeepsThePartialDataSet() throws {
        var writer = Writer()
        basic(&writer)
        writer.header(0x0010, 0x0020, "LO", 400)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("partial-\(UUID().uuidString).dcm")
        try Data(part10(writer)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNil(DicomFile(forPath: url.path))
        let file = try DicomFile(tolerantlyReadingPath: url.path)
        XCTAssertEqual(file.readFailure?.tag, "00100020")
        XCTAssertTrue(file.isCorrupted())
        XCTAssertTrue(file.hasPreamble)
        XCTAssertEqual(file.dataset.string(forTag: "PatientName"), "Doe^Jane")

        XCTAssertThrowsError(try DicomFile(tolerantlyReadingPath: url.path + ".missing")) { error in
            XCTAssertEqual((error as? DicomReadFailure)?.message, "No such file")
        }
    }

    func testFailureDescriptionGivesTheStopOffset() {
        let failure = DicomReadFailure(offset: 864, tag: "312E3631", message: "Fatal, invalid header")
        XCTAssertEqual(failure.tag, "312e3631")
        XCTAssertEqual(failure.description, "Fatal, invalid header (reading stopped at offset 864)")
    }
}
