import XCTest
import NIOCore
import NIOPosix
import NIOConcurrencyHelpers
@testable import DcmSwift

/// Client and server over the loopback interface.
final class DcmSwiftNetworkIntegrationTests: XCTestCase {
    // MARK: Fixtures

    /// Stores received instances in memory.
    final class MemoryStorage: DICOMStorageService, @unchecked Sendable {
        let received = NIOLockedValueBox<[DICOMReceivedInstance]>([])
        var status = DICOMStatus.success

        func store(_ instance: DICOMReceivedInstance, context: DICOMServiceContext) async throws -> DICOMStatus {
            received.withLockedValue { $0.append(instance) }
            return status
        }
    }

    /// Answers C-FIND with `count` matches, slowly enough to be cancelled.
    final class CountingQuery: DICOMQueryService, @unchecked Sendable {
        let count: Int
        let sawCancel = NIOLockedValueBox(false)
        init(count: Int) { self.count = count }

        func find(_ identifier: DataSet, informationModel: String, context: DICOMServiceContext)
            async throws -> AsyncThrowingStream<DataSet, Error> {
            let count = self.count
            let sawCancel = self.sawCancel
            let level = identifier.string(forTag: "QueryRetrieveLevel")
            return AsyncThrowingStream { continuation in
                Task {
                    for index in 0..<count {
                        if await context.isCancelled {
                            sawCancel.withLockedValue { $0 = true }
                            break
                        }
                        let match = DataSet()
                        _ = match.set(value: level ?? "STUDY", forTagName: "QueryRetrieveLevel")
                        _ = match.set(value: "1.2.3.\(index)", forTagName: "StudyInstanceUID")
                        continuation.yield(match)
                        try? await Task.sleep(nanoseconds: 2_000_000)
                    }
                    continuation.finish()
                }
            }
        }
    }

    /// Retrieves fixed instances; knows one C-MOVE destination.
    struct FixedRetrieve: DICOMRetrieveService {
        let items: [DICOMRetrieveItem]
        let destinations: [String: DICOMRemoteNode]

        func retrieve(_ identifier: DataSet, informationModel: String, context: DICOMServiceContext)
            async throws -> [DICOMRetrieveItem] { items }

        func destination(for aeTitle: String) async -> DICOMRemoteNode? { destinations[aeTitle] }
    }

    private func instance(_ index: Int, sopClass: String = "1.2.840.10008.5.1.4.1.1.7") -> DataSet {
        let dataSet = DataSet()
        _ = dataSet.set(value: sopClass, forTagName: "SOPClassUID")
        _ = dataSet.set(value: "1.2.826.0.1.99.\(index)", forTagName: "SOPInstanceUID")
        _ = dataSet.set(value: "Doe^Jane", forTagName: "PatientName")
        _ = dataSet.set(value: UInt16(4), forTagName: "Rows")
        return dataSet
    }

    private func configuration(_ aeTitle: String = "SCP") -> DICOMServerConfiguration {
        DICOMServerConfiguration(
            aeTitle: aeTitle, host: "127.0.0.1", port: 0,
            timeouts: DICOMNetworkTimeouts(connect: .seconds(5), artim: .seconds(5), idle: .seconds(20)))
    }

    /// Runs `server` while `body` runs, then stops it.
    private func withServer<T>(
        _ server: DICOMServer, _ body: (Int) async throws -> T
    ) async throws -> T {
        let ready = AsyncStream<Int>.makeStream()
        let task = Task { try await server.run { ready.continuation.yield($0) } }
        var iterator = ready.stream.makeAsyncIterator()
        guard let port = await iterator.next() else { throw DICOMNetworkError.connectionClosed }
        do {
            let result = try await body(port)
            task.cancel()
            _ = try? await task.value
            return result
        } catch {
            task.cancel()
            _ = try? await task.value
            throw error
        }
    }

    private func client(_ aeTitle: String = "SCU", tls: DICOMTLSConfiguration? = nil) throws -> DICOMClient {
        try DICOMClient(configuration: DICOMClientConfiguration(
            aeTitle: aeTitle, timeouts: DICOMNetworkTimeouts(connect: .seconds(5), artim: .seconds(5), idle: .seconds(20)),
            tls: tls))
    }

    // MARK: Tests

    func testEchoAndRelease() async throws {
        let server = try DICOMServer(configuration: configuration())
        try await withServer(server) { port in
            let status = try await client().withAssociation(
                to: DICOMRemoteNode(aeTitle: "SCP", host: "127.0.0.1", port: port),
                presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.verification])
            ) { association in
                XCTAssertEqual(association.negotiated.acceptorImplementationClassUID, DICOMImplementation.classUID)
                try await association.echo()
                return try await association.echo()
            }
            XCTAssertEqual(status, .success)
        }
        XCTAssertEqual(server.activeAssociations, 0)
    }

    func testStoreKeepsTheSentEncoding() async throws {
        let storage = MemoryStorage()
        let server = try DICOMServer(configuration: configuration(), storage: storage)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // A Part 10 file on disk, streamed as is.
        let source = directory.appendingPathComponent("source.dcm")
        let fileItem = try DICOMRetrieveItem(dataSet: instance(2), transferSyntaxUID: TransferSyntax.implicitVRLittleEndian)
        try DICOMReceivedInstance(
            sopClassUID: fileItem.sopClassUID, sopInstanceUID: fileItem.sopInstanceUID,
            transferSyntaxUID: fileItem.transferSyntaxUID, payload: fileItem.payload, moveOriginatorAETitle: nil,
            moveOriginatorMessageID: nil, sourceAETitle: "TEST").write(to: source)

        try await withServer(server) { port in
            try await client().withAssociation(
                to: DICOMRemoteNode(aeTitle: "SCP", host: "127.0.0.1", port: port),
                presentationContexts: [
                    DICOMPresentationContextProposal(
                        id: 1, abstractSyntax: "1.2.840.10008.5.1.4.1.1.7",
                        transferSyntaxes: [TransferSyntax.implicitVRLittleEndian, TransferSyntax.explicitVRLittleEndian]),
                    DICOMPresentationContextProposal(
                        id: 3, abstractSyntax: "1.2.840.10008.5.1.4.1.1.7",
                        transferSyntaxes: [TransferSyntax.explicitVRLittleEndian]),
                ]
            ) { association in
                XCTAssertEqual(association.negotiated.presentationContexts[1]?.transferSyntax,
                               TransferSyntax.implicitVRLittleEndian, "the requestor's first proposal")
                let first = try await association.store(self.instance(1))
                let second = try await association.store(file: source)
                XCTAssertEqual(first, .success)
                XCTAssertEqual(second, .success)
            }
        }
        let received = storage.received.withLockedValue { $0 }
        XCTAssertEqual(received.map(\.sopInstanceUID), ["1.2.826.0.1.99.1", "1.2.826.0.1.99.2"])
        XCTAssertEqual(received[0].transferSyntaxUID, TransferSyntax.explicitVRLittleEndian)
        XCTAssertEqual(received[1].transferSyntaxUID, TransferSyntax.implicitVRLittleEndian)
        XCTAssertEqual(try received[1].dataSet().string(forTag: "PatientName"), "Doe^Jane")
        XCTAssertEqual(received[1].sourceAETitle, "SCU")

        // The received instance becomes a Part 10 file with the same bytes.
        let written = directory.appendingPathComponent("received.dcm")
        try received[1].write(to: written)
        let header = try DICOMPart10Header.read(written)
        XCTAssertEqual(header.transferSyntaxUID, TransferSyntax.implicitVRLittleEndian)
        XCTAssertEqual(header.dataSetLength, fileItem.payload.length)
        let file = DicomFile(forPath: written.path)
        XCTAssertEqual(file?.dataset.string(forTag: "SOPInstanceUID"), "1.2.826.0.1.99.2")
    }

    /// An uncompressed instance goes to an uncompressed context even when a
    /// compressed context of its class has a lower ID.
    func testStoreConvertsOnAnUncompressedContextOfTheClass() async throws {
        let storage = MemoryStorage()
        let server = try DICOMServer(configuration: configuration(), storage: storage)
        let sopClass = "1.2.840.10008.5.1.4.1.1.7"
        try await withServer(server) { port in
            try await client().withAssociation(
                to: DICOMRemoteNode(aeTitle: "SCP", host: "127.0.0.1", port: port),
                presentationContexts: [
                    DICOMPresentationContextProposal(id: 1, abstractSyntax: sopClass, transferSyntaxes: ["1.2.840.10008.1.2.5"]),
                    DICOMPresentationContextProposal(
                        id: 3, abstractSyntax: sopClass, transferSyntaxes: [TransferSyntax.implicitVRLittleEndian]),
                ]
            ) { association in
                let status = try await association.store(self.instance(5))
                XCTAssertEqual(status, .success)
            }
        }
        let received = storage.received.withLockedValue { $0 }
        XCTAssertEqual(received.map(\.transferSyntaxUID), [TransferSyntax.implicitVRLittleEndian])
        XCTAssertEqual(try received.first?.dataSet().string(forTag: "PatientName"), "Doe^Jane")
    }

    func testFindStreamsMatchesAndCancels() async throws {
        let query = CountingQuery(count: 500)
        let server = try DICOMServer(configuration: configuration(), query: query)
        try await withServer(server) { port in
            try await client().withAssociation(
                to: DICOMRemoteNode(aeTitle: "SCP", host: "127.0.0.1", port: port),
                presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.studyRootFind, DICOMSOPClass.verification])
            ) { association in
                let identifier = DataSet()
                _ = identifier.set(value: "STUDY", forTagName: "QueryRetrieveLevel")
                _ = identifier.set(value: "", forTagName: "StudyInstanceUID")
                var seen: [String] = []
                for try await match in association.find(identifier) {
                    seen.append(match.string(forTag: "StudyInstanceUID") ?? "")
                    if seen.count == 3 { break }
                }
                XCTAssertEqual(seen, ["1.2.3.0", "1.2.3.1", "1.2.3.2"])
                // The association stays usable after the cancellation.
                try await Task.sleep(nanoseconds: 100_000_000)
                let status = try await association.echo()
                XCTAssertEqual(status, .success)
            }
        }
        XCTAssertTrue(query.sawCancel.withLockedValue { $0 })

        // A complete query.
        let small = CountingQuery(count: 4)
        try await withServer(try DICOMServer(configuration: configuration(), query: small)) { port in
            let count = try await client().withAssociation(
                to: DICOMRemoteNode(aeTitle: "SCP", host: "127.0.0.1", port: port),
                presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.studyRootFind])
            ) { association in
                var count = 0
                for try await _ in association.find(DataSet()) { count += 1 }
                return count
            }
            XCTAssertEqual(count, 4)
        }
    }

    func testMoveSendsToTheDestinationAndGetToTheRequestor() async throws {
        let items = try (0..<3).map { try DICOMRetrieveItem(dataSet: instance($0)) }
        let destinationStorage = MemoryStorage()
        let destination = try DICOMServer(configuration: configuration("DEST"), storage: destinationStorage)
        try await withServer(destination) { destinationPort in
            let archive = try DICOMServer(
                configuration: configuration("ARCHIVE"),
                retrieve: FixedRetrieve(items: items, destinations: [
                    "DEST": DICOMRemoteNode(aeTitle: "DEST", host: "127.0.0.1", port: destinationPort),
                ]))
            try await withServer(archive) { port in
                let remote = DICOMRemoteNode(aeTitle: "ARCHIVE", host: "127.0.0.1", port: port)
                let identifier = DataSet()
                _ = identifier.set(value: "STUDY", forTagName: "QueryRetrieveLevel")

                // C-MOVE to a known and an unknown destination.
                let progress = NIOLockedValueBox<[DICOMRetrieveProgress]>([])
                let result = try await client().withAssociation(
                    to: remote, presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.studyRootMove])
                ) { association in
                    do {
                        _ = try await association.move(identifier, destination: "NOWHERE")
                        XCTFail("unknown destination accepted")
                    } catch let error as DICOMServiceError {
                        XCTAssertEqual(error.status, .moveDestinationUnknown)
                    }
                    return try await association.move(identifier, destination: "DEST") { update in
                        progress.withLockedValue { $0.append(update) }
                    }
                }
                XCTAssertEqual(result.status, .success)
                XCTAssertEqual(result.progress, DICOMRetrieveProgress(remaining: 0, completed: 3))
                XCTAssertEqual(progress.withLockedValue { $0.map(\.remaining) }, [2, 1])
                XCTAssertEqual(destinationStorage.received.withLockedValue { $0.map(\.moveOriginatorAETitle) },
                               ["SCU", "SCU", "SCU"])

                // C-GET: the instances come back on the same association.
                let local = MemoryStorage()
                let sopClass = "1.2.840.10008.5.1.4.1.1.7"
                let got = try await client().withAssociation(
                    to: remote,
                    presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.studyRootGet, sopClass]),
                    roleSelections: [DICOMRoleSelection(sopClassUID: sopClass, scuRole: false, scpRole: true)],
                    storage: local
                ) { association in
                    try await association.get(identifier)
                }
                XCTAssertEqual(got.status, .success)
                XCTAssertEqual(got.progress.completed, 3)
                XCTAssertEqual(local.received.withLockedValue { $0.map(\.sopInstanceUID) }, items.map(\.sopInstanceUID))
            }
        }
    }

    func testRejectionsAndLimits() async throws {
        var limited = configuration()
        limited.maximumAssociations = 1
        limited.allowedCallingAETitles = ["SCU"]
        let server = try DICOMServer(configuration: limited)
        try await withServer(server) { port in
            let contexts = DICOMPresentationContextProposal.proposals(abstractSyntaxes: [DICOMSOPClass.verification])
            do {
                try await client().withAssociation(
                    to: DICOMRemoteNode(aeTitle: "WRONG", host: "127.0.0.1", port: port), presentationContexts: contexts
                ) { _ in }
                XCTFail("wrong called AE title accepted")
            } catch DICOMNetworkError.associationRejected(let reject) {
                XCTAssertEqual(reject.reason, .calledAETitleNotRecognized)
            }
            do {
                try await client("STRANGER").withAssociation(
                    to: DICOMRemoteNode(aeTitle: "SCP", host: "127.0.0.1", port: port), presentationContexts: contexts
                ) { _ in }
                XCTFail("unknown calling AE title accepted")
            } catch DICOMNetworkError.associationRejected(let reject) {
                XCTAssertEqual(reject.reason, .callingAETitleNotRecognized)
            }
            // A second association while one is open.
            try await client().withAssociation(
                to: DICOMRemoteNode(aeTitle: "SCP", host: "127.0.0.1", port: port), presentationContexts: contexts
            ) { _ in
                do {
                    try await self.client().withAssociation(
                        to: DICOMRemoteNode(aeTitle: "SCP", host: "127.0.0.1", port: port), presentationContexts: contexts
                    ) { _ in }
                    XCTFail("limit not enforced")
                } catch DICOMNetworkError.associationRejected(let reject) {
                    XCTAssertEqual(reject.result, .transient)
                    XCTAssertEqual(reject.reason, .localLimitExceeded)
                }
            }
            // An operation without accepted context.
            try await client().withAssociation(
                to: DICOMRemoteNode(aeTitle: "SCP", host: "127.0.0.1", port: port), presentationContexts: contexts
            ) { association in
                do {
                    _ = try await association.store(self.instance(9))
                    XCTFail("store without context")
                } catch DICOMNetworkError.noPresentationContext {}
            }
        }
    }

    /// Raw TCP peers: silence, garbage, and an abrupt close.
    func testMisbehavingPeersDoNotDisturbTheServer() async throws {
        var quick = configuration()
        quick.timeouts.artim = .milliseconds(300)
        let server = try DICOMServer(configuration: quick)
        try await withServer(server) { port in
            let group = MultiThreadedEventLoopGroup.singleton
            func raw(_ bytes: [UInt8]) async throws -> [UInt8] {
                let channel = try await ClientBootstrap(group: group).connect(host: "127.0.0.1", port: port) { channel in
                    channel.eventLoop.makeCompletedFuture {
                        try NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrappingChannelSynchronously: channel)
                    }
                }
                return try await channel.executeThenClose { inbound, outbound in
                    if !bytes.isEmpty { try await outbound.write(ByteBuffer(bytes: bytes)) }
                    var received: [UInt8] = []
                    for try await chunk in inbound { received += Array(chunk.readableBytesView) }
                    return received
                }
            }
            // Silence: closed after ARTIM, without answer.
            let start = Date()
            let silent = try await raw([])
            XCTAssertEqual(silent, [])
            XCTAssertLessThan(Date().timeIntervalSince(start), 5)
            // An unknown PDU type: A-ABORT, then close.
            let unknown = try await raw([0x09, 0, 0, 0, 0, 0])
            XCTAssertEqual(Array(unknown.prefix(1)), [0x07])
            // An oversized A-ASSOCIATE-RQ header.
            let oversized = try await raw([0x01, 0, 0x7F, 0xFF, 0xFF, 0xFF])
            XCTAssertEqual(Array(oversized.prefix(1)), [0x07])
            // P-DATA before association: A-ABORT.
            let early = try await raw([0x04, 0, 0, 0, 0, 6, 0, 0, 0, 2, 1, 3])
            XCTAssertEqual(Array(early.prefix(1)), [0x07])

            // The server still serves well-behaved peers.
            let status = try await client().withAssociation(
                to: DICOMRemoteNode(aeTitle: "SCP", host: "127.0.0.1", port: port),
                presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.verification])
            ) { try await $0.echo() }
            XCTAssertEqual(status, .success)
        }
        XCTAssertEqual(server.activeAssociations, 0)
    }

    func testAbortReachesThePeerAndTheServerRecovers() async throws {
        let server = try DICOMServer(configuration: configuration())
        try await withServer(server) { port in
            struct Stop: Error {}
            let remote = DICOMRemoteNode(aeTitle: "SCP", host: "127.0.0.1", port: port)
            let contexts = DICOMPresentationContextProposal.proposals(abstractSyntaxes: [DICOMSOPClass.verification])
            do {
                try await client().withAssociation(to: remote, presentationContexts: contexts) { association in
                    try await association.echo()
                    throw Stop()
                }
                XCTFail("error swallowed")
            } catch is Stop {}
            // Cancelling the task aborts the association too.
            let task = Task {
                try await self.client().withAssociation(to: remote, presentationContexts: contexts) { association in
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                }
            }
            try await Task.sleep(nanoseconds: 200_000_000)
            task.cancel()
            _ = try? await task.value
            try await Task.sleep(nanoseconds: 200_000_000)
            XCTAssertEqual(server.activeAssociations, 0)
            let status = try await client().withAssociation(to: remote, presentationContexts: contexts) {
                try await $0.echo()
            }
            XCTAssertEqual(status, .success)
        }
    }

    func testIdleTimeoutAbortsAWaitingOperation() async throws {
        // A storage service that never answers in time.
        struct Slow: DICOMStorageService {
            func store(_ instance: DICOMReceivedInstance, context: DICOMServiceContext) async throws -> DICOMStatus {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                return .success
            }
        }
        let server = try DICOMServer(configuration: configuration(), storage: Slow())
        try await withServer(server) { port in
            let impatient = try DICOMClient(configuration: DICOMClientConfiguration(
                aeTitle: "SCU", timeouts: DICOMNetworkTimeouts(connect: .seconds(5), artim: .seconds(5), idle: .milliseconds(500))))
            do {
                try await impatient.withAssociation(
                    to: DICOMRemoteNode(aeTitle: "SCP", host: "127.0.0.1", port: port),
                    presentationContexts: .proposals(abstractSyntaxes: ["1.2.840.10008.5.1.4.1.1.7"])
                ) { association in
                    _ = try await association.store(self.instance(1))
                }
                XCTFail("no timeout")
            } catch DICOMNetworkError.timeout {}
        }
    }
}
