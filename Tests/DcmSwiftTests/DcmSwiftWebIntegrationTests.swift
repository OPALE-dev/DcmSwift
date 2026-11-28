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
        let services = DICOMArchiveServices(archive: DICOMArchive(directory: directory))
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

    func testAClientWithItsOwnTLSConfiguration() async throws {
        func pem(_ name: String) throws -> String {
            try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "pem")).path
        }
        let services = DICOMArchiveServices(archive: DICOMArchive(directory: directory))
        let server = try DICOMwebServer(
            origin: DICOMwebOriginServer(configuration: .init(basePath: "/dicomweb"), search: services),
            network: .init(host: "127.0.0.1", port: 0, tls: try DICOMTLSConfiguration.server(
                pemCertificateChainFile: pem("tls-server"), pemPrivateKeyFile: pem("tls-server-key"))))
        let (ports, continuation) = AsyncStream<Int>.makeStream()
        let task = Task { try await server.run { continuation.yield($0) } }
        defer { task.cancel() }
        var iterator = ports.makeAsyncIterator()
        let bound = await iterator.next()
        let base = "https://127.0.0.1:\(try XCTUnwrap(bound))/dicomweb"
        // Trusting the test authority, by its address.
        let trusted = try DICOMTLSConfiguration.client(pemTrustRootsFile: pem("tls-ca"))
        let studies = try await DICOMwebClient.withTLS(trusted, baseURI: base) { try await $0.search(.study) }
        XCTAssertTrue(studies.matches.isEmpty)
        // Another authority: refused.
        let other = try DICOMTLSConfiguration.client(pemTrustRootsFile: pem("tls-other-ca"))
        do {
            _ = try await DICOMwebClient.withTLS(other, baseURI: base) { try await $0.search(.study) }
            XCTFail("untrusted server accepted")
        } catch {}
    }

    /// The records of a trace, in order.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var records: [DICOMwebHTTPTraceRecord] = []
        var trace: DICOMwebHTTPTrace { { record in self.lock.withLock { self.records.append(record) } } }

        /// The exchanges, in the order they started, each with its events.
        var exchanges: [(id: UUID, events: [DICOMwebHTTPTraceRecord])] {
            lock.withLock {
                var order: [UUID] = []
                var events: [UUID: [DICOMwebHTTPTraceRecord]] = [:]
                for record in records {
                    if events[record.exchange] == nil { order.append(record.exchange) }
                    events[record.exchange, default: []].append(record)
                }
                return order.map { ($0, events[$0]!) }
            }
        }
    }

    private struct Exchange {
        var method = "", target = "", status = 0
        var requestHeaders: [(name: String, value: String)] = [], responseHeaders: [(name: String, value: String)] = []
        var request = Data(), response = Data()
        var ended = false, error: String?
        var shape: [String] = []
    }

    private static func exchange(_ events: [DICOMwebHTTPTraceRecord]) -> Exchange {
        var exchange = Exchange()
        for record in events {
            switch record.event {
            case .request(let method, let target, let headers):
                exchange.method = method; exchange.target = target; exchange.requestHeaders = headers
                exchange.shape.append("request")
            case .response(let status, _, let headers):
                exchange.status = status; exchange.responseHeaders = headers
                exchange.shape.append("response")
            case .requestBody(let data):
                exchange.request += data
                if exchange.shape.last != "requestBody" { exchange.shape.append("requestBody") }
            case .responseBody(let data):
                exchange.response += data
                if exchange.shape.last != "responseBody" { exchange.shape.append("responseBody") }
            case .end(let error):
                exchange.ended = true; exchange.error = error
                exchange.shape.append("end")
            }
        }
        return exchange
    }

    func testHTTPTraceSeesEveryExchangeOnBothSides() async throws {
        let services = DICOMArchiveServices(archive: DICOMArchive(directory: directory))
        let serverTrace = Recorder(), clientTrace = Recorder()
        let server = try DICOMwebServer(
            origin: DICOMwebOriginServer(configuration: .init(basePath: "/dicomweb"),
                                         search: services, retrieve: services, store: services),
            network: .init(host: "127.0.0.1", port: 0, httpTrace: serverTrace.trace))
        let (ports, continuation) = AsyncStream<Int>.makeStream()
        let task = Task { try await server.run { continuation.yield($0) } }
        defer { task.cancel() }
        var iterator = ports.makeAsyncIterator()
        let bound = await iterator.next()
        let port = try XCTUnwrap(bound)
        let traced = DICOMwebClient(baseURI: "http://127.0.0.1:\(port)/dicomweb/", headers: [(name: "Authorization", value: "Bearer t")],
                                    httpTrace: clientTrace.trace)

        let mr = directory.appendingPathComponent("traced-mr.dcm")
        let part10 = try DcmSwiftWebServerTests.mrPart10()
        try part10.write(to: mr)
        _ = try await traced.store(files: [mr])
        _ = try await traced.search(.study)
        var retrieved = 0
        for try await _ in traced.instances(study: DcmSwiftWebServerTests.study, transferSyntax: "*") { retrieved += 1 }
        XCTAssertEqual(retrieved, 1)
        do { _ = try await traced.metadata(study: "1.2.3"); XCTFail("expected 404") } catch {}
        // The server traces the end of an exchange after its last write.
        for _ in 0..<100 where serverTrace.exchanges.count < 4 || !serverTrace.exchanges.allSatisfy({ Self.exchange($0.events).ended }) {
            try await Task.sleep(for: .milliseconds(20))
        }

        let client = clientTrace.exchanges.map { Self.exchange($0.events) }
        let served = serverTrace.exchanges.map { Self.exchange($0.events) }
        XCTAssertEqual(client.map(\.method), ["POST", "GET", "GET", "GET"])
        XCTAssertEqual(served.map(\.method), ["POST", "GET", "GET", "GET"])
        XCTAssertEqual(client.map(\.status), [200, 200, 200, 404])
        XCTAssertEqual(served.map(\.status), [200, 200, 200, 404])
        XCTAssertEqual(client[0].shape, ["request", "requestBody", "response", "responseBody", "end"])
        XCTAssertEqual(served[0].shape, ["request", "requestBody", "response", "responseBody", "end"])
        XCTAssertEqual(client[1].shape, ["request", "response", "responseBody", "end"])
        XCTAssertTrue(client.allSatisfy { $0.ended && $0.error == nil })
        XCTAssertTrue(served.allSatisfy { $0.ended && $0.error == nil })

        // The user agent sees the full URL; the server, the request target.
        XCTAssertEqual(client[0].target, "http://127.0.0.1:\(port)/dicomweb/studies")
        XCTAssertEqual(served[0].target, "/dicomweb/studies")
        XCTAssertEqual(client[2].target, "http://127.0.0.1:\(port)/dicomweb/studies/\(DcmSwiftWebServerTests.study)")
        XCTAssertTrue(client[0].requestHeaders.contains { $0.name == "Authorization" && $0.value == "Bearer t" })
        XCTAssertTrue(served[0].requestHeaders.contains { $0.name.lowercased() == "authorization" && $0.value == "Bearer t" })
        XCTAssertTrue(served[0].requestHeaders.contains { $0.name.lowercased() == "host" })

        // The payloads are the same on both sides: the STOW-RS multipart
        // with the file, the WADO-RS multipart with the instance.
        XCTAssertEqual(client[0].request, served[0].request)
        XCTAssertNotNil(client[0].request.range(of: part10))
        for index in 0..<4 { XCTAssertEqual(client[index].response, served[index].response, "exchange \(index)") }
        let type = try XCTUnwrap(client[2].responseHeaders.first { $0.name.lowercased() == "content-type" }?.value)
        var parser = try DICOMwebMultipart.Parser(boundary: try XCTUnwrap(DICOMwebMediaType(type)?.boundary))
        var body = Data()
        for event in try parser.feed(client[2].response) { if case .bodyChunk(let chunk) = event { body += chunk } }
        XCTAssertEqual(body, part10)

        let records = serverTrace.exchanges.flatMap(\.events)
        XCTAssertTrue(records.allSatisfy { $0.origin == "http://127.0.0.1:\(port)" && $0.remoteAddress != nil && $0.connection != nil })
        XCTAssertTrue(clientTrace.exchanges.flatMap(\.events).allSatisfy { $0.origin == "http://127.0.0.1:\(port)" && $0.connection == nil })
    }
}
