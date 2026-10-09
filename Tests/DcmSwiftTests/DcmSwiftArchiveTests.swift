import XCTest
@testable import DcmSwift
import DcmSwiftArchiveConformance

/// Pluggable archive storage: the neutral query model, the archive index
/// implementations, and their conformance kit.
final class DcmSwiftArchiveTests: XCTestCase {
    typealias W = DcmSwiftWorkflowTests

    func testQueryConditionsFromAnIdentifier() throws {
        let identifier = try W.dataSet([
            "00080005": ("CS", ["ISO_IR 192"]),
            "00100010": ("PN", ["Müller*"]),
            "00100020": ("LO", []),
            "0020000D": ("UI", ["1.2.3", "1.2.4"]),
            "00400100": ("SQ", [[
                "00080060": ("CS", ["CT"]),
                "00400001": ("AE", ["CT?"]),
                "00400002": ("DA", ["20240705-20240707"]),
                "00400003": ("TM", ["1000-1800"]),
            ]]),
        ])
        let query = try DICOMQuery(identifier: identifier, matcher: .modalityWorklist)
        let byPath = Dictionary(uniqueKeysWithValues: query.conditions.map { ($0.path.joined(separator: "."), $0.constraint) })
        XCTAssertEqual(byPath.count, 5, "universal keys give no condition")
        XCTAssertEqual(byPath["00100010"], .personName("muller*"))
        XCTAssertEqual(byPath["0020000D"], .equals(["1.2.3", "1.2.4"]))
        XCTAssertEqual(byPath["00400100.00080060"], .equals(["CT"]))
        XCTAssertEqual(byPath["00400100.00400001"], .wildcard("CT?"))
        guard case .dateTime(let time, let range)? = byPath["00400100.00400002"] else {
            return XCTFail("the date and time ranges are combined")
        }
        XCTAssertEqual(time, "00400003")
        XCTAssertEqual(range, DICOMQuery.normalizedRange("202407051000", vr: "DT")!.lowerBound
                       ... DICOMQuery.normalizedRange("202407071800", vr: "DT")!.upperBound)
        // Without the worklist matcher, each range is its own condition.
        XCTAssertEqual(try DICOMQuery(identifier: identifier).conditions.count, 6)
    }

    func testMemoryIndexConformance() async throws {
        try await DICOMArchiveConformance.check { DICOMMemoryArchiveIndex() }
    }

    func testFileIndexConformanceAndPersistence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dcmswift-index-\(UUID().uuidString)", isDirectory: true)
        try await DICOMArchiveConformance.check {
            DICOMFileArchiveIndex(directory: root.appendingPathComponent(UUID().uuidString, isDirectory: true))
        }
        let directory = root.appendingPathComponent("persistence", isDirectory: true)
        let index = DICOMFileArchiveIndex(directory: directory)
        try await index.insert(DICOMArchiveDocument(id: "a/b", attributes: ["00100020": ["vr": "LO", "Value": ["P1"]]],
                                                    metadata: ["k": "v"]), into: .worklist)
        let read = try await index.document("a/b", in: .worklist)!
        try await index.replace(read, in: .worklist)
        let reopened = try await DICOMFileArchiveIndex(directory: directory).document("a/b", in: .worklist)
        XCTAssertEqual(reopened?.version, 2)
        XCTAssertEqual(reopened?.metadata, ["k": "v"])
        XCTAssertEqual(try reopened?.dataSet().string(forTag: "PatientID"), "P1")
    }

    // MARK: C-MOVE beyond 128 presentation contexts

    /// Counts received instances and the associations they came on.
    actor Receiver: DICOMStorageService {
        var instances = 0
        var associations: Set<String> = []
        func store(_ instance: DICOMReceivedInstance, context: DICOMServiceContext) async throws -> DICOMStatus {
            instances += 1
            associations.insert(context.remoteAddress)
            return .success
        }
        func counts() -> (Int, Int) { (instances, associations.count) }
    }

    func testMoveSplitsMoreThan128PresentationContexts() async throws {
        let sopClasses = Array(DICOMSOPClass.allStorage.prefix(130))
        let items = try sopClasses.enumerated().map { index, sopClass -> DICOMRetrieveItem in
            let dataSet = try W.dataSet([
                "00080016": ("UI", [sopClass]), "00080018": ("UI", ["1.2.826.0.1.3680043.2.1125.8.\(index)"]),
                "0020000D": ("UI", ["1.2.826.0.1.3680043.2.1125.8"]), "00100020": ("LO", ["P1"]),
            ])
            return try DICOMRetrieveItem(dataSet: dataSet)
        }
        XCTAssertEqual(DICOMPresentationContextProposal.batches(for: items).map(\.count), [128, 2])

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dcmswift-move-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let archive = DICOMArchive(directory: directory)
        for item in items {
            try await archive.store(DICOMReceivedInstance(
                sopClassUID: item.sopClassUID, sopInstanceUID: item.sopInstanceUID, transferSyntaxUID: item.transferSyntaxUID,
                payload: item.payload, moveOriginatorAETitle: nil, moveOriginatorMessageID: nil, sourceAETitle: ""))
        }
        func start(_ server: DICOMServer) async throws -> (Task<Void, Error>, Int) {
            let ready = AsyncStream<Int>.makeStream()
            let task = Task { try await server.run { ready.continuation.yield($0) } }
            var iterator = ready.stream.makeAsyncIterator()
            guard let port = await iterator.next() else { throw DICOMNetworkError.connectionClosed }
            return (task, port)
        }
        let receiver = Receiver()
        let (destinationTask, destinationPort) = try await start(DICOMServer(
            configuration: DICOMServerConfiguration(aeTitle: "DEST", host: "127.0.0.1", port: 0), storage: receiver))
        defer { destinationTask.cancel() }
        let services = DICOMArchiveServices(
            archive: archive, destinations: ["DEST": DICOMRemoteNode(aeTitle: "DEST", host: "127.0.0.1", port: destinationPort)])
        let (archiveTask, port) = try await start(DICOMServer(
            configuration: DICOMServerConfiguration(aeTitle: "PACS", host: "127.0.0.1", port: 0), query: services,
            retrieve: services))
        defer { archiveTask.cancel() }

        let identifier = DataSet()
        _ = identifier.set(value: "STUDY", forTagName: "QueryRetrieveLevel")
        _ = identifier.set(value: "1.2.826.0.1.3680043.2.1125.8", forTagName: "StudyInstanceUID")
        let client = try DICOMClient(configuration: DICOMClientConfiguration(aeTitle: "SCU"))
        let result = try await client.withAssociation(
            to: DICOMRemoteNode(aeTitle: "PACS", host: "127.0.0.1", port: port),
            presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.studyRootMove])
        ) { try await $0.move(identifier, destination: "DEST") }
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.progress.completed, 130)
        let (instances, associations) = await receiver.counts()
        XCTAssertEqual(instances, 130)
        XCTAssertEqual(associations, 2)
    }
}
