import XCTest
@testable import DcmSwift

/// DICOMwebClient against DICOMwebServer over loopback HTTP.
final class DcmSwiftWebIntegrationTests: XCTestCase {
    private var directory: URL!
    private var serverTask: Task<Void, Error>!
    private var client: DICOMwebClient!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-webhttp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let services = DICOMDirectoryArchiveServices(archive: DICOMDirectoryArchive(directory: directory))
        let server = try DICOMwebServer(
            origin: DICOMwebOriginServer(configuration: .init(basePath: "/dicomweb"),
                                         search: services, retrieve: services, store: services),
            network: .init(host: "127.0.0.1", port: 0))
        let (ports, continuation) = AsyncStream<Int>.makeStream()
        serverTask = Task { try await server.run { continuation.yield($0) } }
        var iterator = ports.makeAsyncIterator()
        let bound = await iterator.next()
        let port = try XCTUnwrap(bound)
        client = DICOMwebClient(baseURI: "http://127.0.0.1:\(port)/dicomweb")
    }

    override func tearDown() async throws {
        serverTask.cancel()
        _ = try? await serverTask.value
        try? FileManager.default.removeItem(at: directory)
    }

    func testStoreSearchAndRetrieveOverHTTP() async throws {
        let mr = directory.appendingPathComponent("upload-mr.dcm")
        let ct = directory.appendingPathComponent("upload-ct.dcm")
        try DcmSwiftWebServerTests.mrPart10().write(to: mr)
        try DcmSwiftWebServerTests.ctPart10().write(to: ct)
        let stored = try await client.store(files: [mr, ct])
        XCTAssertEqual(Set(stored.stored.map(\.sopInstanceUID)),
                       [DcmSwiftWebServerTests.mrInstance, DcmSwiftWebServerTests.ctInstance])
        XCTAssertEqual(stored.retrieveURL?.hasSuffix("/studies/\(DcmSwiftWebServerTests.study)"), true)

        var query = DICOMwebSearchQuery()
        query.match("PatientName", "DOE*")
        let studies = try await client.search(.study, query: query)
        XCTAssertEqual(studies.matches.map { $0.string(forTag: "StudyInstanceUID") }, [DcmSwiftWebServerTests.study])
        var paged = DICOMwebSearchQuery()
        paged.limit = 1
        let instances = try await client.search(.instance, study: DcmSwiftWebServerTests.study, query: paged)
        XCTAssertEqual(instances.matches.count, 1)
        XCTAssertEqual(instances.remaining, 1)

        var retrieved: [DICOMwebRetrievedInstance] = []
        for try await instance in client.instances(study: DcmSwiftWebServerTests.study, transferSyntax: "*") {
            retrieved.append(instance)
        }
        XCTAssertEqual(Set(retrieved.map(\.data)),
                       [try DcmSwiftWebServerTests.mrPart10(), try DcmSwiftWebServerTests.ctPart10()])
        var decompressed: [DICOMwebRetrievedInstance] = []
        for try await instance in client.instances(study: DcmSwiftWebServerTests.study, series: DcmSwiftWebServerTests.ctSeries) {
            decompressed.append(instance)
        }
        XCTAssertEqual(decompressed.map(\.transferSyntaxUID), [TransferSyntax.explicitVRLittleEndian])
        XCTAssertEqual(try decompressed[0].dataSet().string(forTag: "SOPInstanceUID"), DcmSwiftWebServerTests.ctInstance)

        let metadata = try await client.metadata(study: DcmSwiftWebServerTests.study, series: DcmSwiftWebServerTests.mrSeries)
        XCTAssertEqual(metadata.first?.string(forTag: "Modality"), "MR")
        let pixelData = try XCTUnwrap(metadata.first?.element(forTagName: "PixelData"))
        XCTAssertEqual(pixelData.bulkDataURI?.hasSuffix("/instances/\(DcmSwiftWebServerTests.mrInstance)/pixeldata"), true)

        let frames = try await client.frames([2], study: DcmSwiftWebServerTests.study, series: DcmSwiftWebServerTests.ctSeries,
                                             instance: DcmSwiftWebServerTests.ctInstance)
        XCTAssertEqual(frames.first?.count, 12)

        let rendered = try await client.rendered(
            .target(study: DcmSwiftWebServerTests.study, series: DcmSwiftWebServerTests.ctSeries,
                    instance: DcmSwiftWebServerTests.ctInstance, kind: .rendered),
            mediaType: .png, parameters: ["viewport": "6,4"], multipart: true)
        XCTAssertEqual(rendered.count, 2, "one image per frame")
        XCTAssertTrue(rendered.allSatisfy { $0.starts(with: [0x89, 0x50, 0x4E, 0x47]) })

        let wadl = try await client.capabilities()
        XCTAssertTrue(wadl.contains("<application"), wadl)

        do {
            _ = try await client.metadata(study: "1.2.3")
            XCTFail("expected 404")
        } catch let error as DICOMwebClientError {
            XCTAssertEqual(error.status, 404)
            XCTAssertTrue(error.message.contains("does not exist"), error.message)
        }
    }
}
