import XCTest
import NIOCore
import NIOConcurrencyHelpers
@testable import DcmSwift

/// DIMSE-N services (PS3.7 10) and Storage Commitment (PS3.4 Annex J) over
/// the loopback interface. The reference command sets were encoded by
/// pynetdicom 3.0.4.
final class DcmSwiftNetworkNormalizedTests: XCTestCase {
    private let mpps = "1.2.840.10008.3.1.2.3.3"
    private let secondaryCapture = "1.2.840.10008.5.1.4.1.1.7"

    // MARK: Fixtures

    /// Keeps normalized instances in memory: N-CREATE, N-SET, N-GET,
    /// N-DELETE, an N-ACTION echoing its information, and received
    /// N-EVENT-REPORTs.
    final class MemoryInstances: DICOMNormalizedService, @unchecked Sendable {
        let instances = NIOLockedValueBox<[String: [String: String]]>([:])
        let events = NIOLockedValueBox<[(UInt16, String?)]>([])

        func perform(_ request: DICOMNormalizedRequest, context: DICOMServiceContext) async throws -> DICOMNormalizedResponse {
            let attributes = try request.dataSet().map { dataSet in
                Dictionary(dataSet.allElements.map { ($0.name, dataSet.string(forTag: $0.name) ?? "") },
                           uniquingKeysWith: { _, last in last })
            } ?? [:]
            switch request.operation {
            case .create:
                let uid = request.sopInstanceUID ?? "2.25.\(UInt64.random(in: 1...UInt64.max))"
                let created = instances.withLockedValue { instances -> Bool in
                    guard instances[uid] == nil else { return false }
                    instances[uid] = attributes
                    return true
                }
                return DICOMNormalizedResponse(status: created ? .success : .duplicateSOPInstance, sopInstanceUID: uid)
            case .set:
                let found = instances.withLockedValue { instances -> Bool in
                    guard let uid = request.sopInstanceUID, instances[uid] != nil else { return false }
                    instances[uid]!.merge(attributes) { _, new in new }
                    return true
                }
                return DICOMNormalizedResponse(status: found ? .success : .noSuchObjectInstance)
            case .get(let tags):
                guard let uid = request.sopInstanceUID,
                      let stored = instances.withLockedValue({ $0[uid] }) else {
                    return DICOMNormalizedResponse(status: .noSuchObjectInstance)
                }
                let wanted = Set(tags.map { tag -> String in
                    DicomSpec.shared.nameForTag(withCode: String(format: "%08x", tag)) ?? ""
                })
                let reply = DataSet()
                for (name, value) in stored where wanted.isEmpty || wanted.contains(name) {
                    _ = reply.set(value: value, forTagName: name)
                }
                return DICOMNormalizedResponse(status: .success, dataSet: reply)
            case .delete:
                let removed = instances.withLockedValue { instances -> [String: String]? in
                    guard let uid = request.sopInstanceUID else { return nil }
                    return instances.removeValue(forKey: uid)
                }
                return DICOMNormalizedResponse(status: removed == nil ? .noSuchObjectInstance : .success)
            case .action(let type):
                guard type == 7 else { return DICOMNormalizedResponse(status: .noSuchActionType) }
                return DICOMNormalizedResponse(status: .success, dataSet: try request.dataSet())
            case .eventReport(let type):
                events.withLockedValue { $0.append((type, attributes["PatientComments"])) }
                return DICOMNormalizedResponse(status: .success)
            }
        }
    }

    /// Stores in memory; commits the instances it holds.
    final class CommittingArchive: DICOMStorageService, DICOMStorageCommitmentService, @unchecked Sendable {
        let stored = NIOLockedValueBox<Set<DICOMSOPReference>>([])
        let destinations: NIOLockedValueBox<[String: DICOMRemoteNode]>
        /// Destination lookups: results that could not go on the same
        /// association.
        let lookups = NIOLockedValueBox(0)
        let delay: UInt64

        init(destinations: [String: DICOMRemoteNode] = [:], delay: UInt64 = 0) {
            self.destinations = NIOLockedValueBox(destinations)
            self.delay = delay
        }

        func store(_ instance: DICOMReceivedInstance, context: DICOMServiceContext) async throws -> DICOMStatus {
            stored.withLockedValue {
                _ = $0.insert(DICOMSOPReference(sopClassUID: instance.sopClassUID, sopInstanceUID: instance.sopInstanceUID))
            }
            return .success
        }

        func commit(_ request: DICOMStorageCommitmentRequest, context: DICOMServiceContext) async throws
            -> DICOMStorageCommitmentResult {
            if delay > 0 { try await Task.sleep(nanoseconds: delay) }
            let stored = self.stored.withLockedValue { $0 }
            var result = DICOMStorageCommitmentResult(transactionUID: request.transactionUID, committed: [],
                                                      retrieveAETitle: context.calledAETitle)
            for reference in request.references {
                if stored.contains(reference) {
                    result.committed.append(reference)
                } else {
                    result.failed.append(.init(
                        reference: reference, reason: DICOMStorageCommitmentResult.FailureReason.noSuchSOPInstance))
                }
            }
            return result
        }

        func destination(for aeTitle: String) async -> DICOMRemoteNode? {
            lookups.withLockedValue { $0 += 1 }
            return destinations.withLockedValue { $0[aeTitle] }
        }
    }

    final class ResultCollector: DICOMStorageCommitmentReceiver, @unchecked Sendable {
        let results = NIOLockedValueBox<[DICOMStorageCommitmentResult]>([])
        let arrived = AsyncStream<Void>.makeStream()

        func received(_ result: DICOMStorageCommitmentResult, context: DICOMServiceContext) async throws {
            results.withLockedValue { $0.append(result) }
            arrived.continuation.yield()
        }
    }

    private func instance(_ index: Int) -> DataSet {
        let dataSet = DataSet()
        _ = dataSet.set(value: secondaryCapture, forTagName: "SOPClassUID")
        _ = dataSet.set(value: "1.2.826.0.1.98.\(index)", forTagName: "SOPInstanceUID")
        _ = dataSet.set(value: "Doe^John", forTagName: "PatientName")
        return dataSet
    }

    private func configuration(_ aeTitle: String) -> DICOMServerConfiguration {
        DICOMServerConfiguration(
            aeTitle: aeTitle, host: "127.0.0.1", port: 0,
            timeouts: DICOMNetworkTimeouts(connect: .seconds(5), artim: .seconds(5), idle: .seconds(20)))
    }

    private func client(_ aeTitle: String = "SCU") throws -> DICOMClient {
        try DICOMClient(configuration: DICOMClientConfiguration(
            aeTitle: aeTitle, timeouts: DICOMNetworkTimeouts(connect: .seconds(5), artim: .seconds(5), idle: .seconds(20))))
    }

    private func withServer<T>(_ server: DICOMServer, _ body: (Int) async throws -> T) async throws -> T {
        let ready = AsyncStream<Int>.makeStream()
        let task = Task { try await server.run { ready.continuation.yield($0) } }
        var iterator = ready.stream.makeAsyncIterator()
        guard let port = await iterator.next() else { throw DICOMNetworkError.connectionClosed }
        defer { task.cancel() }
        let result = try await body(port)
        task.cancel()
        _ = try? await task.value
        return result
    }

    private func data(_ hex: String) -> Data {
        Data(stride(from: 0, to: hex.count, by: 2).map {
            UInt8(hex[hex.index(hex.startIndex, offsetBy: $0)..<hex.index(hex.startIndex, offsetBy: $0 + 2)], radix: 16)!
        })
    }

    // MARK: Tests

    func testNormalizedCommandSetsMatchPynetdicom() throws {
        var report = DICOMCommand(field: .nEventReportRequest, hasDataSet: true)
        report.messageID = 21
        report.affectedSOPClassUID = DICOMSOPClass.storageCommitmentPushModel
        report.affectedSOPInstanceUID = DICOMSOPClass.storageCommitmentPushModelInstance
        report.eventTypeID = 2
        var reportResponse = DICOMCommand(field: .nEventReportResponse)
        reportResponse.messageIDBeingRespondedTo = 21
        reportResponse.affectedSOPClassUID = DICOMSOPClass.storageCommitmentPushModel
        reportResponse.affectedSOPInstanceUID = DICOMSOPClass.storageCommitmentPushModelInstance
        reportResponse.eventTypeID = 2
        reportResponse.status = 0
        var get = DICOMCommand(field: .nGetRequest)
        get.messageID = 22
        get.requestedSOPClassUID = "1.2.840.10008.5.1.1.16"
        get.requestedSOPInstanceUID = "1.2.840.10008.5.1.1.17"
        get.attributeIdentifierList = [0x2110_0010, 0x2110_0020]
        var set = DICOMCommand(field: .nSetRequest, hasDataSet: true)
        set.messageID = 23
        set.requestedSOPClassUID = mpps
        set.requestedSOPInstanceUID = "1.2.3.4"
        var create = DICOMCommand(field: .nCreateRequest, hasDataSet: true)
        create.messageID = 24
        create.affectedSOPClassUID = mpps
        create.affectedSOPInstanceUID = "1.2.3.4"
        var delete = DICOMCommand(field: .nDeleteRequest)
        delete.messageID = 25
        delete.requestedSOPClassUID = "1.2.840.10008.5.1.1.1"
        delete.requestedSOPInstanceUID = "1.2.3.5"
        var actionResponse = DICOMCommand(field: .nActionResponse)
        actionResponse.messageIDBeingRespondedTo = 11
        actionResponse.affectedSOPClassUID = DICOMSOPClass.storageCommitmentPushModel
        actionResponse.affectedSOPInstanceUID = DICOMSOPClass.storageCommitmentPushModelInstance
        actionResponse.actionTypeID = 1
        actionResponse.status = 0
        var getResponse = DICOMCommand(field: .nGetResponse, hasDataSet: true)
        getResponse.messageIDBeingRespondedTo = 22
        getResponse.affectedSOPClassUID = "1.2.840.10008.5.1.1.16"
        getResponse.affectedSOPInstanceUID = "1.2.840.10008.5.1.1.17"
        getResponse.status = 0x0107

        let references: [(DICOMCommand, String)] = [
            (report, "0000000004000000620000000000020014000000312e322e3834302e31303030382e312e32302e310000000102000000000100001001020000001500000000080200000001000000001016000000312e322e3834302e31303030382e312e32302e312e3100000210020000000200"),
            (reportResponse, "00000000040000006c0000000000020014000000312e322e3834302e31303030382e312e32302e31000000010200000000810000200102000000150000000008020000000101000000090200000000000000001016000000312e322e3834302e31303030382e312e32302e312e3100000210020000000200"),
            (get, "00000000040000006a0000000000030016000000312e322e3834302e31303030382e352e312e312e31360000000102000000100100001001020000001600000000080200000001010000011016000000312e322e3834302e31303030382e352e312e312e313700000510080000001021100010212000"),
            (set, "00000000040000004e0000000000030018000000312e322e3834302e31303030382e332e312e322e332e33000000000102000000200100001001020000001700000000080200000001000000011008000000312e322e332e3400"),
            (create, "00000000040000004e0000000000020018000000312e322e3834302e31303030382e332e312e322e332e33000000000102000000400100001001020000001800000000080200000001000000001008000000312e322e332e3400"),
            (delete, "00000000040000004c0000000000030016000000312e322e3834302e31303030382e352e312e312e31000000000102000000500100001001020000001900000000080200000001010000011008000000312e322e332e3500"),
            (actionResponse, "00000000040000006c0000000000020014000000312e322e3834302e31303030382e312e32302e310000000102000000308100002001020000000b0000000008020000000101000000090200000000000000001016000000312e322e3834302e31303030382e312e32302e312e3100000810020000000100"),
            (getResponse, "0000000004000000640000000000020016000000312e322e3834302e31303030382e352e312e312e3136000000010200000010810000200102000000160000000008020000000100000000090200000007010000001016000000312e322e3834302e31303030382e352e312e312e3137"),
        ]
        for (command, hex) in references {
            XCTAssertEqual(try command.encoded(), data(hex), "\(command.field)")
            XCTAssertEqual(try DICOMCommand(encoded: data(hex)), command, "\(command.field)")
        }
    }

    func testNormalizedOperationsReachTheService() async throws {
        let service = MemoryInstances()
        let server = try DICOMServer(configuration: configuration("SCP"), normalized: [mpps: service])
        try await withServer(server) { port in
            try await client().withAssociation(
                to: DICOMRemoteNode(aeTitle: "SCP", host: "127.0.0.1", port: port),
                presentationContexts: .proposals(abstractSyntaxes: [mpps]),
                // Both roles, to send N-EVENT-REPORT as well.
                roleSelections: [DICOMRoleSelection(sopClassUID: mpps, scuRole: true, scpRole: true)]
            ) { association in
                let attributes = DataSet()
                _ = attributes.set(value: "IN PROGRESS", forTagName: "PerformedProcedureStepStatus")
                _ = attributes.set(value: "CT", forTagName: "Modality")
                let created = try await association.nCreate(sopClassUID: mpps, sopInstanceUID: "1.2.3.4", attributes: attributes)
                XCTAssertEqual(created.status, .success)
                XCTAssertEqual(created.sopInstanceUID, "1.2.3.4")
                let duplicate = try await association.nCreate(sopClassUID: mpps, sopInstanceUID: "1.2.3.4", attributes: attributes)
                XCTAssertEqual(duplicate.status, .duplicateSOPInstance)
                // The SCP chooses the UID.
                let assigned = try await association.nCreate(sopClassUID: mpps, attributes: attributes)
                XCTAssertEqual(assigned.status, .success)
                XCTAssertTrue(assigned.sopInstanceUID?.hasPrefix("2.25.") ?? false)

                let modification = DataSet()
                _ = modification.set(value: "COMPLETED", forTagName: "PerformedProcedureStepStatus")
                let set = try await association.nSet(sopClassUID: mpps, sopInstanceUID: "1.2.3.4", modifications: modification)
                XCTAssertEqual(set.status, .success)
                XCTAssertEqual(set.sopInstanceUID, "1.2.3.4")

                let got = try await association.nGet(
                    sopClassUID: mpps, sopInstanceUID: "1.2.3.4", attributes: [0x0040_0252])
                XCTAssertEqual(got.status, .success)
                XCTAssertEqual(got.dataSet?.string(forTag: "PerformedProcedureStepStatus"), "COMPLETED")
                XCTAssertNil(got.dataSet?.string(forTag: "Modality"))

                let information = DataSet()
                _ = information.set(value: "hello", forTagName: "PatientComments")
                let action = try await association.nAction(
                    sopClassUID: mpps, sopInstanceUID: "1.2.3.4", actionTypeID: 7, information: information)
                XCTAssertEqual(action.status, .success)
                XCTAssertEqual(action.typeID, 7)
                XCTAssertEqual(action.dataSet?.string(forTag: "PatientComments"), "hello")
                let unknownAction = try await association.nAction(sopClassUID: mpps, sopInstanceUID: "1.2.3.4", actionTypeID: 9)
                XCTAssertEqual(unknownAction.status, .noSuchActionType)
                XCTAssertNil(unknownAction.typeID)

                let report = try await association.nEventReport(
                    sopClassUID: mpps, sopInstanceUID: "1.2.3.4", eventTypeID: 3, information: information)
                XCTAssertEqual(report.status, .success)
                XCTAssertEqual(report.typeID, 3)

                let deleted = try await association.nDelete(sopClassUID: mpps, sopInstanceUID: "1.2.3.4")
                XCTAssertEqual(deleted.status, .success)
                let gone = try await association.nGet(sopClassUID: mpps, sopInstanceUID: "1.2.3.4")
                XCTAssertEqual(gone.status, .noSuchObjectInstance)

                // A SOP class without a service.
                do {
                    _ = try await association.nGet(sopClassUID: "1.2.840.10008.5.1.1.16", sopInstanceUID: "1.2.3")
                    XCTFail("no context expected")
                } catch DICOMNetworkError.noPresentationContext {}
            }
        }
        XCTAssertEqual(service.events.withLockedValue { $0.map(\.0) }, [3])
        XCTAssertEqual(service.events.withLockedValue { $0.first?.1 }, "hello")
    }

    func testEventReportsNeedTheSCPRole() async throws {
        let server = try DICOMServer(configuration: configuration("SCP"), normalized: [mpps: MemoryInstances()])
        try await withServer(server) { port in
            try await client().withAssociation(
                to: DICOMRemoteNode(aeTitle: "SCP", host: "127.0.0.1", port: port),
                presentationContexts: .proposals(abstractSyntaxes: [mpps])
            ) { association in
                do {
                    _ = try await association.nEventReport(sopClassUID: mpps, sopInstanceUID: "1.2.3", eventTypeID: 1)
                    XCTFail("a requestor without the SCP role sent a notification")
                } catch DICOMNetworkError.noPresentationContext {}
            }
        }
    }

    func testStorageCommitmentResultOnTheSameAssociation() async throws {
        let archive = CommittingArchive()
        let server = try DICOMServer(configuration: configuration("ARCHIVE"), storage: archive, storageCommitment: archive)
        let items = try (0..<2).map { try DICOMRetrieveItem(dataSet: instance($0)) }
        let missing = DICOMSOPReference(sopClassUID: secondaryCapture, sopInstanceUID: "1.2.826.0.1.98.99")
        try await withServer(server) { port in
            let result = try await client().withAssociation(
                to: DICOMRemoteNode(aeTitle: "ARCHIVE", host: "127.0.0.1", port: port),
                presentationContexts: DICOMPresentationContextProposal.proposals(
                    abstractSyntaxes: [secondaryCapture, DICOMSOPClass.storageCommitmentPushModel])
            ) { association -> DICOMStorageCommitmentResult? in
                for item in items { try await association.store(item) }
                return try await association.commit(items.map(\.reference) + [missing], timeout: .seconds(5))
            }
            let unwrapped = try XCTUnwrap(result)
            XCTAssertEqual(unwrapped.eventTypeID, 2)
            XCTAssertEqual(Set(unwrapped.committed), Set(items.map(\.reference)))
            XCTAssertEqual(unwrapped.failed, [.init(
                reference: missing, reason: DICOMStorageCommitmentResult.FailureReason.noSuchSOPInstance)])
            XCTAssertEqual(unwrapped.retrieveAETitle, "ARCHIVE")

            // All committed: Event Type 1.
            let complete = try await client().withAssociation(
                to: DICOMRemoteNode(aeTitle: "ARCHIVE", host: "127.0.0.1", port: port),
                presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.storageCommitmentPushModel])
            ) { try await $0.commit(items.map(\.reference), timeout: .seconds(5)) }
            XCTAssertEqual(complete?.eventTypeID, 1)
            XCTAssertEqual(complete?.failed, [])
        }
        // Both results were answered on their association, although the
        // SCU released as soon as it had them.
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(archive.lookups.withLockedValue { $0 }, 0)
    }

    func testStorageCommitmentResultOnANewAssociation() async throws {
        // The SCU listens for results under its own AE title.
        let collector = ResultCollector()
        let listener = try DICOMServer(configuration: configuration("SCU"), storageCommitmentReceiver: collector)
        try await withServer(listener) { listenerPort in
            let archive = CommittingArchive(
                destinations: ["SCU": DICOMRemoteNode(aeTitle: "SCU", host: "127.0.0.1", port: listenerPort)],
                delay: 300_000_000)
            let server = try DICOMServer(configuration: configuration("ARCHIVE"), storage: archive, storageCommitment: archive)
            let item = try DICOMRetrieveItem(dataSet: instance(7))
            try await withServer(server) { port in
                // The SCU releases as soon as the request is accepted.
                let transaction = try await client().withAssociation(
                    to: DICOMRemoteNode(aeTitle: "ARCHIVE", host: "127.0.0.1", port: port),
                    presentationContexts: DICOMPresentationContextProposal.proposals(
                        abstractSyntaxes: [secondaryCapture, DICOMSOPClass.storageCommitmentPushModel])
                ) { association -> String in
                    try await association.store(item)
                    return try await association.requestStorageCommitment([item.reference])
                }
                var arrivals = collector.arrived.stream.makeAsyncIterator()
                let waiter = Task { await arrivals.next() }
                let timeout = Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    waiter.cancel()
                }
                _ = await waiter.value
                timeout.cancel()
                let results = collector.results.withLockedValue { $0 }
                XCTAssertEqual(results.map(\.transactionUID), [transaction])
                XCTAssertEqual(results.first?.committed, [item.reference])
            }
        }
    }

    func testUndeliveredStorageCommitmentResultsAreRetried() async throws {
        let collector = ResultCollector()
        let listener = try DICOMServer(configuration: configuration("SCU"), storageCommitmentReceiver: collector)
        try await withServer(listener) { listenerPort in
            // The SCU's address is unknown at first: the result waits.
            let archive = CommittingArchive(destinations: [:], delay: 100_000_000)
            let outbox = DICOMStorageCommitmentOutbox(retryInterval: 0.3)
            let server = try DICOMServer(configuration: configuration("ARCHIVE"), storage: archive,
                                         storageCommitment: archive, storageCommitmentOutbox: outbox)
            let item = try DICOMRetrieveItem(dataSet: instance(8))
            try await withServer(server) { port in
                let transaction = try await client().withAssociation(
                    to: DICOMRemoteNode(aeTitle: "ARCHIVE", host: "127.0.0.1", port: port),
                    presentationContexts: DICOMPresentationContextProposal.proposals(
                        abstractSyntaxes: [secondaryCapture, DICOMSOPClass.storageCommitmentPushModel])
                ) { association -> String in
                    try await association.store(item)
                    return try await association.requestStorageCommitment([item.reference])
                }
                var pending: [DICOMStorageCommitmentResult] = []
                for _ in 0..<40 where pending.isEmpty {
                    try await Task.sleep(nanoseconds: 50_000_000)
                    pending = try await outbox.pending()
                }
                XCTAssertEqual(pending.map(\.transactionUID), [transaction])
                archive.destinations.withLockedValue {
                    $0["SCU"] = DICOMRemoteNode(aeTitle: "SCU", host: "127.0.0.1", port: listenerPort)
                }
                var arrivals = collector.arrived.stream.makeAsyncIterator()
                let waiter = Task { await arrivals.next() }
                let timeout = Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    waiter.cancel()
                }
                _ = await waiter.value
                timeout.cancel()
                XCTAssertEqual(collector.results.withLockedValue { $0 }.map(\.transactionUID), [transaction])
                for _ in 0..<20 where !pending.isEmpty {
                    try await Task.sleep(nanoseconds: 50_000_000)
                    pending = try await outbox.pending()
                }
                XCTAssertTrue(pending.isEmpty)
            }
        }
    }

    func testStorageCommitmentRequestsAreValidated() async throws {
        let archive = CommittingArchive()
        let server = try DICOMServer(configuration: configuration("ARCHIVE"), storageCommitment: archive)
        try await withServer(server) { port in
            try await client().withAssociation(
                to: DICOMRemoteNode(aeTitle: "ARCHIVE", host: "127.0.0.1", port: port),
                presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.storageCommitmentPushModel])
            ) { association in
                // Not the well-known instance.
                let wrongInstance = try await association.nAction(
                    sopClassUID: DICOMSOPClass.storageCommitmentPushModel, sopInstanceUID: "1.2.3", actionTypeID: 1,
                    information: DICOMStorageCommitmentRequest(
                        transactionUID: "1.2.3.9", references: [.init(sopClassUID: "1.2", sopInstanceUID: "1.3")]).dataSet())
                XCTAssertEqual(wrongInstance.status, .noSuchObjectInstance)
                // No Transaction UID.
                let empty = try await association.nAction(
                    sopClassUID: DICOMSOPClass.storageCommitmentPushModel,
                    sopInstanceUID: DICOMSOPClass.storageCommitmentPushModelInstance, actionTypeID: 1,
                    information: DataSet())
                XCTAssertEqual(empty.status, .invalidArgumentValue)
                do {
                    try await association.requestStorageCommitment([])
                    XCTFail("empty request accepted")
                } catch let error as DICOMServiceError {
                    XCTAssertEqual(error.status, .invalidArgumentValue)
                }
                // No result arrives for a transaction never requested.
                let none = await association.storageCommitmentResult(transactionUID: "1.2.3.4", timeout: .milliseconds(100))
                XCTAssertNil(none)
            }
        }
    }

    func testStorageCommitmentDataSetsRoundTrip() throws {
        let request = DICOMStorageCommitmentRequest(
            transactionUID: "1.2.3.4.5",
            references: [.init(sopClassUID: secondaryCapture, sopInstanceUID: "1.2.3.6"),
                         .init(sopClassUID: secondaryCapture, sopInstanceUID: "1.2.3.7")],
            storageMediaFileSetID: "DISC1")
        for syntax in [TransferSyntax.implicitVRLittleEndian, TransferSyntax.explicitVRLittleEndian,
                       TransferSyntax.explicitVRBigEndian, TransferSyntax.deflatedExplicitVRLittleEndian] {
            let encoded = try DICOMDataSetCoding.encode(request.dataSet(), transferSyntax: syntax)
            let decoded = try DICOMStorageCommitmentRequest(dataSet: DICOMDataSetCoding.decode(encoded, transferSyntax: syntax))
            XCTAssertEqual(decoded, request, syntax)

            let result = DICOMStorageCommitmentResult(
                transactionUID: "1.2.3.4.5", committed: [request.references[0]],
                failed: [.init(reference: request.references[1], reason: 0x0119)], retrieveAETitle: "ARCHIVE")
            let resultBytes = try DICOMDataSetCoding.encode(result.dataSet(), transferSyntax: syntax)
            XCTAssertEqual(try DICOMStorageCommitmentResult(
                dataSet: DICOMDataSetCoding.decode(resultBytes, transferSyntax: syntax)), result, syntax)
        }
    }
}
