import XCTest
import NIOCore
@testable import DcmSwift

/// DIMSE command sets (PS3.7 Annex E), message fragmentation and
/// reassembly (PS3.8 9.3.5), and data set coding. The reference command
/// sets were encoded by pynetdicom 3.0.4.
final class DcmSwiftNetworkDIMSETests: XCTestCase {
    private func data(_ hex: String) -> Data {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return Data(bytes)
    }

    func testCommandSetsMatchPynetdicom() throws {
        var echo = DICOMCommand(field: .cEchoRequest)
        echo.messageID = 7
        echo.affectedSOPClassUID = "1.2.840.10008.1.1"

        var store = DICOMCommand(field: .cStoreRequest, hasDataSet: true)
        store.messageID = 3
        store.affectedSOPClassUID = "1.2.840.10008.5.1.4.1.1.2"
        store.affectedSOPInstanceUID = "1.2.3.4.5"
        store.priority = 0
        store.moveOriginatorAETitle = "MOVER"
        store.moveOriginatorMessageID = 9

        var find = DICOMCommand(field: .cFindResponse, hasDataSet: true)
        find.messageIDBeingRespondedTo = 5
        find.affectedSOPClassUID = "1.2.840.10008.5.1.4.1.2.2.1"
        find.status = 0xFF00

        var move = DICOMCommand(field: .cMoveResponse)
        move.messageIDBeingRespondedTo = 6
        move.affectedSOPClassUID = "1.2.840.10008.5.1.4.1.2.2.2"
        move.status = 0xB000
        move.remainingSuboperations = 0
        move.completedSuboperations = 10
        move.failedSuboperations = 2
        move.warningSuboperations = 1
        move.errorComment = "Some failed"

        var cancel = DICOMCommand(field: .cCancelRequest)
        cancel.messageIDBeingRespondedTo = 5

        var action = DICOMCommand(field: .nActionRequest, hasDataSet: true)
        action.messageID = 11
        action.requestedSOPClassUID = "1.2.840.10008.1.20.1"
        action.requestedSOPInstanceUID = "1.2.840.10008.1.20.1.1"
        action.actionTypeID = 1

        let references: [(DICOMCommand, String)] = [
            (echo, "0000000004000000380000000000020012000000312e322e3834302e31303030382e312e3100000000010200000030000000100102000000070000000008020000000101"),
            (store, "000000000400000074000000000002001a000000312e322e3834302e31303030382e352e312e342e312e312e320000000001020000000100000010010200000003000000000702000000000000000008020000000100000000100a000000312e322e332e342e350000003010060000004d4f5645522000003110020000000900"),
            (find, "00000000040000004c000000000002001c000000312e322e3834302e31303030382e352e312e342e312e322e322e3100000000010200000020800000200102000000050000000008020000000100000000090200000000ff"),
            (move, "000000000400000088000000000002001c000000312e322e3834302e31303030382e352e312e342e312e322e322e3200000000010200000021800000200102000000060000000008020000000101000000090200000000b0000002090c000000536f6d65206661696c6564200000201002000000000000002110020000000a000000221002000000020000002310020000000100"),
            (cancel, "00000000040000001e0000000000000102000000ff0f0000200102000000050000000008020000000101"),
            (action, "0000000004000000620000000000030014000000312e322e3834302e31303030382e312e32302e310000000102000000300100001001020000000b00000000080200000001000000011016000000312e322e3834302e31303030382e312e32302e312e3100000810020000000100"),
        ]
        for (command, hex) in references {
            XCTAssertEqual(try command.encoded(), data(hex), "\(command.field)")
            XCTAssertEqual(try DICOMCommand(encoded: data(hex)), command, "\(command.field)")
        }
        XCTAssertEqual(DICOMCommand.Field.cFindRequest.response, .cFindResponse)
        XCTAssertEqual(DICOMStatus(code: 0xFF01).category, .pending)
        XCTAssertEqual(DICOMStatus(code: 0xB000).category, .warning)
        XCTAssertEqual(DICOMStatus(code: 0xA700).category, .failure)
        XCTAssertEqual(DICOMStatus(code: 0xFE00).category, .cancel)
    }

    func testMalformedCommandSetsAreRejected() throws {
        var echo = DICOMCommand(field: .cEchoRequest)
        echo.messageID = 1
        let good = [UInt8](try echo.encoded())
        // Element outside group 0000, overrunning length, repeated element.
        var wrongGroup = good
        wrongGroup[12] = 8
        XCTAssertThrowsError(try DICOMCommand(encoded: Data(wrongGroup)))
        XCTAssertThrowsError(try DICOMCommand(encoded: Data(good.dropLast(1))))
        XCTAssertThrowsError(try DICOMCommand(encoded: Data(good + good.suffix(10))))
        // Missing Command Field, a US of 4 bytes, too long a command.
        XCTAssertThrowsError(try DICOMCommand(encoded: Data(good.prefix(12))))
        XCTAssertThrowsError(try DICOMCommand(encoded: Data(good), maximumLength: 8))
        var invalid = DICOMCommand(field: .cMoveRequest)
        invalid.moveDestination = "BAD\\AE"
        XCTAssertThrowsError(try invalid.encoded())
        invalid.moveDestination = nil
        invalid.affectedSOPClassUID = "1.2.x"
        XCTAssertThrowsError(try invalid.encoded())
    }

    private func message(length: Int) -> DICOMMessage {
        var command = DICOMCommand(field: .cStoreRequest, hasDataSet: true)
        command.messageID = 42
        command.affectedSOPClassUID = "1.2.840.10008.5.1.4.1.1.7"
        command.affectedSOPInstanceUID = "1.2.3"
        command.priority = 0
        let bytes = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 * 7) })
        return DICOMMessage(presentationContextID: 5, command: command, dataSet: DICOMDataSetPayload(data: bytes))
    }

    func testFragmentationAndReassemblyRespectTheMaximumLength() throws {
        for (length, maximum) in [(0, 0), (1000, 16), (100_000, 4096), (70_000, 0)] {
            let original = message(length: length)
            let pdus = Array(try DICOMMessageFragmenter(original, maximumLength: UInt32(maximum)))
            var assembler = DICOMMessageAssembler()
            var received: [DICOMMessage] = []
            for pdu in pdus {
                guard case .data(let values) = pdu else { return XCTFail("not P-DATA-TF") }
                let encoded = try DICOMPDUCodec.encode(pdu)
                if maximum > 0 { XCTAssertLessThanOrEqual(encoded.readableBytes - 6, maximum) }
                for value in values {
                    if let complete = try assembler.append(value) { received.append(complete) }
                }
            }
            XCTAssertEqual(received.count, 1, "\(length)")
            XCTAssertEqual(received.first?.command, original.command)
            XCTAssertEqual(try received.first?.dataSet?.data(), try original.dataSet?.data())
            XCTAssertTrue(assembler.isIdle)
        }
        // A command alone, without data set.
        var echo = DICOMCommand(field: .cEchoRequest)
        echo.messageID = 1
        var assembler = DICOMMessageAssembler()
        let echoPDUs = Array(try DICOMMessageFragmenter(DICOMMessage(presentationContextID: 1, command: echo), maximumLength: 0))
        XCTAssertEqual(echoPDUs.count, 1)
        guard case .data(let values) = echoPDUs[0] else { return XCTFail("not P-DATA-TF") }
        XCTAssertEqual(try assembler.append(values[0])?.command, echo)
        // The command and the payload must agree.
        XCTAssertThrowsError(try DICOMMessageFragmenter(
            DICOMMessage(presentationContextID: 1, command: echo, dataSet: DICOMDataSetPayload(data: Data([1]))),
            maximumLength: 0))
        XCTAssertThrowsError(try DICOMMessageFragmenter(message(length: 10), maximumLength: 7))
    }

    func testLargeDataSetsSpillToATemporaryFileThatIsRemoved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func files() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: directory.path) }

        let original = message(length: 50_000)
        var payloadFile: URL?
        do {
            var assembler = DICOMMessageAssembler(memoryLimit: 10_000, temporaryDirectory: directory)
            var received: DICOMMessage?
            for case .data(let values) in try DICOMMessageFragmenter(original, maximumLength: 4096) {
                for value in values { received = try assembler.append(value) ?? received }
            }
            let payload = try XCTUnwrap(received?.dataSet)
            payloadFile = payload.fileURL
            XCTAssertNotNil(payloadFile)
            XCTAssertEqual(try payload.data(), try original.dataSet?.data())
            XCTAssertEqual(try files().count, 1)
        }
        XCTAssertEqual(try files(), [], "the payload removes its file")

        // An interrupted transfer removes its partial file too.
        do {
            var assembler = DICOMMessageAssembler(memoryLimit: 1000, temporaryDirectory: directory)
            for case .data(let values) in Array(try DICOMMessageFragmenter(original, maximumLength: 4096)).prefix(5) {
                for value in values { _ = try assembler.append(value) }
            }
            XCTAssertEqual(try files().count, 1)
        }
        XCTAssertEqual(try files(), [])
    }

    func testOutOfOrderAndOversizedFragmentsAbort() throws {
        let pdus = Array(try DICOMMessageFragmenter(message(length: 5000), maximumLength: 1024))
        let values = pdus.flatMap { pdu -> [DICOMPresentationDataValue] in
            guard case .data(let values) = pdu else { return [] }
            return values
        }
        // A data set fragment first.
        var assembler = DICOMMessageAssembler()
        XCTAssertThrowsError(try assembler.append(values[1]))
        // Another presentation context in the middle.
        assembler = DICOMMessageAssembler()
        _ = try assembler.append(values[0])
        var foreign = values[1]
        foreign.presentationContextID = 7
        XCTAssertThrowsError(try assembler.append(foreign))
        // A command fragment while a data set is expected.
        assembler = DICOMMessageAssembler()
        _ = try assembler.append(values[0])
        XCTAssertThrowsError(try assembler.append(values[0]))
        // Data set and command limits.
        assembler = DICOMMessageAssembler(maximumDataSetLength: 2000)
        XCTAssertThrowsError(try values.forEach { _ = try assembler.append($0) })
        assembler = DICOMMessageAssembler(maximumCommandLength: 50)
        XCTAssertThrowsError(try assembler.append(values[0]))
    }

    func testDataSetsRoundTripInEveryNetworkTransferSyntax() throws {
        let dataset = DataSet()
        _ = dataset.set(value: "Doe^Jane", forTagName: "PatientName")
        _ = dataset.set(value: "1.2.840.10008.5.1.4.1.1.7", forTagName: "SOPClassUID")
        _ = dataset.set(value: "1.2.3.4", forTagName: "SOPInstanceUID")
        _ = dataset.set(value: UInt16(512), forTagName: "Rows")
        for uid in [TransferSyntax.implicitVRLittleEndian, TransferSyntax.explicitVRLittleEndian,
                    TransferSyntax.explicitVRBigEndian, TransferSyntax.deflatedExplicitVRLittleEndian] {
            let encoded = try DICOMDataSetCoding.encode(dataset, transferSyntax: uid)
            let decoded = try DICOMDataSetCoding.decode(encoded, transferSyntax: uid)
            XCTAssertEqual(decoded.string(forTag: "PatientName"), "Doe^Jane", uid)
            XCTAssertEqual(decoded.string(forTag: "SOPInstanceUID"), "1.2.3.4", uid)
            XCTAssertEqual(decoded.integer16(forTag: "Rows"), 512, uid)
        }
    }
}
