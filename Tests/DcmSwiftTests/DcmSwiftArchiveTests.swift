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

    /// A file indexed where it is is found and served; removed, it is
    /// found no more, its file kept or deleted as asked.
    func testIndexAFileInPlaceThenRemoveIt() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-inplace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func file(_ uid: String) throws -> URL {
            let dataSet = DataSet()
            _ = dataSet.set(value: "1.2.840.10008.5.1.4.1.1.7", forTagName: "SOPClassUID")
            _ = dataSet.set(value: uid, forTagName: "SOPInstanceUID")
            _ = dataSet.set(value: "1.2.3", forTagName: "StudyInstanceUID")
            _ = dataSet.set(value: "Doe^Jane", forTagName: "PatientName")
            _ = dataSet.set(value: "1.2.3.9", forTagName: "SeriesInstanceUID")
            _ = dataSet.set(value: "OT", forTagName: "Modality")
            var bytes = DICOMPart10Header.encodeMetaInformation(sopClassUID: "1.2.840.10008.5.1.4.1.1.7", sopInstanceUID: uid,
                                                            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian, sourceAETitle: nil)
            bytes += try DICOMDataSetCoding.encode(dataSet, transferSyntax: TransferSyntax.explicitVRLittleEndian)
            let url = folder.appendingPathComponent("\(uid).dcm")
            try bytes.write(to: url)
            return url
        }
        // The store's own folder is elsewhere: the files stay where they are.
        let archive = DICOMArchive(store: DICOMFileInstanceStore(directory: folder.appendingPathComponent("store")))
        let first = try file("1.2.3.1"), second = try file("1.2.3.2")
        let record = try await archive.index(file: first)
        XCTAssertEqual(record.location, first.path)
        try await archive.index(file: second)
        let identifier = DataSet()
        _ = identifier.set(value: "IMAGE", forTagName: "QueryRetrieveLevel")
        _ = identifier.set(value: "1.2.3", forTagName: "StudyInstanceUID")
        _ = identifier.set(value: "", forTagName: "SOPInstanceUID")
        let found = try await archive.find(identifier)
        XCTAssertEqual(found.count, 2)
        let firstRecord = try await archive.record("1.2.3.1")
        let item = try await archive.item(try XCTUnwrap(firstRecord))
        XCTAssertEqual(item.sopInstanceUID, "1.2.3.1")

        // Modalities in Study: matched against the series of the study.
        let byModality = DataSet()
        _ = byModality.set(value: "STUDY", forTagName: "QueryRetrieveLevel")
        _ = byModality.set(value: "", forTagName: "StudyInstanceUID")
        _ = byModality.set(value: "MR\\OT", forTagName: "ModalitiesInStudy")
        let otStudies = try await archive.find(byModality)
        XCTAssertEqual(otStudies.count, 1)
        _ = byModality.set(value: "CT", forTagName: "ModalitiesInStudy")
        let ctStudies = try await archive.find(byModality)
        XCTAssertEqual(ctStudies.count, 0)
        // A lone * is universal matching (PS3.4 C.2.2.2.4): every study; other wildcards match each value.
        let allStudies = try await archive.find({ let all = DataSet(); _ = all.set(value: "STUDY", forTagName: "QueryRetrieveLevel")
            _ = all.set(value: "", forTagName: "StudyInstanceUID"); return all }())
        _ = byModality.set(value: "*", forTagName: "ModalitiesInStudy")
        let universal = try await archive.find(byModality)
        XCTAssertEqual(universal.count, allStudies.count)
        XCTAssertGreaterThan(allStudies.count, 0)
        _ = byModality.set(value: "O?", forTagName: "ModalitiesInStudy")
        let wildcard = try await archive.find(byModality)
        XCTAssertEqual(wildcard.count, otStudies.count)

        // A deviant file, its Pixel Data cut short, is indexed with what precedes.
        let truncated = folder.appendingPathComponent("truncated.dcm")
        var bytes = try Data(contentsOf: try file("1.2.3.3"))
        bytes += Data([0xE0, 0x7F, 0x10, 0x00]) + Data("OW".utf8) + Data([0, 0]) + withUnsafeBytes(of: UInt32(1000).littleEndian) { Data($0) }
        bytes += Data(repeating: 7, count: 10)
        try bytes.write(to: truncated)
        let deviant = try await archive.index(file: truncated)
        XCTAssertEqual(deviant.attributes["PatientName"], "Doe^Jane")
        XCTAssertEqual(deviant.attributes["SOPInstanceUID"], "1.2.3.3")
        try await archive.remove("1.2.3.3")

        let removed = try await archive.remove("1.2.3.1", keepingFile: true)
        XCTAssertTrue(removed)
        let gone = try await archive.record("1.2.3.1")
        XCTAssertNil(gone)
        let left = try await archive.find(identifier)
        XCTAssertEqual(left.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path), "kept as asked")
        let removedAgain = try await archive.remove("1.2.3.1")
        XCTAssertFalse(removedAgain)
        try await archive.remove("1.2.3.2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path), "deleted with its entry")
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

    /// The observed bytes are the written file, and the data set part starts where the header says.
    func testReceivedInstanceWriteHandsOverEveryWrittenByte() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-observe-\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: url) }
        let item = try DICOMRetrieveItem(dataSet: try W.dataSet([
            "00080016": ("UI", [DICOMSOPClass.storage[0]]), "00080018": ("UI", ["1.2.826.0.1.3680043.2.1125.9.2"]),
            "0020000D": ("UI", ["1.2.826.0.1.3680043.2.1125.9"]), "00100020": ("LO", ["P9"]),
        ]))
        let instance = DICOMReceivedInstance(sopClassUID: item.sopClassUID, sopInstanceUID: item.sopInstanceUID,
            transferSyntaxUID: item.transferSyntaxUID, payload: item.payload, moveOriginatorAETitle: nil,
            moveOriginatorMessageID: nil, sourceAETitle: "MOD")
        var all = Data(), dataSet = Data()
        try instance.write(to: url) { bytes, isDataSet in
            all += bytes
            if isDataSet { dataSet += bytes }
        }
        let file = try Data(contentsOf: url)
        XCTAssertEqual(all, file)
        let header = try DICOMPart10Header.read(url)
        XCTAssertEqual(dataSet, file.subdata(in: Int(header.dataSetOffset)..<file.count))
        XCTAssertEqual(dataSet.count, header.dataSetLength)
    }

    /// A non-ASCII return value comes back intact and declared (ISO_IR 192).
    func testFindReturnsNonASCIIValuesDeclaredAsUTF8() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dcmswift-charset-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = DICOMArchive(directory: directory)
        let item = try DICOMRetrieveItem(dataSet: try W.dataSet([
            "00080005": ("CS", ["ISO_IR 192"]), "00080016": ("UI", [DICOMSOPClass.storage[0]]),
            "00080018": ("UI", ["1.2.826.0.1.3680043.2.1125.9.1"]), "0020000D": ("UI", ["1.2.826.0.1.3680043.2.1125.9"]),
            "0020000E": ("UI", ["1.2.826.0.1.3680043.2.1125.9.0"]), "00100020": ("LO", ["P9"]), "00100010": ("PN", ["Élise^Müller"]),
        ]))
        try await archive.store(DICOMReceivedInstance(
            sopClassUID: item.sopClassUID, sopInstanceUID: item.sopInstanceUID, transferSyntaxUID: item.transferSyntaxUID,
            payload: item.payload, moveOriginatorAETitle: nil, moveOriginatorMessageID: nil, sourceAETitle: ""))
        let identifier = DataSet()
        _ = identifier.set(value: "STUDY", forTagName: "QueryRetrieveLevel")
        _ = identifier.set(value: "", forTagName: "SpecificCharacterSet")
        _ = identifier.set(value: "1.2.826.0.1.3680043.2.1125.9", forTagName: "StudyInstanceUID")
        _ = identifier.set(value: "", forTagName: "PatientName")
        let matches = try await archive.find(identifier)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.string(forTag: "SpecificCharacterSet"), "ISO_IR 192")
        XCTAssertEqual(matches.first?.string(forTag: "PatientName"), "Élise^Müller")
        // Encoded and decoded as a peer would: the name survives the wire.
        let wire = try DICOMDataSetCoding.decode(try DICOMDataSetCoding.encode(matches[0], transferSyntax: "1.2.840.10008.1.2.1"), transferSyntax: "1.2.840.10008.1.2.1")
        XCTAssertEqual(wire.string(forTag: "PatientName"), "Élise^Müller")
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

/// Retrieval reads several instances at a time and keeps their order.
final class DcmSwiftOrderedConcurrentMapTests: XCTestCase {
    actor Gauge {
        var running = 0, peak = 0
        func enter() { running += 1; peak = max(peak, running) }
        func leave() { running -= 1 }
    }

    func testResultsKeepTheOrderAndTheLimitHolds() async throws {
        let gauge = Gauge()
        let results = try await orderedConcurrentMap(Array(0..<40), limit: 8) { value -> Int in
            await gauge.enter()
            // Earlier elements finish later: completion order differs from element order.
            try await Task.sleep(nanoseconds: UInt64(40 - value) * 200_000)
            await gauge.leave()
            return value * 2
        }
        XCTAssertEqual(results, (0..<40).map { $0 * 2 })
        let peak = await gauge.peak
        XCTAssertGreaterThan(peak, 1)
        XCTAssertLessThanOrEqual(peak, 8)
    }

    func testTheFirstErrorIsThrown() async {
        struct Failure: Error {}
        do {
            _ = try await orderedConcurrentMap(Array(0..<20), limit: 4) { value -> Int in
                if value == 7 { throw Failure() }
                return value
            }
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is Failure)
        }
    }
}
