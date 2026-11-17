import XCTest
@testable import DcmSwift

final class DcmSwiftUPSRESTTests: XCTestCase {
    private let uid = "2.25.202610212000"
    private func value(_ vr: String, _ text: String) -> [String: Any] { ["vr": vr, "Value": [text]] }
    private func scheduled() -> [String: Any] {
        var object: [String: Any] = ["00741200": value("CS", "MEDIUM"), "00741204": value("LO", "Read"),
            "00404005": value("DT", "20261021190000+0200"), "00404041": value("CS", "READY"),
            "00741000": value("CS", "SCHEDULED")]
        for (tag, vr) in [("00081195", "UI"), ("00741202", "LO"), ("00400400", "LT"), ("00100010", "PN"),
                          ("00100021", "LO"), ("00100030", "DA"), ("00100040", "CS"), ("00380010", "LO"), ("00081080", "LO")] {
            object[tag] = ["vr": vr]
        }
        for tag in ["00741210", "00404025", "00404026", "00404027", "00404018", "00404021", "00100024", "00101002",
                    "00380014", "00081084", "0040A370", "00741002", "00741216"] { object[tag] = ["vr": "SQ"] }
        return object
    }
    private func origin(_ steps: DICOMUnifiedProcedureStepService, maximum: Int = 1 << 20) -> DICOMwebOriginServer {
        .init(configuration: .init(basePath: "/dicomweb", maximumResults: 1, maximumRequestLength: maximum),
              worklist: DICOMUPSRESTService(steps: steps))
    }
    private func request(_ origin: DICOMwebOriginServer, _ method: String, _ target: String,
                         object: [String: Any]? = nil, headers: DICOMwebMultipart.Headers = .init()) async throws -> DICOMwebHTTPResponse {
        var headers = headers
        let data: Data
        if let object {
            data = try JSONSerialization.data(withJSONObject: [object])
            headers["Content-Type"] = "application/dicom+json"
        } else { data = Data() }
        return await origin.respond(to: .init(method: method, target: "/dicomweb" + target, headers: headers, body: data),
                                    origin: "http://example.test")
    }
    private func check(_ response: DICOMwebHTTPResponse, _ status: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(response.status, status, file: file, line: line)
    }

    func testCreateWithoutType2AttributesUsesSharedCompletion() async throws {
        let steps = DICOMUnifiedProcedureStepService()
        let server = origin(steps)
        let minimal = scheduled().filter {
            ["00741200", "00741204", "00404005", "00404041", "00741000"].contains($0.key)
        }
        check(try await request(server, "POST", "/workitems?workitem=" + uid, object: minimal), 201)
        let document = try await steps.index.document(uid, in: .unifiedProcedureSteps)
        let stored = try XCTUnwrap(document).attributes
        for (tag, expected) in scheduled() where minimal[tag] == nil {
            let attribute = try XCTUnwrap(stored[tag] as? [String: Any], tag)
            XCTAssertEqual(attribute["vr"] as? String, (expected as? [String: Any])?["vr"] as? String, tag)
            if tag != "00741202" { XCTAssertNil(attribute["Value"], tag) }
        }
    }

    func testCreateRetrieveUpdateClaimAndCancelShareDIMSEState() async throws {
        let steps = DICOMUnifiedProcedureStepService()
        let server = origin(steps)
        let created = try await request(server, "POST", "/workitems?workitem=" + uid, object: scheduled())
        check(created, 201)
        XCTAssertEqual(created.headers["Location"], "http://example.test/dicomweb/workitems/" + uid)
        check(try await request(server, "POST", "/workitems?workitem=" + uid, object: scheduled()), 409)
        let dimse = try await steps.get(uid)
        XCTAssertEqual(dimse.dataSet?.string(forTag: "ProcedureStepState"), "SCHEDULED")
        check(try await request(server, "PUT", "/workitems/" + uid + "/state",
                                object: ["00741000": value("CS", "IN PROGRESS"), "00081195": value("UI", "2.25.7")]), 200)
        check(try await request(server, "POST", "/workitems/" + uid + "?transactionuid=2.25.8",
                                object: ["00404041": value("CS", "UNAVAILABLE")]), 400)
        check(try await request(server, "POST", "/workitems/" + uid + "?2.25.8",
                                object: ["00404041": value("CS", "UNAVAILABLE")]), 400)
        check(try await request(server, "POST", "/workitems/" + uid + "?2.25.7",
                                object: ["00404041": value("CS", "INCOMPLETE")]), 200)
        check(try await request(server, "POST", "/workitems/" + uid + "?transactionuid=2.25.7",
                                object: ["00404041": value("CS", "UNAVAILABLE")]), 200)
        let read = try await request(server, "GET", "/workitems/" + uid)
        check(read, 200)
        let data = try await read.collectBody()
        let objects = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertNil(objects[0]["00081195"])
        XCTAssertEqual(DICOMUnifiedProcedureStepService.value(objects[0], "00404041"), "UNAVAILABLE")
        check(try await request(server, "POST", "/workitems/" + uid + "/cancelrequest?requester=SCU"), 202)
        let current = try await steps.get(uid)
        XCTAssertEqual(current.dataSet?.string(forTag: "ProcedureStepState"), "IN PROGRESS")
    }

    func testXMLRepresentationAndInvalidMedia() async throws {
        let steps = DICOMUnifiedProcedureStepService()
        let server = origin(steps)
        let boundary = "ups-xml"
        let xml = try DICOMXML.encode(DICOMJSON.dataSet(scheduled()))
        let payload = DICOMwebMultipart.Writer.encode([(.init([("Content-Type", "application/dicom+xml")]), xml)], boundary: boundary)
        let create = await server.respond(to: .init(method: "POST", target: "/dicomweb/workitems?workitem=" + uid,
            headers: .init([("Content-Type", "multipart/related; type=\"application/dicom+xml\"; boundary=ups-xml")]), body: payload),
            origin: "http://example.test")
        check(create, 201)
        let read = try await request(server, "GET", "/workitems/" + uid,
                                    headers: .init([("Accept", "multipart/related; type=\"application/dicom+xml\"")]))
        check(read, 200)
        XCTAssertTrue(read.headers.contentType?.isMultipartRelated == true)
        check(try await request(server, "GET", "/workitems/" + uid, headers: .init([("Accept", "image/png")])), 406)
        check(try await request(server, "POST", "/workitems", headers: .init([("Content-Type", "text/plain")])), 415)
        check(try await request(origin(steps, maximum: 8), "POST", "/workitems", object: scheduled()), 413)
        let bad = await server.respond(to: .init(method: "POST", target: "/dicomweb/workitems",
            headers: .init([("Content-Type", "application/dicom+json")]), body: Data("{}".utf8)), origin: "http://example.test")
        check(bad, 400)
    }

    func testSearchReturnsRequiredAttributesAndPagination() async throws {
        let steps = DICOMUnifiedProcedureStepService()
        let server = origin(steps)
        _ = try await steps.create(uid, scheduled())
        _ = try await steps.create("2.25.202610212001", scheduled())
        let response = try await request(server, "GET", "/workitems?ProcedureStepState=SCHEDULED&limit=1")
        check(response, 200)
        let data = try await response.collectBody()
        let matches = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(matches.count, 1)
        XCTAssertNotNil(matches[0]["00080018"])
        XCTAssertNotNil(matches[0]["00100010"])
        XCTAssertNil(matches[0]["00081195"])
        XCTAssertNotNil(response.headers["Warning"])
        let empty = try await request(server, "GET", "/workitems?ProcedureStepLabel=Nothing")
        check(empty, 200)
        let emptyData = try await empty.collectBody()
        XCTAssertEqual(String(data: emptyData, encoding: .utf8), "[]")
        check(try await request(server, "GET", "/workitems?TransactionUID=2.25.7"), 400)
        check(try await request(server, "GET", "/workitems?offset=-1"), 400)
    }

    func testSubscriptionsEventEnvelopeDisconnectAndSuspend() async throws {
        let steps = DICOMUnifiedProcedureStepService()
        let server = origin(steps)
        let listener = await steps.eventHub.connect(ae: "WATCHER")
        var iterator = listener.events.makeAsyncIterator()
        let global = "/workitems/" + DICOMSOPClass.upsGlobalSubscription + "/subscribers/WATCHER"
        let sub = try await request(server, "POST", global + "?deletionlock=true")
        check(sub, 201)
        XCTAssertEqual(sub.headers["Content-Location"], "ws://example.test/dicomweb/subscribers/WATCHER")
        check(try await request(server, "POST", "/workitems?workitem=" + uid, object: scheduled()), 201)
        let firstData = try await iterator.next()
        let first = try XCTUnwrap(firstData)
        let event = try XCTUnwrap(JSONSerialization.jsonObject(with: first) as? [String: Any])
        XCTAssertEqual(DICOMUnifiedProcedureStepService.value(event, "00000002"), DICOMSOPClass.upsEvent)
        XCTAssertEqual(((event["00001002"] as? [String: Any])?["Value"] as? [Int])?.first, 1)
        check(try await request(server, "PUT", "/workitems/" + uid + "/state?requester=OWNER",
            object: ["00741000": value("CS", "IN PROGRESS"), "00081195": value("UI", "2.25.7")]), 200)
        let ownerData = try await iterator.next()
        let owner = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(ownerData)) as? [String: Any])
        XCTAssertEqual(DICOMUnifiedProcedureStepService.value(owner, "00741236"), "OWNER")
        await steps.eventHub.disconnect(listener.id)
        let persisted = try await steps.index.document("WATCHER|" + uid, in: .unifiedProcedureStepSubscriptions)
        XCTAssertEqual(persisted?.metadata["lock"], "TRUE")
        let reconnect = await steps.eventHub.connect(ae: "WATCHER")
        var resumed = reconnect.events.makeAsyncIterator()
        check(try await request(server, "POST", "/workitems/" + uid + "/cancelrequest?requester=REMOTE"), 202)
        let nextData = try await resumed.next()
        let next = try XCTUnwrap(nextData)
        let cancel = try XCTUnwrap(JSONSerialization.jsonObject(with: next) as? [String: Any])
        XCTAssertEqual(DICOMUnifiedProcedureStepService.value(cancel, "00741236"), "REMOTE")
        check(try await request(server, "POST", global + "/suspend"), 200)
        let specific = try await steps.index.document("WATCHER|" + uid, in: .unifiedProcedureStepSubscriptions)
        XCTAssertNotNil(specific)
        check(try await request(server, "DELETE", global), 200)
        check(try await request(server, "DELETE", "/workitems/" + uid + "/subscribers/WATCHER"), 404)
        await steps.eventHub.disconnect(reconnect.id)
    }

    func testUIDAndSubscriptionPayloadValidation() async throws {
        let steps = DICOMUnifiedProcedureStepService()
        let server = origin(steps)
        check(try await request(server, "POST", "/workitems", object: scheduled()), 400)
        var object = scheduled()
        object["00080018"] = value("UI", uid)
        check(try await request(server, "POST", "/workitems?workitem=2.25.42", object: object), 400)
        var bulk = object
        bulk["7FE00010"] = ["vr": "OB", "BulkDataURI": "https://example.test/bulk"]
        check(try await request(server, "POST", "/workitems", object: bulk), 400)
        check(try await request(server, "POST", "/workitems", object: object), 201)
        check(try await request(server, "POST", "/workitems/" + uid + "/subscribers/AE", object: [:]), 400)
        check(try await request(server, "PUT", "/workitems/" + uid + "/state?requester=%20%20", object: [:]), 400)
    }

    func testSlowConsumerIsDisconnectedWithoutLosingSubscription() async throws {
        let steps = DICOMUnifiedProcedureStepService()
        let listener = await steps.eventHub.connect(ae: "SLOW", bufferLimit: 1)
        _ = try await steps.create(uid, scheduled())
        _ = try await steps.subscription(uid, action: 3, object: ["00741234": value("AE", "SLOW"), "00741230": value("CS", "TRUE")])
        _ = try await steps.changeState(uid, ["00741000": value("CS", "IN PROGRESS"), "00081195": value("UI", "2.25.7")])
        let connected = await steps.eventHub.isConnected("SLOW")
        XCTAssertFalse(connected)
        let stored = try await steps.index.document("SLOW|" + uid, in: .unifiedProcedureStepSubscriptions)
        XCTAssertNotNil(stored)
        await steps.eventHub.disconnect(listener.id)
    }
}
