import XCTest
@testable import DcmSwift

/// Values DcmSwift does not understand are written back byte for byte.
final class DcmSwiftBytePreservationTests: XCTestCase {
    typealias Writer = DcmSwiftFuzzTests.Writer

    /// Elements whose semantics DcmSwift cannot or need not decode.
    private func unusual(_ writer: inout Writer) {
        writer.text(0x0008, 0x0005, "CS", "ISO_IR 100")
        // A retired element.
        writer.text(0x0008, 0x0010, "SH", "RECOGNITION")
        writer.text(0x0008, 0x0016, "UI", "1.2.840.10008.5.1.4.1.1.7")
        // A Latin-1 name, with an unusual NUL padding.
        writer.text(0x0010, 0x0010, "PN", [0x4D, 0xFC, 0x6C, 0x6C, 0x65, 0x72, 0x00])
        // Bytes invalid in ISO_IR 100 (C1 control area) in a LO.
        writer.text(0x0010, 0x0020, "LO", [0x41, 0x81, 0x9F, 0x42])
        // Non-standard padding between Values.
        writer.text(0x0018, 0x1020, "LO", "V1 \\V2  ")
        // An unknown odd-group element, as UN.
        writer.header(0x0019, 0x0001, "UN", 2)
        writer.bytes += [0xFF, 0x00]
        // A private block: creator, a value of unknown VR, binary data, and
        // a Sequence of defined length holding an UN value.
        writer.text(0x0029, 0x0010, "LO", "ACME 1.0")
        writer.header(0x0029, 0x1001, "UN", 6)
        writer.bytes += [1, 2, 3, 4, 5, 6]
        writer.header(0x0029, 0x1002, "OB", 4)
        writer.bytes += [0xDE, 0xAD, 0xBE, 0xEF]
        writer.sequence(0x0029, 0x1003, undefined: false, items: [{ item in
            item.text(0x0029, 0x0010, "LO", "ACME 1.0")
            item.header(0x0029, 0x1010, "UN", 2)
            item.bytes += [0xAB, 0xCD]
        }])
    }

    func testUnderstoodAndUnknownValuesAreWrittenUnchanged() throws {
        for syntax in [TransferSyntax.explicitVRLittleEndian, TransferSyntax.explicitVRBigEndian] {
            var writer = Writer(explicit: true, bigEndian: syntax == TransferSyntax.explicitVRBigEndian)
            unusual(&writer)
            let source = Data(writer.bytes)
            let dataSet = try DICOMDataSetCoding.decode(source, transferSyntax: syntax)
            let written = try DICOMDataSetCoding.encode(dataSet, transferSyntax: syntax)
            XCTAssertEqual([UInt8](written), [UInt8](source), syntax)
        }
    }

    func testPart10FilesAreWrittenUnchanged() throws {
        var writer = Writer()
        unusual(&writer)
        let source = DcmSwiftFuzzTests.part10(transferSyntax: TransferSyntax.explicitVRLittleEndian, dataSet: writer.bytes)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(source).write(to: url)
        let file = try XCTUnwrap(DicomFile(forPath: url.path))
        let copy = url.appendingPathExtension("copy")
        defer { try? FileManager.default.removeItem(at: copy) }
        XCTAssertTrue(file.write(atPath: copy.path))
        let rewritten = [UInt8](try Data(contentsOf: copy))
        // The data set after the File Meta Information is unchanged.
        XCTAssertEqual(Array(rewritten.suffix(writer.bytes.count)), writer.bytes)
    }

    private func rewrite(_ bytes: [UInt8]) throws -> [UInt8] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-\(UUID().uuidString).dcm")
        let copy = url.appendingPathExtension("copy")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: copy)
        }
        try Data(bytes).write(to: url)
        let file = try XCTUnwrap(DicomFile(forPath: url.path))
        XCTAssertTrue(file.write(atPath: copy.path))
        return [UInt8](try Data(contentsOf: copy))
    }

    func testPreambleAndFileMetaOrderAreKept() throws {
        // A dual-format file's TIFF preamble, and elements of the illegal
        // group 0001 that sort before the File Meta Information.
        var writer = Writer(explicit: false)
        writer.header(0x0001, 0x0001, "", 2)
        writer.bytes += [0x41, 0x20]
        writer.text(0x0010, 0x0010, "PN", "Doe^Jane")
        var source = DcmSwiftFuzzTests.part10(transferSyntax: TransferSyntax.implicitVRLittleEndian, dataSet: writer.bytes)
        source.replaceSubrange(0..<8, with: [0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00])
        XCTAssertEqual(try rewrite(source), source)
    }

    func testLongValuesOfShortLengthVRsBecomeUN() throws {
        // An 80000-byte IS value from Implicit VR does not fit a 16-bit
        // Explicit VR length: they are written as UN (PS3.5 6.2.2), and OD
        // has a 32-bit length.
        var writer = Writer(explicit: false)
        writer.header(0x0008, 0x1160, "", 80_000)
        writer.bytes += [UInt8](repeating: 0x37, count: 80_000)
        writer.header(0x0066, 0x0022, "", 16)
        writer.bytes += [UInt8](repeating: 1, count: 16)
        let dataSet = try DICOMDataSetCoding.decode(Data(writer.bytes), transferSyntax: TransferSyntax.implicitVRLittleEndian)
        let explicit = [UInt8](try DICOMDataSetCoding.encode(dataSet, transferSyntax: TransferSyntax.explicitVRLittleEndian))
        // (0028,3006) UN, reserved bytes, 32-bit length.
        XCTAssertEqual(Array(explicit[0..<12]), [0x08, 0x00, 0x60, 0x11, 0x55, 0x4E, 0, 0, 0x80, 0x38, 0x01, 0x00])
        let reread = try DICOMDataSetCoding.decode(Data(explicit), transferSyntax: TransferSyntax.explicitVRLittleEndian)
        XCTAssertEqual(reread.allElements.first { $0.tagCode() == "00081160" }?.data.count, 80_000)
        let od = try XCTUnwrap(reread.allElements.first { $0.tagCode() == "00660022" })
        XCTAssertEqual(od.vr, .OD)
        XCTAssertEqual(od.data.count, 16)
    }
}
