import XCTest
@testable import DcmSwift

/// Checks of the encoding as read: the File Meta Information Group Length
/// (PS3.10 7.1), unique and ascending tags (PS3.5 7.1), Private Creators
/// (PS3.5 7.8.1), and Value Field padding (PS3.5 6.2).
final class DcmSwiftEncodingValidationTests: XCTestCase {
    typealias Writer = DcmSwiftFuzzTests.Writer

    private func messages(_ bytes: [UInt8]) throws -> [String] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("encoding-\(UUID().uuidString).dcm")
        try Data(bytes).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try DicomFile(tolerantlyReadingPath: url.path)
        return file.validate().map(\.message)
    }

    private func file(_ body: (inout Writer) -> Void) -> [UInt8] {
        var writer = Writer()
        body(&writer)
        return DcmSwiftFuzzTests.part10(transferSyntax: TransferSyntax.explicitVRLittleEndian, dataSet: writer.bytes)
    }

    func testAConformingDataSetHasNoEncodingFinding() throws {
        let found = try messages(file { writer in
            writer.text(0x0008, 0x0016, "UI", "1.2.840.10008.5.1.4.1.1.7")
            writer.text(0x0009, 0x0010, "LO", "VENDOR")
            writer.text(0x0009, 0x1001, "LO", "VALUE")
            writer.text(0x0010, 0x0010, "PN", "Doe^Jane")
        })
        XCTAssertFalse(found.contains { $0.contains("PS3.5 7.") || $0.contains("PS3.10 7.1") || $0.contains("padded") }, "\(found)")
    }

    func testTheGroupLengthIsCheckedAgainstTheGroup() throws {
        var bytes = file { $0.text(0x0010, 0x0010, "PN", "Doe^Jane") }
        // (0002,0000) value, after the preamble, DICM, and its 8-byte header.
        let at = 132 + 8
        let declared = Int(bytes[at]) | Int(bytes[at + 1]) << 8
        bytes[at] = UInt8(truncatingIfNeeded: declared + 20)
        bytes[at + 1] = UInt8(truncatingIfNeeded: (declared + 20) >> 8)
        let found = try messages(bytes)
        XCTAssertTrue(found.contains("File Meta Information Group Length is \(declared + 20) but the group holds \(declared) bytes (PS3.10 7.1)"), "\(found)")
    }

    func testDuplicateAndUnsortedTagsAreReportedOnce() throws {
        let found = try messages(file { writer in
            writer.text(0x0010, 0x0020, "LO", "ID")
            writer.text(0x0010, 0x0010, "PN", "Doe^Jane")
            writer.text(0x0010, 0x0020, "LO", "AGAIN")
        })
        XCTAssertEqual(found.filter { $0.contains("appears more than once (PS3.5 7.1)") }.count, 1, "\(found)")
        XCTAssertEqual(found.filter { $0.contains("not in ascending order (PS3.5 7.1)") }.count, 1, "\(found)")
    }

    func testAPrivateElementNeedsItsCreatorInItsDataSetOrItem() throws {
        let found = try messages(file { writer in
            writer.text(0x0009, 0x1010, "LO", "ORPHAN")
            writer.sequence(0x0008, 0x1140, undefined: true, items: [{ item in
                item.text(0x0011, 0x0010, "LO", "VENDOR")
                item.text(0x0011, 0x1001, "LO", "OWNED")
                item.text(0x0011, 0x1101, "LO", "ORPHAN")
            }])
        })
        let orphans = found.filter { $0.contains("has no Private Creator") }
        XCTAssertEqual(orphans.count, 2, "\(found)")
        XCTAssertTrue(orphans.contains { $0.contains("(0009,0010)") })
        XCTAssertTrue(orphans.contains { $0.contains("(0011,0011)") })
        XCTAssertFalse(found.contains { $0.contains("may be private") })
    }

    func testPaddingFollowsTheVR() throws {
        let found = try messages(file { writer in
            writer.text(0x0008, 0x0018, "UI", Array("1.2.3".utf8), pad: 0x20)
            writer.text(0x0010, 0x0010, "PN", Array("Doe^Jan".utf8), pad: 0x00)
        })
        XCTAssertTrue(found.contains { $0.contains("padded with a space; UI is padded with NUL (PS3.5 6.2)") }, "\(found)")
        XCTAssertTrue(found.contains { $0.contains("padded with NUL; PN is padded with a space (PS3.5 6.2)") }, "\(found)")
    }
}
