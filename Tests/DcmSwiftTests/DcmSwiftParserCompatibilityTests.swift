import XCTest
import CZlib
@testable import DcmSwift

/// Files other toolkits read and DcmSwift once did not, found by comparing
/// with pydicom (Scripts/crosscheck/pydicom_json.py) and by fuzzing.
final class DcmSwiftParserCompatibilityTests: XCTestCase {
    typealias Writer = DcmSwiftFuzzTests.Writer

    private func read(_ bytes: [UInt8]) throws -> DataSet {
        try XCTUnwrap(try DicomInputStream(data: Data(bytes)).readDataset(enforceVR: false))
    }

    private func basic(_ writer: inout Writer) {
        writer.text(0x0008, 0x0016, "UI", "1.2.840.10008.5.1.4.1.1.7")
        writer.text(0x0010, 0x0010, "PN", "Doe^Jane")
    }

    func testPreambleContentIsFree() throws {
        // PS3.10 7.1: a dual-format file may start with a TIFF header.
        var writer = Writer()
        basic(&writer)
        var bytes = DcmSwiftFuzzTests.part10(transferSyntax: TransferSyntax.explicitVRLittleEndian, dataSet: writer.bytes)
        bytes.replaceSubrange(0..<4, with: [0x49, 0x49, 0x2A, 0x00])
        let dataSet = try read(bytes)
        XCTAssertTrue(dataSet.hasPreamble)
        XCTAssertEqual(dataSet.string(forTag: "PatientName"), "Doe^Jane")
    }

    func testImplicitDataSetLabelledExplicitIsRead() throws {
        var writer = Writer(explicit: false)
        basic(&writer)
        writer.us(0x0028, 0x0010, [4])
        let bytes = DcmSwiftFuzzTests.part10(transferSyntax: TransferSyntax.explicitVRLittleEndian, dataSet: writer.bytes)
        let dataSet = try read(bytes)
        XCTAssertEqual(dataSet.vrMethod, .Implicit)
        XCTAssertEqual(dataSet.string(forTag: "PatientName"), "Doe^Jane")
        XCTAssertEqual(dataSet.unsignedInteger16(forTag: "Rows"), 4)
        // A genuine Explicit VR data set is unaffected.
        var explicit = Writer()
        basic(&explicit)
        XCTAssertEqual(try read(DcmSwiftFuzzTests.part10(
            transferSyntax: TransferSyntax.explicitVRLittleEndian, dataSet: explicit.bytes)).vrMethod, .Explicit)
    }

    func testUndefinedLengthUnknownElementsAreSequences() throws {
        // Explicit UN of undefined length (PS3.5 6.2.2), its Items in
        // Implicit VR, and an unknown private element in Implicit VR.
        func items(_ writer: inout Writer) {
            writer.header(0xFFFE, 0xE000, "", 0xFFFF_FFFF)
            var inner = Writer(explicit: false)
            inner.text(0x0008, 0x0100, "SH", "113691")
            writer.bytes += inner.bytes
            writer.header(0xFFFE, 0xE00D, "", 0)
            writer.header(0xFFFE, 0xE0DD, "", 0)
        }
        var explicit = Writer()
        basic(&explicit)
        explicit.header(0x0018, 0x9346, "UN", 0xFFFF_FFFF)
        items(&explicit)
        explicit.text(0x0020, 0x0013, "IS", "1")
        let first = try read(DcmSwiftFuzzTests.part10(
            transferSyntax: TransferSyntax.explicitVRLittleEndian, dataSet: explicit.bytes))
        let sequence = try XCTUnwrap(first.allElements.first { $0.tagCode() == "00189346" } as? DataSequence)
        XCTAssertEqual(sequence.vr, .SQ)
        XCTAssertEqual(sequence.items.first?.elements.first?.value as? String, "113691")
        XCTAssertEqual(first.string(forTag: "InstanceNumber"), "1")

        var implicit = Writer(explicit: false)
        basic(&implicit)
        implicit.header(0x0001, 0x1001, "", 0xFFFF_FFFF)
        items(&implicit)
        implicit.us(0x0028, 0x0010, [8])
        let second = try read(DcmSwiftFuzzTests.part10(
            transferSyntax: TransferSyntax.implicitVRLittleEndian, dataSet: implicit.bytes))
        XCTAssertTrue(second.allElements.first { $0.tagCode() == "00011001" } is DataSequence)
        XCTAssertEqual(second.unsignedInteger16(forTag: "Rows"), 8)
    }

    func testImplicitVRResolvesAmbiguousVRs() throws {
        var writer = Writer(explicit: false)
        basic(&writer)
        writer.us(0x0028, 0x0103, [1])
        writer.header(0x0028, 0x0106, "", 2)
        writer.u16(0xFFFE)
        writer.header(0x7FE0, 0x0010, "", 4)
        writer.bytes += [1, 0, 2, 0]
        let dataSet = try read(DcmSwiftFuzzTests.part10(
            transferSyntax: TransferSyntax.implicitVRLittleEndian, dataSet: writer.bytes))
        // Signed with Pixel Representation 1; Pixel Data is OW (PS3.5 A.1).
        XCTAssertEqual(dataSet.element(forTagName: "SmallestImagePixelValue")?.vr, .SS)
        XCTAssertEqual(dataSet.integer16(forTag: "SmallestImagePixelValue"), -2)
        XCTAssertEqual(dataSet.element(forTagName: "PixelData")?.vr, .OW)
    }

    func testDeflatedStreamWithAGzipTrailer() throws {
        var writer = Writer()
        basic(&writer)
        let inflated = Data(writer.bytes)
        var compressed = [UInt8](try DICOMDeflate.compress(inflated))
        let checksum = inflated.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count))) }
        let trailer = (0..<4).map { UInt8(truncatingIfNeeded: checksum >> (8 * $0)) }
            + (0..<4).map { UInt8(truncatingIfNeeded: UInt32(inflated.count) >> (8 * $0)) }
        let syntax = TransferSyntax.deflatedExplicitVRLittleEndian
        XCTAssertEqual(try read(DcmSwiftFuzzTests.part10(transferSyntax: syntax, dataSet: compressed + trailer))
            .string(forTag: "PatientName"), "Doe^Jane")
        // Anything else after the stream is still refused.
        compressed += [1, 2, 3, 4, 5, 6, 7, 8]
        XCTAssertThrowsError(try DicomInputStream(data: Data(DcmSwiftFuzzTests.part10(
            transferSyntax: syntax, dataSet: compressed))).readDataset(enforceVR: false))
    }

    func testTrailingBytesShorterThanATagEndTheDataSet() throws {
        var writer = Writer()
        basic(&writer)
        for extra in 1...3 {
            let bytes = DcmSwiftFuzzTests.part10(
                transferSyntax: TransferSyntax.explicitVRLittleEndian,
                dataSet: writer.bytes + [UInt8](repeating: 0, count: extra))
            XCTAssertEqual(try read(bytes).string(forTag: "PatientName"), "Doe^Jane", "\(extra) bytes")
        }
    }

    func testDataSetsWithoutFileMetaInformationAreDetected() throws {
        for (explicit, bigEndian) in [(true, false), (true, true), (false, false)] {
            var writer = Writer(explicit: explicit, bigEndian: bigEndian)
            basic(&writer)
            writer.us(0x0028, 0x0010, [512])
            // Long enough for the 132 bytes probed for a preamble.
            writer.text(0x0028, 0x0004, "CS", "MONOCHROME2")
            writer.text(0x0040, 0xA160, "UT", String(repeating: "x", count: 120))
            let dataSet = try XCTUnwrap(try DicomInputStream(data: Data(writer.bytes)).readDataset())
            XCTAssertFalse(dataSet.hasPreamble)
            XCTAssertEqual(dataSet.string(forTag: "PatientName"), "Doe^Jane", "\(explicit) \(bigEndian)")
            XCTAssertEqual(dataSet.unsignedInteger16(forTag: "Rows"), 512, "\(explicit) \(bigEndian)")
        }
    }
}
