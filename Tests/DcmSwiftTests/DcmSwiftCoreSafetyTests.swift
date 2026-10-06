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

    func testAttributeTagValueUsesTargetByteOrder() throws {
        let dataset = DataSet()
        let pointer = try XCTUnwrap(dataset.set(
            value: DataTag(withGroup: "0028", element: "0010"),
            forTagName: "DimensionIndexPointer"
        ))

        XCTAssertEqual(pointer.data, Data([0x28, 0x00, 0x10, 0x00]))
        XCTAssertEqual(
            pointer.toData(vrMethod: .Explicit, byteOrder: .BigEndian).suffix(4),
            Data([0x00, 0x28, 0x00, 0x10])
        )
    }

    func testModernTextVRUsesLongExplicitHeaderAndURIStaysASCII() throws {
        let dataset = DataSet()
        _ = dataset.set(value: "ISO_IR 192", forTagName: "SpecificCharacterSet")
        let url = try XCTUnwrap(dataset.set(
            value: "https://example.test/dicom",
            forTagName: "CodingSchemeURL"
        ))
        let encoded = url.toData(vrMethod: .Explicit, byteOrder: .LittleEndian)

        XCTAssertEqual(Array(encoded[4..<8]), [0x55, 0x52, 0x00, 0x00])
        XCTAssertEqual(encoded.subdata(in: 8..<12).toUInt32(), UInt32(url.length))
        XCTAssertNil(dataset.set(value: "https://example.test/é", forTagName: "CodingSchemeURL"))
    }

    func testFloatingPointAndModernBinaryVRSetters() throws {
        let dataset = DataSet()
        let float = try XCTUnwrap(dataset.set(value: Float32(1.5), forTagName: "RecommendedDisplayFrameRateInFloat"))
        let double = try XCTUnwrap(dataset.set(value: Float64(-2.25), forTagName: "EventTimeOffset"))
        let offsets = try XCTUnwrap(dataset.set(value: Data([1, 2, 3, 4]), forTagName: "LongPrimitivePointIndexList"))

        XCTAssertEqual(float.value as? Float32, 1.5)
        XCTAssertEqual(double.value as? Float64, -2.25)
        XCTAssertEqual(offsets.vr, .OL)
        XCTAssertEqual(offsets.data, Data([1, 2, 3, 4]))
    }

    func testFileMetaValidationReportsMissingAndMismatchedIdentifiers() {
        let dataset = DataSet()
        dataset.hasPreamble = true
        _ = dataset.set(value: "1.2.840.10008.5.1.4.1.1.2", forTagName: "SOPClassUID")
        _ = dataset.set(value: "1.2.3.4", forTagName: "SOPInstanceUID")
        _ = dataset.set(value: "1.2.840.10008.5.1.4.1.1.4", forTagName: "MediaStorageSOPClassUID")
        _ = dataset.set(value: "1.2.3.5", forTagName: "MediaStorageSOPInstanceUID")

        let messages = dataset.validateFileMetaInformation().map(\.message)
        XCTAssertTrue(messages.contains("MediaStorageSOPClassUID does not match SOPClassUID"))
        XCTAssertTrue(messages.contains("MediaStorageSOPInstanceUID does not match SOPInstanceUID"))
        XCTAssertTrue(messages.contains("Missing required File Meta Information element TransferSyntaxUID"))
        XCTAssertTrue(messages.contains("Missing required File Meta Information element ImplementationClassUID"))
    }

    func testReadLimitsRejectOversizedElementBeforeReadingItsValue() {
        // PatientName, explicit VR Little Endian, four-byte value.
        let bytes = Data([0x10, 0x00, 0x10, 0x00, 0x50, 0x4e, 0x04, 0x00, 0x41, 0x42, 0x43, 0x44])
        let stream = DicomInputStream(data: bytes)
        stream.limits.maximumElementValueLength = 2

        XCTAssertThrowsError(try stream.readDataset(enforceVR: false)) { error in
            guard case StreamError.datasetIsCorrupted = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testReadLimitsRejectExcessiveElementCount() {
        let first = Data([0x10, 0x00, 0x20, 0x00, 0x4c, 0x4f, 0x02, 0x00, 0x41, 0x20])
        let second = Data([0x10, 0x00, 0x30, 0x00, 0x44, 0x41, 0x08, 0x00])
            + Data("20000101".utf8)
        let stream = DicomInputStream(data: first + second)
        stream.limits.maximumElementCount = 1

        XCTAssertThrowsError(try stream.readDataset(enforceVR: false)) { error in
            guard case StreamError.datasetIsCorrupted = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testReadLimitsRejectSequenceNesting() {
        var sequence = Data([0x08, 0x00, 0x11, 0x11, 0x53, 0x51, 0x00, 0x00])
        sequence.append(contentsOf: [0xff, 0xff, 0xff, 0xff])
        let stream = DicomInputStream(data: sequence)
        stream.limits.maximumSequenceDepth = 0

        XCTAssertThrowsError(try stream.readDataset(enforceVR: false)) { error in
            guard case StreamError.datasetIsCorrupted = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testReadLimitsCountPixelFragmentsSeparatelyFromOffsetTable() {
        var pixelData = Data([0xe0, 0x7f, 0x10, 0x00, 0x4f, 0x42, 0x00, 0x00])
        pixelData.append(contentsOf: [0xff, 0xff, 0xff, 0xff])
        // Empty Basic Offset Table followed by one two-byte fragment.
        pixelData.append(contentsOf: [0xfe, 0xff, 0x00, 0xe0, 0x00, 0x00, 0x00, 0x00])
        pixelData.append(contentsOf: [0xfe, 0xff, 0x00, 0xe0, 0x02, 0x00, 0x00, 0x00, 0x01, 0x02])
        pixelData.append(contentsOf: [0xfe, 0xff, 0xdd, 0xe0, 0x00, 0x00, 0x00, 0x00])

        let allowed = DicomInputStream(data: pixelData)
        allowed.limits.maximumPixelFragmentCount = 1
        XCTAssertNoThrow(try allowed.readDataset(enforceVR: false))

        let rejected = DicomInputStream(data: pixelData)
        rejected.limits.maximumPixelFragmentCount = 0
        XCTAssertThrowsError(try rejected.readDataset(enforceVR: false))
    }

    func testUndefinedSequenceRequiresZeroLengthDelimiter() {
        var sequence = Data([0x08, 0x00, 0x11, 0x11, 0x53, 0x51, 0x00, 0x00])
        sequence.append(contentsOf: [0xff, 0xff, 0xff, 0xff])
        sequence.append(contentsOf: [0xfe, 0xff, 0xdd, 0xe0, 0x01, 0x00, 0x00, 0x00])

        XCTAssertThrowsError(try DicomInputStream(data: sequence).readDataset(enforceVR: false))
    }

    func testDefinedSequenceRejectsNonItemContent() {
        var sequence = Data([0x08, 0x00, 0x11, 0x11, 0x53, 0x51, 0x00, 0x00])
        sequence.append(contentsOf: [0x08, 0x00, 0x00, 0x00])
        // A regular Data Element tag and four bytes interpreted as its length.
        sequence.append(contentsOf: [0x10, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00])

        XCTAssertThrowsError(try DicomInputStream(data: sequence).readDataset(enforceVR: false))
    }

    func testImplicitVRPrivateCreatorResolvesPrivateBlock() throws {
        var bytes = Data([0x09, 0x00, 0x11, 0x00])
        bytes.append(uint32: 4)
        bytes.append(contentsOf: Data("ACME".utf8))
        bytes.append(contentsOf: [0x09, 0x00, 0x01, 0x11])
        bytes.append(uint32: 2)
        bytes.append(contentsOf: [0x12, 0x34])

        let dataset = try XCTUnwrap(try DicomInputStream(data: bytes).readDataset())
        let creator = try XCTUnwrap(dataset.allElements.first { $0.tagCode() == "00090011" })
        let privateElement = try XCTUnwrap(dataset.allElements.first { $0.tagCode() == "00091101" })

        XCTAssertTrue(creator.tag.isPrivateCreator)
        XCTAssertEqual(creator.vr, .LO)
        XCTAssertEqual(creator.value as? String, "ACME")
        XCTAssertEqual(privateElement.vr, .UN)
        XCTAssertEqual(privateElement.privateCreator, "ACME")
        XCTAssertEqual(privateElement.data, Data([0x12, 0x34]))
    }

    func testPrivateCreatorReservationsAreScopedPerSequenceItem() throws {
        func explicitElement(tag: [UInt8], vr: [UInt8], value: Data, longLength: Bool = false) -> Data {
            var data = Data(tag + vr)
            if longLength {
                data.append(contentsOf: [0x00, 0x00])
                data.append(uint32: UInt32(value.count))
            } else {
                data.append(uint16: UInt16(value.count))
            }
            data.append(value)
            return data
        }

        func item(creator: String, value: UInt8) -> Data {
            var content = explicitElement(
                tag: [0x09, 0x00, 0x10, 0x00],
                vr: [0x4c, 0x4f],
                value: Data(creator.utf8)
            )
            content.append(explicitElement(
                tag: [0x09, 0x00, 0x01, 0x10],
                vr: [0x55, 0x4e],
                value: Data([value, 0x00]),
                longLength: true
            ))
            var encoded = Data([0xfe, 0xff, 0x00, 0xe0])
            encoded.append(uint32: UInt32(content.count))
            encoded.append(content)
            return encoded
        }

        var sequence = Data([0x08, 0x00, 0x11, 0x11, 0x53, 0x51, 0x00, 0x00])
        var items = item(creator: "ONE ", value: 1)
        items.append(item(creator: "TWO ", value: 2))
        sequence.append(uint32: UInt32(items.count))
        sequence.append(items)

        let dataset = try XCTUnwrap(
            try DicomInputStream(data: sequence).readDataset(enforceVR: false)
        )
        let parsedSequence = try XCTUnwrap(dataset.allElements.first as? DataSequence)
        XCTAssertEqual(parsedSequence.items.count, 2)
        XCTAssertEqual(parsedSequence.items[0].elements.last?.privateCreator, "ONE")
        XCTAssertEqual(parsedSequence.items[1].elements.last?.privateCreator, "TWO")
    }

    func testNestedCharacterSetOverrideDoesNotLeakToSiblingItem() throws {
        func explicitElement(tag: [UInt8], vr: [UInt8], value: Data) -> Data {
            var data = Data(tag + vr)
            data.append(uint16: UInt16(value.count))
            data.append(value)
            return data
        }

        func item(_ content: Data) -> Data {
            var data = Data([0xfe, 0xff, 0x00, 0xe0])
            data.append(uint32: UInt32(content.count))
            data.append(content)
            return data
        }

        var bytes = explicitElement(
            tag: [0x08, 0x00, 0x05, 0x00],
            vr: [0x43, 0x53],
            value: Data("ISO_IR 192".utf8)
        )
        let latin1Name = try XCTUnwrap("Jérôme".data(using: .isoLatin1))
        var firstContent = explicitElement(
            tag: [0x08, 0x00, 0x05, 0x00],
            vr: [0x43, 0x53],
            value: Data("ISO_IR 100".utf8)
        )
        firstContent.append(explicitElement(
            tag: [0x10, 0x00, 0x10, 0x00],
            vr: [0x50, 0x4e],
            value: latin1Name
        ))
        let secondContent = explicitElement(
            tag: [0x10, 0x00, 0x10, 0x00],
            vr: [0x50, 0x4e],
            value: Data("山田".utf8)
        )
        var items = item(firstContent)
        items.append(item(secondContent))
        bytes.append(contentsOf: [0x08, 0x00, 0x11, 0x11, 0x53, 0x51, 0x00, 0x00])
        bytes.append(uint32: UInt32(items.count))
        bytes.append(items)

        let dataset = try XCTUnwrap(
            try DicomInputStream(data: bytes).readDataset(enforceVR: false)
        )
        let sequence = try XCTUnwrap(dataset.allElements.last as? DataSequence)
        let firstName = try XCTUnwrap(sequence.items[0].element(withName: "PatientName"))
        let secondName = try XCTUnwrap(sequence.items[1].element(withName: "PatientName"))

        XCTAssertEqual(firstName.effectiveCharacterSet, .latin1)
        XCTAssertEqual(firstName.value as? String, "Jérôme")
        XCTAssertEqual(secondName.effectiveCharacterSet, .utf8)
        XCTAssertEqual(secondName.value as? String, "山田")
    }

    func testMultiValuedBinaryVRsRoundTripWithTypedAccessors() throws {
        let source = DataSet()
        XCTAssertNotNil(source.set(value: [UInt16.max, 1], forTagName: "SynchronizationChannel"))
        XCTAssertNotNil(source.set(value: [Int16(-2), 3], forTagName: "CenterOfCircularExposureControlSensingRegion"))
        XCTAssertNotNil(source.set(value: [UInt32(1), 2, 3], forTagName: "SimpleFrameList"))
        XCTAssertNotNil(source.set(value: [Int64.min, 7], forTagName: "SelectorSVValue"))
        XCTAssertNotNil(source.set(value: [UInt64.max, 8], forTagName: "SelectorUVValue"))
        XCTAssertNotNil(source.set(value: [Float32(1.5), -2.25], forTagName: "LocalizingCursorPosition"))
        XCTAssertNotNil(source.set(value: [Float64.pi, -0.5], forTagName: "TimeRange"))
        XCTAssertNotNil(source.set(value: [
            DataTag(withGroup: "0018", element: "1063"),
            DataTag(withGroup: "0018", element: "1065")
        ], forTagName: "FrameIncrementPointer"))

        let decoded = try XCTUnwrap(
            try DicomInputStream(data: source.toData()).readDataset(enforceVR: false)
        )
        XCTAssertEqual(decoded.element(forTagName: "SynchronizationChannel")?.uint16Values, [UInt16.max, 1])
        XCTAssertEqual(decoded.element(forTagName: "CenterOfCircularExposureControlSensingRegion")?.int16Values, [-2, 3])
        XCTAssertEqual(decoded.element(forTagName: "SimpleFrameList")?.uint32Values, [1, 2, 3])
        XCTAssertEqual(decoded.element(forTagName: "SelectorSVValue")?.int64Values, [Int64.min, 7])
        XCTAssertEqual(decoded.element(forTagName: "SelectorUVValue")?.uint64Values, [UInt64.max, 8])
        XCTAssertEqual(decoded.element(forTagName: "LocalizingCursorPosition")?.float32Values, [1.5, -2.25])
        XCTAssertEqual(decoded.element(forTagName: "TimeRange")?.float64Values, [Double.pi, -0.5])
        let pointers = try XCTUnwrap(
            decoded.element(forTagName: "FrameIncrementPointer")?.attributeTagValues
        )
        XCTAssertEqual(pointers.map(\.code), ["00181063", "00181065"])
    }

    func testDictionaryVMValidationHandlesRangesAndMultiples() throws {
        let dataset = DataSet()
        let valid = try XCTUnwrap(dataset.set(
            value: [UInt32(1), 2, 3, 4, 5, 6],
            forTagName: "CalculatedFrameList"
        ))
        XCTAssertEqual(valid.valueMultiplicity, 6)
        XCTAssertFalse(DicomSpec.shared.validate(dataElement: valid).contains { $0.message.contains("Multiplicity") })

        let invalid = try XCTUnwrap(dataset.set(
            value: [UInt16(1), 2, 3],
            forTagName: "SynchronizationChannel"
        ))
        let results = DicomSpec.shared.validate(dataElement: invalid)
        XCTAssertTrue(results.contains { $0.message.contains("requires VM 2 but contains 3") })
    }

    func testContextDependentVRValidationAcceptsSignedPixelPadding() throws {
        let dataset = DataSet()
        let element = try XCTUnwrap(dataset.set(value: Int16(-1), forTagName: "PixelPaddingValue"))
        element.vr = .SS

        XCTAssertFalse(DicomSpec.shared.validate(dataElement: element).contains {
            $0.message.contains("Value Representation mismatch")
        })
    }
}
