import XCTest
import NIOCore
@testable import DcmSwift

/// DICOM Upper Layer PDUs (PS3.8 9.3). The reference bytes were produced by
/// pynetdicom 3.0.4, an independent implementation.
final class DcmSwiftNetworkPDUTests: XCTestCase {
    private static let pynetdicom: [String: String] = [
        "rq": "0100000001f300010000414e592d53435020202020202020202043414c4c494e47202020202020202020000000000000000000000000000000000000000000000000000000000000000010000015312e322e3834302e31303030382e332e312e312e312000002e0100000030000011312e322e3834302e31303030382e312e3140000011312e322e3834302e31303030382e312e32200000670300000030000019312e322e3834302e31303030382e352e312e342e312e312e3240000013312e322e3834302e31303030382e312e322e3140000011312e322e3834302e31303030382e312e3240000016312e322e3834302e31303030382e312e322e342e3830500000f5510000040000400052000020312e322e3832362e302e312e333638303034332e392e333831312e322e312e3053000004000300045400001d0019312e322e3834302e31303030382e352e312e342e312e312e3201015500000c44434d53574946545f32303056000020001b312e322e3834302e31303030382e352e312e342e312e322e312e3101000157000053001d312e322e3834302e31303030382e352e312e342e312e312e38382e32320011312e322e3834302e31303030382e342e32001f001d312e322e3834302e31303030382e352e312e342e312e312e38382e31315800001102010005616c6963650006733363726574",
        "ac": "0200000000f600010000414e592d53435020202020202020202043414c4c494e47202020202020202020000000000000000000000000000000000000000000000000000000000000000010000015312e322e3834302e31303030382e332e312e312e31210000190100000040000011312e322e3834302e31303030382e312e32210000190300030040000011312e322e3834302e31303030382e312e325000005b510000040000800052000020312e322e3832362e302e312e333638303034332e392e333831312e322e312e305400001d0019312e322e3834302e31303030382e352e312e342e312e312e3200015900000a00084f4b2d544f4b454e",
        "rj": "03000000000400010107",
        "pdata": "04000000001100000005010300010200000004030002aa",
        "releaserq": "05000000000400000000",
        "releaserp": "06000000000400000000",
        "abort": "07000000000400000206",
    ]

    private static let implementationClassUID = "1.2.826.0.1.3680043.9.3811.2.1.0"

    private func buffer(_ hex: String) -> ByteBuffer {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return ByteBufferAllocator().buffer(bytes: bytes)
    }

    private func decode(_ bytes: ByteBuffer) throws -> DICOMPDU {
        var bytes = bytes
        var decoder = DICOMPDUFrameDecoder(maximumDataLength: 1 << 20)
        let pdu = try XCTUnwrap(try decoder.decode(buffer: &bytes))
        XCTAssertEqual(bytes.readableBytes, 0)
        return pdu
    }

    private var expectedRequest: DICOMAssociateRequest {
        DICOMAssociateRequest(
            calledAETitle: "ANY-SCP", callingAETitle: "CALLING",
            presentationContexts: [
                DICOMPresentationContextProposal(
                    id: 1, abstractSyntax: "1.2.840.10008.1.1", transferSyntaxes: ["1.2.840.10008.1.2"]),
                DICOMPresentationContextProposal(
                    id: 3, abstractSyntax: "1.2.840.10008.5.1.4.1.1.2",
                    transferSyntaxes: ["1.2.840.10008.1.2.1", "1.2.840.10008.1.2", "1.2.840.10008.1.2.4.80"]),
            ],
            userInformation: DICOMUserInformation(
                maximumLength: 16384, implementationClassUID: Self.implementationClassUID,
                implementationVersionName: "DCMSWIFT_200",
                asynchronousOperationsWindow: DICOMAsynchronousOperationsWindow(maximumInvoked: 3, maximumPerformed: 4),
                roleSelections: [DICOMRoleSelection(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", scuRole: true, scpRole: true)],
                extendedNegotiations: [DICOMExtendedNegotiation(
                    sopClassUID: "1.2.840.10008.5.1.4.1.2.1.1", applicationInformation: [1, 0, 1])],
                commonExtendedNegotiations: [DICOMCommonExtendedNegotiation(
                    sopClassUID: "1.2.840.10008.5.1.4.1.1.88.22", serviceClassUID: "1.2.840.10008.4.2",
                    relatedGeneralSOPClassUIDs: ["1.2.840.10008.5.1.4.1.1.88.11"])],
                userIdentity: .username("alice", passcode: "s3cret", positiveResponseRequested: true)))
    }

    private var expectedAccept: DICOMAssociateAccept {
        DICOMAssociateAccept(
            calledAETitle: "ANY-SCP", callingAETitle: "CALLING",
            presentationContexts: [
                DICOMPresentationContextResult(id: 1, result: .acceptance, transferSyntax: "1.2.840.10008.1.2"),
                DICOMPresentationContextResult(
                    id: 3, result: .abstractSyntaxNotSupported, transferSyntax: "1.2.840.10008.1.2"),
            ],
            userInformation: DICOMUserInformation(
                maximumLength: 32768, implementationClassUID: Self.implementationClassUID,
                roleSelections: [DICOMRoleSelection(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", scuRole: false, scpRole: true)],
                userIdentityServerResponse: Array("OK-TOKEN".utf8)))
    }

    private var expectedData: [DICOMPresentationDataValue] {
        [
            DICOMPresentationDataValue(
                presentationContextID: 1, isCommand: true, isLast: true,
                data: ByteBufferAllocator().buffer(bytes: [0x00, 0x01, 0x02])),
            DICOMPresentationDataValue(
                presentationContextID: 3, isCommand: false, isLast: false,
                data: ByteBufferAllocator().buffer(bytes: [0x02, 0xAA])),
        ]
    }

    private var expected: [String: DICOMPDU] {
        [
            "rq": .associateRequest(expectedRequest),
            "ac": .associateAccept(expectedAccept),
            "rj": .associateReject(DICOMAssociateReject(result: .permanent, reason: .calledAETitleNotRecognized)),
            "pdata": .data(expectedData),
            "releaserq": .releaseRequest,
            "releaserp": .releaseResponse,
            "abort": .abort(DICOMAbort(source: .serviceProvider, reason: .invalidPDUParameterValue)),
        ]
    }

    func testPynetdicomPDUsDecodeAndReencodeByteForByte() throws {
        for (name, hex) in Self.pynetdicom {
            let bytes = buffer(hex)
            let pdu = try decode(bytes)
            XCTAssertEqual(pdu, expected[name], name)
            XCTAssertEqual(try DICOMPDUCodec.encode(pdu), bytes, name)
        }
    }

    func testFramingAcrossChunksAndConcatenatedPDUs() throws {
        var stream = ByteBufferAllocator().buffer(capacity: 1024)
        for name in ["rq", "pdata", "releaserq", "ac", "abort"] {
            var bytes = buffer(Self.pynetdicom[name]!)
            stream.writeBuffer(&bytes)
        }
        // Fed byte by byte, then all at once.
        for chunk in [1, 7, stream.readableBytes] {
            var decoder = DICOMPDUFrameDecoder(maximumDataLength: 1 << 20)
            var pending = ByteBufferAllocator().buffer(capacity: 1024)
            var decoded: [DICOMPDU] = []
            var input = stream
            while input.readableBytes > 0 {
                var slice = input.readSlice(length: min(chunk, input.readableBytes))!
                pending.writeBuffer(&slice)
                while let pdu = try decoder.decode(buffer: &pending) { decoded.append(pdu) }
            }
            XCTAssertEqual(decoded, ["rq", "pdata", "releaserq", "ac", "abort"].map { expected[$0]! }, "\(chunk)")
        }
    }

    func testOversizedAndUnknownPDUsAreRefusedFromTheirHeader() throws {
        // A P-DATA-TF announcing 1 MiB, of which only the header arrived.
        var header = ByteBufferAllocator().buffer(bytes: [0x04, 0x00, 0x00, 0x10, 0x00, 0x00])
        var decoder = DICOMPDUFrameDecoder(maximumDataLength: 16384)
        XCTAssertThrowsError(try decoder.decode(buffer: &header)) {
            XCTAssertEqual(($0 as? DICOMPDUError)?.reason, .invalidPDUParameterValue)
        }
        var associate = ByteBufferAllocator().buffer(bytes: [0x01, 0x00, 0x00, 0x20, 0x00, 0x00])
        decoder = DICOMPDUFrameDecoder(maximumDataLength: 16384, maximumAssociateLength: 4096)
        XCTAssertThrowsError(try decoder.decode(buffer: &associate))
        var unknown = ByteBufferAllocator().buffer(bytes: [0x09, 0x00, 0x00, 0x00, 0x00, 0x04, 0, 0, 0, 0])
        XCTAssertThrowsError(try decoder.decode(buffer: &unknown)) {
            XCTAssertEqual(($0 as? DICOMPDUError)?.reason, .unrecognizedPDU)
        }
        var release = ByteBufferAllocator().buffer(bytes: [0x05, 0x00, 0x00, 0x00, 0x00, 0x05, 0, 0, 0, 0, 0])
        XCTAssertThrowsError(try decoder.decode(buffer: &release))
        // An incomplete PDU waits for more bytes.
        var partial = buffer(String(Self.pynetdicom["rq"]!.prefix(40)))
        XCTAssertNil(try decoder.decode(buffer: &partial))
    }

    func testMalformedPDUsAreRejected() throws {
        func body(_ hex: String) -> ByteBuffer { buffer(hex) }
        // P-DATA-TF without PDV, with a short PDV, and with an overrunning one.
        XCTAssertThrowsError(try DICOMPDUCodec.decode(type: 0x04, body: body("")))
        XCTAssertThrowsError(try DICOMPDUCodec.decode(type: 0x04, body: body("0000000101")))
        XCTAssertThrowsError(try DICOMPDUCodec.decode(type: 0x04, body: body("000000100103")))
        // A-ASSOCIATE-RJ with an undefined result.
        XCTAssertThrowsError(try DICOMPDUCodec.decode(type: 0x03, body: body("00030107")))

        // A-ASSOCIATE-RQ without presentation context or user information.
        var request = expectedRequest
        request.presentationContexts = []
        XCTAssertThrowsError(try DICOMPDUCodec.encode(.associateRequest(request)))
        let full = [UInt8](try DICOMPDUCodec.encode(.associateRequest(expectedRequest)).readableBytesView)
        // Cut inside the user information item: the item length overruns.
        var cut = Array(full.prefix(full.count - 3))
        cut.replaceSubrange(2..<6, with: withUnsafeBytes(of: UInt32(cut.count - 6).bigEndian, Array.init))
        var truncated = ByteBufferAllocator().buffer(bytes: cut)
        var decoder = DICOMPDUFrameDecoder(maximumDataLength: 1 << 20)
        XCTAssertThrowsError(try decoder.decode(buffer: &truncated))

        // Invalid AE titles and UIDs are refused when encoding.
        for title in ["", "                ", "ABCDEFGHIJKLMNOPQ", "BACK\\SLASH"] {
            request = expectedRequest
            request.callingAETitle = title
            XCTAssertThrowsError(try DICOMPDUCodec.encode(.associateRequest(request)), title)
        }
        request = expectedRequest
        request.presentationContexts[0].abstractSyntax = "1.2..3"
        XCTAssertThrowsError(try DICOMPDUCodec.encode(.associateRequest(request)))
    }

    func testAETitlesArePaddedAndTrimmed() throws {
        var request = expectedRequest
        request.calledAETitle = " A"
        let bytes = [UInt8](try DICOMPDUCodec.encode(.associateRequest(request)).readableBytesView)
        XCTAssertEqual(Array(bytes[10..<26]), Array(" A".utf8) + Array(repeating: 0x20, count: 14))
        guard case .associateRequest(let decoded) = try decode(ByteBufferAllocator().buffer(bytes: bytes)) else {
            return XCTFail("not an A-ASSOCIATE-RQ")
        }
        XCTAssertEqual(decoded.calledAETitle, "A")
    }

    func testUnknownUserInformationSubItemsArePreserved() throws {
        var request = expectedRequest
        request.userInformation.unknownSubItems = [DICOMUnknownItem(type: 0x7F, value: [1, 2, 3])]
        let bytes = try DICOMPDUCodec.encode(.associateRequest(request))
        XCTAssertEqual(try decode(bytes), .associateRequest(request))
    }

    func testRandomCorruptionNeverCrashes() throws {
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
        for name in ["rq", "ac", "pdata"] {
            let original = [UInt8](buffer(Self.pynetdicom[name]!).readableBytesView)
            for _ in 0..<2000 {
                var bytes = original
                for _ in 0..<(1 + Int(next() % 4)) {
                    bytes[Int(next() % UInt64(bytes.count))] = UInt8(truncatingIfNeeded: next())
                }
                var input = ByteBufferAllocator().buffer(bytes: bytes)
                var decoder = DICOMPDUFrameDecoder(maximumDataLength: 1 << 16, maximumAssociateLength: 1 << 16)
                _ = try? decoder.decode(buffer: &input)
            }
        }
    }
}
