import Foundation
import XCTest
@testable import DcmSwift

final class DcmSwiftCoreSafetyTests: XCTestCase {
    func testRuntimeDictionaryComesFromDICOM2026d() {
        XCTAssertEqual(DicomSpec.shared.dictionaryEdition, "2026d")
        XCTAssertEqual(DicomSpec.shared.nameForTag(withCode: "00100010"), "PatientName")
        XCTAssertNotNil(DicomSpec.shared.dataTag(forName: "LongCodeValue"))
    }

    func testKnownTransferSyntaxIsNotAutomaticallyImplemented() {
        let deflated = "1.2.840.10008.1.2.1.99"
        XCTAssertTrue(DicomSpec.shared.isKnown(transferSyntax: deflated))
        XCTAssertFalse(DicomSpec.shared.isSupported(transferSyntax: deflated))
        XCTAssertFalse(TransferSyntax(deflated)!.capability.canReadDataset)

        let jpegBaseline = TransferSyntax.JPEGLossy8bit
        XCTAssertTrue(DicomSpec.shared.isKnown(transferSyntax: jpegBaseline))
        XCTAssertTrue(TransferSyntax(jpegBaseline)!.capability.canPreservePixelData)
        XCTAssertFalse(TransferSyntax(jpegBaseline)!.capability.canDecodePixelData)
        XCTAssertFalse(TransferSyntax(jpegBaseline)!.capability.canNegotiateForDIMSE)
    }

    func testNumericDecodingHonorsByteOrderAndShortInputIsSafe() {
        XCTAssertEqual(Data([0x34, 0x12]).toUInt16(), 0x1234)
        XCTAssertEqual(Data([0x12, 0x34]).toUInt16(byteOrder: .BigEndian), 0x1234)
        XCTAssertEqual(Data([0x78, 0x56, 0x34, 0x12]).toUInt32(), 0x12345678)
        XCTAssertEqual(Data([0x12, 0x34, 0x56, 0x78]).toUInt32(byteOrder: .BigEndian), 0x12345678)
        XCTAssertEqual(Data([0xff, 0xff]).toInt16(), -1)
        XCTAssertEqual(Data().toUInt32(), 0)
    }

    func testChunkingUsesRequestedSize() {
        let data = Data(0..<10)
        XCTAssertEqual(data.chunked(into: 4), [Data(0..<4), Data(4..<8), Data(8..<10)])
        XCTAssertEqual(data.chunked(into: 0), [])
        XCTAssertEqual(Array(0..<5).chunked(into: 2), [[0, 1], [2, 3], [4]])
    }

    func testOffsetInputStreamRejectsInvalidAndTruncatedReads() {
        let stream = OffsetInputStream(data: Data([1, 2, 3]))
        stream.open()
        defer { stream.close() }

        XCTAssertNil(stream.read(length: -1))
        XCTAssertEqual(stream.read(length: 2), Data([1, 2]))
        XCTAssertNil(stream.read(length: 2))
        XCTAssertEqual(stream.readableBytes, 1)
    }

    func testUserInfoEncodingContainsRequiredSubItemsAndRoundTrips() {
        let source = UserInfo(
            implementationVersion: "DCMSWIFT_2",
            implementationUID: "1.2.826.0.1.3680043.10.999",
            maxPDULength: 131_072
        )
        let encoded = source.data()

        XCTAssertEqual(encoded.first, ItemType.userInfo.rawValue)
        XCTAssertEqual(encoded.subdata(in: 2..<4).toUInt16(byteOrder: .BigEndian), UInt16(encoded.count - 4))

        let decoded = UserInfo(data: encoded.subdata(in: 4..<encoded.count))
        XCTAssertEqual(decoded?.maxPDULength, 131_072)
        XCTAssertEqual(decoded?.implementationUID, source.implementationUID)
        XCTAssertEqual(decoded?.implementationVersion, source.implementationVersion)
    }

    func testUserInfoRejectsTruncatedSubItem() {
        XCTAssertNil(UserInfo(data: Data([ItemType.maxPduLength.rawValue, 0, 0, 4, 0, 1])))
    }

    func testPixelAccessUsesPixelWidthAndRangeOffset() {
        let dataset = DataSet()
        let bytes = Data([0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x04, 0x00])
        let element = dataset.set(value: bytes, forTagName: "PixelData")!

        XCTAssertEqual(PixelDataAccess.getPixelUnsigned16(pixelDataElement: element, pixelNumber: 2, byteOrder: .LittleEndian), 3)
        XCTAssertNil(PixelDataAccess.getPixelUnsigned16(pixelDataElement: element, pixelNumber: 4, byteOrder: .LittleEndian))
        XCTAssertEqual(
            PixelDataAccess.getUnsigned16Pixels(pixelDataElement: element, from: 2, at: 6, byteOrder: .LittleEndian),
            [2, 3]
        )
    }

    func testUnsignedVRValuesPreserveFullRange() {
        let dataset = DataSet()
        let rows = dataset.set(value: UInt16.max, forTagName: "Rows")!
        XCTAssertEqual(rows.value as? UInt16, UInt16.max)

        let groupLength = dataset.set(value: UInt32.max - 1, forTagName: "FileMetaInformationGroupLength")!
        XCTAssertEqual(groupLength.value as? UInt32, UInt32.max - 1)
    }

    func testBigEndianTransferSyntaxExposesBigEndianEncoding() {
        let syntax = TransferSyntax(TransferSyntax.explicitVRBigEndian)
        XCTAssertEqual(syntax?.byteOrder, .BigEndian)
        XCTAssertEqual(syntax?.vrMethod, .Explicit)
    }

    func testTruncatedDeclaredValueThrowsCorruptionError() {
        // PatientName, explicit VR Little Endian, declares 8 bytes but only contains 2.
        let bytes = Data([0x10, 0x00, 0x10, 0x00, 0x50, 0x4e, 0x08, 0x00, 0x41, 0x42])
        XCTAssertThrowsError(try DicomInputStream(data: bytes).readDataset(enforceVR: false)) { error in
            guard case StreamError.datasetIsCorrupted = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testDIMSECommandSetUsesLittleEndianValues() throws {
        let command = DataSet()
        _ = command.set(value: CommandField.C_ECHO_RQ.rawValue, forTagName: "CommandField")
        _ = command.set(value: UInt16(7), forTagName: "MessageID")
        _ = command.set(value: UInt16(0x0101), forTagName: "CommandDataSetType")

        let pdu = PDUData(
            pduType: .dataTF,
            commandDataset: command,
            abstractSyntax: DicomConstants.verificationSOP,
            transferSyntax: try XCTUnwrap(TransferSyntax(TransferSyntax.implicitVRLittleEndian)),
            pcID: 1,
            flags: 0x03
        ).data()

        let pdvLength = Int(pdu.subdata(in: 6..<10).toUInt32(byteOrder: .BigEndian))
        let commandData = pdu.subdata(in: 12..<10 + pdvLength)
        let decoded = try XCTUnwrap(try DicomInputStream(data: commandData).readDataset())

        XCTAssertEqual(decoded.unsignedInteger16(forTag: "CommandField"), CommandField.C_ECHO_RQ.rawValue)
        XCTAssertEqual(decoded.unsignedInteger16(forTag: "MessageID"), 7)
        XCTAssertEqual(decoded.unsignedInteger16(forTag: "CommandDataSetType"), 0x0101)
        XCTAssertEqual(decoded.unsignedInteger32(forTag: "CommandGroupLength"), UInt32(commandData.count - 12))
    }

    func testDataElementTranscodesNumericValueByteOrder() {
        let dataset = DataSet()
        let rows = dataset.set(value: UInt16(0x1234), forTagName: "Rows")!
        XCTAssertEqual(
            rows.toData(vrMethod: .Explicit, byteOrder: .BigEndian),
            Data([0x00, 0x28, 0x00, 0x10, 0x55, 0x53, 0x00, 0x02, 0x12, 0x34])
        )
    }

    func testLatin1SpecificCharacterSetRoundTrips() throws {
        let source = DataSet()
        XCTAssertNotNil(source.set(value: "ISO_IR 100", forTagName: "SpecificCharacterSet"))
        let name = try XCTUnwrap(source.set(value: "Jérôme", forTagName: "PatientName"))
        XCTAssertEqual(source.characterSet, .latin1)
        XCTAssertTrue(name.data.contains(0xe9))

        let encoded = source.toData(vrMethod: .Explicit, byteOrder: .LittleEndian)
        let decoded = try XCTUnwrap(
            try DicomInputStream(data: encoded).readDataset(enforceVR: false)
        )
        XCTAssertEqual(decoded.characterSet, .latin1)
        XCTAssertEqual(decoded.string(forTag: "PatientName"), "Jérôme")
    }

    func testUTF8SpecificCharacterSetRoundTrips() throws {
        let source = DataSet()
        XCTAssertNotNil(source.set(value: "ISO_IR 192", forTagName: "SpecificCharacterSet"))
        XCTAssertNotNil(source.set(value: "山田^太郎", forTagName: "PatientName"))

        let encoded = source.toData(vrMethod: .Explicit, byteOrder: .LittleEndian)
        let decoded = try XCTUnwrap(
            try DicomInputStream(data: encoded).readDataset(enforceVR: false)
        )
        XCTAssertEqual(decoded.characterSet, .utf8)
        XCTAssertEqual(decoded.string(forTag: "PatientName"), "山田^太郎")
    }

    func testUnsupportedCharacterSetDoesNotFallBackToUTF8() {
        let dataset = DataSet()
        XCTAssertNotNil(dataset.set(value: "ISO 2022 IR 87", forTagName: "SpecificCharacterSet"))
        XCTAssertFalse(dataset.characterSet.isSupported)
        XCTAssertNil(dataset.set(value: "山田", forTagName: "PatientName"))
        XCTAssertNil(DICOMCharacterSet(specificCharacterSet: "ISO 2022 IR 87").decode(Data([0x41])))
    }

    func testSignedIntegerSettersPreserveSign() {
        let dataset = DataSet()
        let signedShort = dataset.set(value: Int16(-2), forTagName: "PixelPaddingValue")!
        let signedLong = dataset.set(value: Int32(-3), forTagName: "IntegerNumericValue")!

        // Pixel Padding Value has an ambiguous dictionary VR; select SS for this fixture.
        signedShort.vr = .SS
        XCTAssertEqual(signedShort.value as? Int16, -2)
        XCTAssertEqual(signedLong.value as? Int32, -3)
    }

    func testUnimplementedTransferSyntaxIsRejected() throws {
        let meta = DataSet()
        _ = meta.set(value: "1.2.840.10008.1.2.1.99", forTagName: "TransferSyntaxUID")
        var part10 = Data(repeating: 0, count: 128)
        part10.append(contentsOf: [0x44, 0x49, 0x43, 0x4d])
        part10.append(meta.toData())

        XCTAssertThrowsError(try DicomInputStream(data: part10).readDataset()) { error in
            guard case StreamError.unsupportedTransferSyntax(let uid) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(uid, "1.2.840.10008.1.2.1.99")
        }
    }

    func testFileMetaInformationIsExplicitLittleEndianAndRecalculated() {
        let dataset = DataSet()
        dataset.hasPreamble = true
        _ = dataset.set(value: UInt32(0), forTagName: "FileMetaInformationGroupLength")
        _ = dataset.set(value: "1.2.840.10008.1.2.1", forTagName: "TransferSyntaxUID")
        _ = dataset.set(value: "1.2.826.0.1.3680043.10.999", forTagName: "ImplementationClassUID")
        _ = dataset.set(value: "TEST", forTagName: "PatientID")

        let expected = dataset.metaInformationHeaderElements
            .filter { $0.name != "FileMetaInformationGroupLength" }
            .reduce(0) { $0 + $1.toData(vrMethod: .Explicit, byteOrder: .LittleEndian).count }
        let encoded = dataset.toData(vrMethod: .Implicit, byteOrder: .BigEndian)

        XCTAssertEqual(dataset.unsignedInteger32(forTag: "FileMetaInformationGroupLength"), UInt32(expected))
        XCTAssertEqual(Array(encoded.prefix(8)), [0x02, 0x00, 0x00, 0x00, 0x55, 0x4c, 0x04, 0x00])
    }

    func testPart10BigEndianDatasetStartsAfterCompleteFileMetaInformation() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dcmswift-\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: url) }

        let source = DataSet()
        source.hasPreamble = true
        source.transferSyntax = try XCTUnwrap(TransferSyntax(TransferSyntax.explicitVRBigEndian))
        _ = source.set(value: "1.2.826.0.1.3680043.10.999", forTagName: "ImplementationClassUID")
        _ = source.set(value: "BIG-ENDIAN", forTagName: "PatientID")

        XCTAssertTrue(try DicomOutputStream(url: url).write(dataset: source))
        XCTAssertEqual(source.string(forTag: "TransferSyntaxUID"), TransferSyntax.explicitVRBigEndian)

        let decoded = try XCTUnwrap(try DicomInputStream(url: url).readDataset())
        XCTAssertEqual(decoded.transferSyntax.tsUID, TransferSyntax.explicitVRBigEndian)
        XCTAssertEqual(decoded.string(forTag: "PatientID"), "BIG-ENDIAN")
    }

    func testDefaultWriterPreservesEncapsulatedTransferSyntaxUID() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dcmswift-\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: url) }

        let source = DataSet()
        source.hasPreamble = true
        source.transferSyntax = try XCTUnwrap(TransferSyntax(TransferSyntax.JPEGLossless))
        _ = source.set(value: "1.2.826.0.1.3680043.10.999", forTagName: "ImplementationClassUID")

        XCTAssertTrue(try DicomOutputStream(url: url).write(
            dataset: source,
            vrMethod: nil,
            byteOrder: nil
        ))
        XCTAssertEqual(source.transferSyntax.tsUID, TransferSyntax.JPEGLossless)
        XCTAssertEqual(source.string(forTag: "TransferSyntaxUID"), TransferSyntax.JPEGLossless)
    }
}
