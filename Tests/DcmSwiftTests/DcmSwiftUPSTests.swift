import XCTest
@testable import DcmSwift

final class DcmSwiftUPSTests: XCTestCase {
    private let uid = "2.25.341341"

    private func assertStatus(_ response: DICOMNormalizedResponse, _ expected: UInt16, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(response.status.code, expected, file: file, line: line)
    }

    private func value(_ vr: String, _ text: String) -> [String: Any] {
        ["vr": vr, "Value": [text]]
    }

    private func scheduled() -> [String: Any] {
        var object: [String: Any] = [
            "00741200": value("CS", "MEDIUM"),
            "00741204": value("LO", "Review"),
            "00404005": value("DT", "20261009120000+0200"),
            "00404041": value("CS", "READY"),
            "00741000": value("CS", "SCHEDULED"),
        ]
        for tag in ["00081195", "00741202", "00400400", "00100010", "00100021",
                    "00100030", "00100040", "00380010", "00081080"] {
            let vr = ["00081195": "UI", "00400400": "LT", "00100010": "PN",
                      "00100030": "DA", "00100040": "CS"][tag] ?? "LO"
            object[tag] = ["vr": vr]
        }
        for tag in ["00741210", "00404025", "00404026", "00404027", "00404018",
                    "00404021", "00100024", "00101002", "00380014", "00081084",
                    "0040A370", "00741002", "00741216"] {
            object[tag] = ["vr": "SQ"]
        }
        return object
    }

    private func state(_ name: String, token: String = "2.25.455") -> [String: Any] {
        ["00741000": value("CS", name), "00081195": value("UI", token)]
    }

    func testCreationFillsMissingType2AttributesWithCorrectVRs() async throws {
        let service = DICOMUnifiedProcedureStepService()
        let type1: Set<String> = ["00741200", "00741204", "00404005", "00404041", "00741000"]
        let complete = scheduled()
        let minimal = complete.filter { type1.contains($0.key) }
        assertStatus(try await service.create(uid, minimal), 0)
        let document = try await service.index.document(uid, in: .unifiedProcedureSteps)
        let stored = try XCTUnwrap(document).attributes
        for (tag, expected) in complete where !type1.contains(tag) {
            let attribute = try XCTUnwrap(stored[tag] as? [String: Any], tag)
            let expectedVR = (expected as? [String: Any])?["vr"] as? String
            XCTAssertEqual(attribute["vr"] as? String, expectedVR, tag)
            if tag == "00741202" {
                XCTAssertEqual(DICOMUnifiedProcedureStepService.value(stored, tag), "DEFAULT")
            } else {
                XCTAssertEqual(attribute.count, 1, "\(tag) must be empty, including SQ attributes")
                XCTAssertNil(attribute["Value"], tag)
            }
        }
    }

    func testCreationPreservesSuppliedType2Elements() async throws {
        let service = DICOMUnifiedProcedureStepService()
        var object = scheduled().filter {
            ["00741200", "00741204", "00404005", "00404041", "00741000"].contains($0.key)
        }
        let supplied: [String: Any] = [
            "00741202": value("LO", "RADIOLOGY"),
            "00400400": value("LT", "Keep these instructions"),
            "00100010": ["vr": "PN", "Value": [["Alphabetic": "DOE^JANE"]]],
            "00404025": sequence([code("STATION")]),
            "00081195": ["vr": "UI", "Value": [String]()],
        ]
        object.merge(supplied) { _, provided in provided }
        assertStatus(try await service.create(uid, object), 0)
        let document = try await service.index.document(uid, in: .unifiedProcedureSteps)
        let stored = try XCTUnwrap(document).attributes
        for (tag, expected) in supplied {
            XCTAssertEqual(stored[tag] as? NSDictionary, expected as? NSDictionary, tag)
        }
    }

    func testCreationStateLockAndFinalRequirements() async throws {
        let index = DICOMMemoryArchiveIndex()
        let service = DICOMUnifiedProcedureStepService(index: index)
        assertStatus(try await service.create(uid, scheduled()), 0)
        let created = await index.document(uid, in: .unifiedProcedureSteps)
        XCTAssertEqual(((created?.attributes["00741202"] as? [String: Any])?["Value"] as? [String])?.first,
                       "DEFAULT", "the SCP fills an empty Worklist Label")
        assertStatus(try await service.create(uid, scheduled()), 0x0111)
        assertStatus(try await service.changeState(uid, state("COMPLETED")), 0xC310)
        assertStatus(try await service.changeState(uid, state("SCHEDULED")), 0xC303)
        assertStatus(try await service.changeState(uid, state("IN PROGRESS")), 0)
        assertStatus(try await service.changeState(uid, state("IN PROGRESS")), 0xC302)
        assertStatus(try await service.changeState(uid, state("COMPLETED", token: "2.25.999")), 0xC301)
        assertStatus(try await service.set(uid, ["00081195": value("UI", "2.25.999")]), 0xC301)
        assertStatus(try await service.changeState(uid, state("COMPLETED")), 0xC304)
        let performed: [String: Any] = [
            "00404028": ["vr": "SQ", "Value": [code("STATION")]],
            "00404050": value("DT", "20261009120500+0200"),
            "00404019": ["vr": "SQ", "Value": [code("WORK")]],
            "00404051": value("DT", "20261009121000+0200"),
            "00404033": ["vr": "SQ"],
        ]
        assertStatus(try await service.set(uid, ["00081195": value("UI", "2.25.455"),
                                                    "00741216": ["vr": "SQ", "Value": [performed]]]), 0)
        assertStatus(try await service.changeState(uid, state("COMPLETED")), 0)
        assertStatus(try await service.changeState(uid, state("COMPLETED")), 0xB306)
        assertStatus(try await service.set(uid, ["00081195": value("UI", "2.25.455")]), 0xC300)
        let reply = try await service.get(uid)
        let object = try DICOMJSON.object(reply.dataSet!, options: .init(numbersAsStrings: true))
        XCTAssertNil(object["00081195"], "Transaction UID is not returned by N-GET")
    }

    func testScheduledCancelAndQuery() async throws {
        let service = DICOMUnifiedProcedureStepService()
        assertStatus(try await service.create(uid, scheduled()), 0)
        assertStatus(try await service.cancel(uid, [:], requestingAE: "SCU"), 0)
        let canceled = try await service.index.document(uid, in: .unifiedProcedureSteps)
        XCTAssertNotNil(DICOMUnifiedProcedureStepService.items(canceled!.attributes, "00741002").first?["00404052"], "the SCP fills Cancellation DateTime")
        assertStatus(try await service.cancel(uid, [:], requestingAE: "SCU"), 0xB304)
        let query = try DICOMJSON.dataSet(["00741000": value("CS", "CANCELED")])
        let results = try await service.matches(query)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].string(forTag: "ProcedureStepState"), "CANCELED")
    }

    func testGlobalSubscriptionPersistsForNewSteps() async throws {
        let index = DICOMMemoryArchiveIndex()
        let service = DICOMUnifiedProcedureStepService(index: index)
        let subscribe = ["00741234": value("AE", "WATCHER"), "00741230": value("CS", "TRUE")]
        assertStatus(try await service.subscription(DICOMSOPClass.upsGlobalSubscription,
                                                       action: 3, object: subscribe), 0)
        assertStatus(try await service.create(uid, scheduled()), 0)
        let subscriptions = await index.documents(in: .unifiedProcedureStepSubscriptions,
                                                       matching: DICOMQuery(conditions: []))
        XCTAssertEqual(subscriptions.count, 2)
        XCTAssertTrue(subscriptions.contains { $0.metadata["uid"] == uid && $0.metadata["lock"] == "TRUE" })
        assertStatus(try await service.subscription(DICOMSOPClass.upsGlobalSubscription,
                                                       action: 4, object: subscribe), 0)
        let after = await index.documents(in: .unifiedProcedureStepSubscriptions,
                                              matching: DICOMQuery(conditions: []))
        XCTAssertTrue(after.isEmpty)
    }

    func testFilteredGlobalSubscriptionOnlySelectsMatchingSteps() async throws {
        let index = DICOMMemoryArchiveIndex()
        let service = DICOMUnifiedProcedureStepService(index: index)
        let filter = ["00741234": value("AE", "WATCHER"),
                      "00741230": value("CS", "FALSE"),
                      "00741200": value("CS", "HIGH")]
        assertStatus(try await service.subscription(DICOMSOPClass.upsFilteredGlobalSubscription,
                                                     action: 3, object: filter), 0)
        assertStatus(try await service.create(uid, scheduled()), 0)
        var high = scheduled()
        high["00741200"] = value("CS", "HIGH")
        assertStatus(try await service.create("2.25.341342", high), 0)
        let subscriptions = await index.documents(in: .unifiedProcedureStepSubscriptions,
                                                       matching: DICOMQuery(conditions: []))
        XCTAssertEqual(subscriptions.count, 2)
        XCTAssertTrue(subscriptions.contains { $0.metadata["uid"] == "2.25.341342" })
        XCTAssertFalse(subscriptions.contains { $0.metadata["uid"] == uid })
    }
    private func code(_ text: String = "TEST") -> [String: Any] {
        ["00080100": value("SH", text), "00080102": value("SH", "99TEST"), "00080104": value("LO", text)]
    }

    private func sequence(_ items: [[String: Any]]) -> [String: Any] { ["vr": "SQ", "Value": items] }

    func testNestedRequirementsAndAtomicSet() async throws {
        let service = DICOMUnifiedProcedureStepService()
        var object = scheduled()
        object["00404034"] = sequence([["00404009": sequence([code()])]])
        assertStatus(try await service.create(uid, object), 0x0106)
        object["00404034"] = sequence([["00404009": sequence([code()]),
                                        "00404037": value("PN", "DOE^JANE"), "00404036": value("LO", "HOSPITAL")]])
        assertStatus(try await service.create(uid, object), 0)
        assertStatus(try await service.set(uid, ["00741200": value("CS", "HIGH"),
                                                "00404025": sequence([["00080100": value("SH", "BAD")]])]), 0x0106)
        let stored = try await service.index.document(uid, in: .unifiedProcedureSteps)!
        XCTAssertEqual(DICOMUnifiedProcedureStepService.value(stored.attributes, "00741200"), "MEDIUM")
        for tag in ["00100021", "00100024", "00380010", "00380014", "00081080", "00081084", "0040A370"] {
            assertStatus(try await service.set(uid, [tag: ["vr": "LO"]]), 0x0106)
        }
        assertStatus(try await service.set(uid, ["00081195": ["vr": "UI"]]), 0xC301)
        assertStatus(try await service.set(uid, ["00404011": value("DT", "20261021190000")]), 0x0105)
    }

    func testCreationStatusAndRequiredValues() async throws {
        for (tag, vr, text) in [("00741000", "CS", "COMPLETED"), ("00741200", "CS", "URGENT"),
                                ("00404041", "CS", "UNKNOWN")] {
            let service = DICOMUnifiedProcedureStepService()
            var object = scheduled(); object[tag] = value(vr, text)
            assertStatus(try await service.create(uid, object), tag == "00741000" ? 0xC309 : 0x0106)
        }
        let type1: Set<String> = ["00741200", "00741204", "00404005", "00404041", "00741000"]
        for tag in type1 {
            let service = DICOMUnifiedProcedureStepService()
            var object = scheduled().filter { type1.contains($0.key) }
            let attribute = try XCTUnwrap(object.removeValue(forKey: tag) as? [String: Any])
            assertStatus(try await service.create(uid, object), 0x0120)
            for empty: [String: Any] in [["vr": attribute["vr"]!],
                                         ["vr": attribute["vr"]!, "Value": [String]()],
                                         ["vr": attribute["vr"]!, "Value": [""]]] {
                object[tag] = empty
                assertStatus(try await service.create(uid, object), 0x0121)
            }
        }
    }

    func testContentAndReferenceMacros() async throws {
        let service = DICOMUnifiedProcedureStepService()
        var object = scheduled()
        object["00741210"] = sequence([["0040A040": value("CS", "NUMERIC"), "0040A043": sequence([code()]),
                                        "0040A30A": value("DS", "4")]])
        assertStatus(try await service.create(uid, object), 0x0106)
        object["00741210"] = sequence([["0040A040": value("CS", "NUMERIC"), "0040A043": sequence([code()]),
                                        "0040A30A": value("DS", "4"), "004008EA": sequence([code("mm")])]])
        object["00404021"] = sequence([["0040E020": value("CS", "DICOM"), "00081199": sequence([
            ["00081150": value("UI", "1.2.840.10008.5.1.4.1.1.2"), "00081155": value("UI", "2.25.123")]
        ])]])
        assertStatus(try await service.create(uid, object), 0x0106)
        var reference = DICOMUnifiedProcedureStepService.items(object, "00404021")[0]
        reference["0020000D"] = value("UI", "2.25.10")
        reference["0020000E"] = value("UI", "2.25.11")
        reference["0040E025"] = sequence([["00081190": value("UR", "https://example.test/instances/123")]])
        object["00404021"] = sequence([reference])
        assertStatus(try await service.create(uid, object), 0)
    }

    func testCanceledFinalRequirementsAreNestedAndPersist() async throws {
        let service = DICOMUnifiedProcedureStepService()
        assertStatus(try await service.create(uid, scheduled()), 0)
        assertStatus(try await service.changeState(uid, state("IN PROGRESS")), 0)
        assertStatus(try await service.changeState(uid, state("CANCELED")), 0xC304)
        assertStatus(try await service.set(uid, ["00081195": value("UI", "2.25.455"),
            "00741002": sequence([["0074100E": sequence([code("CANCEL")])]])]), 0)
        assertStatus(try await service.changeState(uid, state("CANCELED")), 0)
        let stored = try await service.index.document(uid, in: .unifiedProcedureSteps)!
        XCTAssertNil(stored.attributes["00404052"])
        XCTAssertNotNil(DICOMUnifiedProcedureStepService.items(stored.attributes, "00741002")[0]["00404052"])
        assertStatus(try await service.changeState(uid, state("CANCELED")), 0xB304)
        assertStatus(try await service.changeState(uid, state("COMPLETED")), 0xC300)
    }

    func testGlobalPreservesSpecificLocksAndSuspendPreservesInstances() async throws {
        let index = DICOMMemoryArchiveIndex()
        let service = DICOMUnifiedProcedureStepService(index: index)
        assertStatus(try await service.create(uid, scheduled()), 0)
        let unlocked = ["00741234": value("AE", "WATCHER"), "00741230": value("CS", "FALSE")]
        let locked = ["00741234": value("AE", "WATCHER"), "00741230": value("CS", "TRUE")]
        assertStatus(try await service.subscription(uid, action: 3, object: unlocked), 0)
        assertStatus(try await service.subscription(DICOMSOPClass.upsGlobalSubscription, action: 3, object: locked), 0)
        var sub = await index.document("WATCHER|" + uid, in: .unifiedProcedureStepSubscriptions)
        XCTAssertEqual(sub?.metadata["lock"], "FALSE")
        assertStatus(try await service.subscription(uid, action: 3, object: locked), 0)
        assertStatus(try await service.subscription(DICOMSOPClass.upsGlobalSubscription, action: 3, object: unlocked), 0)
        sub = await index.document("WATCHER|" + uid, in: .unifiedProcedureStepSubscriptions)
        XCTAssertEqual(sub?.metadata["lock"], "TRUE")
        assertStatus(try await service.subscription(DICOMSOPClass.upsGlobalSubscription, action: 5, object: unlocked), 0)
        assertStatus(try await service.cancel(uid, [:], requestingAE: "SCU"), 0)
        assertStatus(try await service.get(uid), 0)
        sub = await index.document("WATCHER|" + uid, in: .unifiedProcedureStepSubscriptions)
        XCTAssertEqual(sub?.metadata["lock"], "TRUE", "final state does not release a deletion lock")
        assertStatus(try await service.subscription(uid, action: 4, object: unlocked), 0)
        sub = await index.document("WATCHER|" + uid, in: .unifiedProcedureStepSubscriptions)
        XCTAssertNil(sub)
        assertStatus(try await service.get(uid), 0, file: #filePath, line: #line)
        assertStatus(try await service.create("2.25.341343", scheduled()), 0)
        let all = await index.documents(in: .unifiedProcedureStepSubscriptions, matching: DICOMQuery(conditions: []))
        XCTAssertTrue(all.isEmpty)
    }

    func testConcurrentClaimHasOneOwner() async throws {
        let index = DICOMMemoryArchiveIndex()
        let a = DICOMUnifiedProcedureStepService(index: index)
        let b = DICOMUnifiedProcedureStepService(index: index)
        assertStatus(try await a.create(uid, scheduled()), 0)
        async let first = a.changeState(uid, state("IN PROGRESS", token: "2.25.1"))
        async let second = b.changeState(uid, state("IN PROGRESS", token: "2.25.2"))
        let responses = try await [first, second]
        XCTAssertEqual(responses.filter { $0.status.code == 0 }.count, 1)
        XCTAssertEqual(responses.filter { $0.status.code == 0xC301 }.count, 1)
    }

    func testCompletionChecksEveryRequiredPerformedAttribute() async throws {
        for omitted in ["00404028", "00404050", "00404019", "00404051", "00404033"] {
            let index = DICOMMemoryArchiveIndex()
            let service = DICOMUnifiedProcedureStepService(index: index)
            assertStatus(try await service.create(uid, scheduled()), 0)
            assertStatus(try await service.changeState(uid, state("IN PROGRESS")), 0)
            var performed: [String: Any] = ["00404028": sequence([code()]), "00404019": sequence([code()]),
                "00404050": value("DT", "20261021180000"), "00404051": value("DT", "20261021190000"),
                "00404033": sequence([])]
            performed.removeValue(forKey: omitted)
            var stored = await index.document(uid, in: .unifiedProcedureSteps)!
            stored.attributes["00741216"] = sequence([performed])
            _ = try await index.replace(stored, in: .unifiedProcedureSteps)
            assertStatus(try await service.changeState(uid, state("COMPLETED")), 0xC304)
        }
    }

    func testQueryRestrictionsAndSetTypeOneValues() async throws {
        let service = DICOMUnifiedProcedureStepService()
        assertStatus(try await service.create(uid, scheduled()), 0)
        for tag in ["00741202", "00400400", "00404018"] {
            assertStatus(try await service.set(uid, [tag: ["vr": tag == "00404018" ? "SQ" : "LO"]]), 0x0106)
        }
        for keys in [["00081195": value("UI", "")], ["00741000": value("CS", "IN*")],
                     ["00080018": value("UI", "2.25.*")]] {
            do {
                _ = try await service.matches(DICOMJSON.dataSet(keys))
                XCTFail("forbidden matching key accepted")
            } catch is DICOMServiceError { }
        }
    }

    func testStateTransitionTableAndFinalAttributeProtection() async throws {
        for initial in ["SCHEDULED", "IN PROGRESS", "COMPLETED", "CANCELED"] {
            for desired in ["SCHEDULED", "IN PROGRESS", "COMPLETED", "CANCELED"] {
                for correctToken in [true, false] {
                    let index = DICOMMemoryArchiveIndex()
                    let service = DICOMUnifiedProcedureStepService(index: index)
                    assertStatus(try await service.create(uid, scheduled()), 0)
                    var stored = await index.document(uid, in: .unifiedProcedureSteps)!
                    stored.attributes["00741000"] = value("CS", initial)
                    stored.attributes["00081195"] = value("UI", "2.25.455")
                    _ = try await index.replace(stored, in: .unifiedProcedureSteps)
                    let expected: UInt16
                    if desired == "SCHEDULED" { expected = 0xC303 }
                    else if !correctToken && initial != "SCHEDULED" { expected = 0xC301 }
                    else if initial == desired && desired == "COMPLETED" { expected = 0xB306 }
                    else if initial == desired && desired == "CANCELED" { expected = 0xB304 }
                    else if initial == "COMPLETED" || initial == "CANCELED" { expected = 0xC300 }
                    else if desired == "IN PROGRESS" { expected = initial == "SCHEDULED" ? 0 : 0xC302 }
                    else { expected = initial == "SCHEDULED" ? 0xC310 : 0xC304 }
                    assertStatus(try await service.changeState(uid, state(desired, token: correctToken ? "2.25.455" : "2.25.999")), expected)
                }
            }
        }
    }

    func testSubscriptionsSurviveRestartAndUnknownRecipientsFail() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let subscription = ["00741234": value("AE", "WATCHER"), "00741230": value("CS", "TRUE")]
        let first = DICOMUnifiedProcedureStepService(index: DICOMFileArchiveIndex(directory: directory))
        assertStatus(try await first.create(uid, scheduled()), 0)
        assertStatus(try await first.subscription(uid, action: 3, object: subscription), 0)
        assertStatus(try await first.cancel(uid, [:], requestingAE: "SCU"), 0)
        let index = DICOMFileArchiveIndex(directory: directory)
        let restarted = DICOMUnifiedProcedureStepService(index: index, receivingAEs: [])
        assertStatus(try await restarted.get(uid), 0)
        let persisted = try await index.document("WATCHER|" + uid, in: .unifiedProcedureStepSubscriptions)
        XCTAssertEqual(persisted?.metadata["lock"], "TRUE")
        assertStatus(try await restarted.subscription(uid, action: 3, object: subscription), 0xC308)
        let disabled = DICOMUnifiedProcedureStepService(index: index, eventReportsSupported: false)
        assertStatus(try await disabled.subscription(uid, action: 3, object: subscription), 0xC315)
        assertStatus(try await restarted.subscription(DICOMSOPClass.upsGlobalSubscription, action: 4, object: subscription), 0)
        let remaining = try await index.documents(in: .unifiedProcedureStepSubscriptions, matching: DICOMQuery(conditions: []))
        XCTAssertTrue(remaining.isEmpty)
    }

    func testEventReceiverValidatesRequiredInformation() async throws {
        let reports = UPSReports()
        let service = DICOMUnifiedProcedureStepService(receive: { uid, type, data in
            await reports.record("SOURCE", uid, type, data)
        })
        assertStatus(try await service.receiveEvent(uid, type: 1, object: [:]), 0x0120)
        assertStatus(try await service.receiveEvent(uid, type: 1, object: ["00741000": value("CS", "SCHEDULED"),
                                                                         "00404041": value("CS", "READY")]), 0)
        assertStatus(try await service.receiveEvent(uid, type: 6, object: [:]), 0x0113)
        let events = await reports.types
        XCTAssertEqual(events, [1])
    }

    func testEventTriggersAndStatusRecipients() async throws {
        let reports = UPSReports()
        let service = DICOMUnifiedProcedureStepService(notify: { ae, uid, type, data in
            await reports.record(ae, uid, type, data)
        })
        var object = scheduled()
        object["00404034"] = sequence([])
        assertStatus(try await service.subscription(DICOMSOPClass.upsGlobalSubscription, action: 3,
            object: ["00741234": value("AE", "WATCHER"), "00741230": value("CS", "TRUE")]), 0)
        assertStatus(try await service.create(uid, object), 0)
        assertStatus(try await service.set(uid, ["00404041": value("CS", "UNAVAILABLE")]), 0)
        assertStatus(try await service.set(uid, ["00404025": sequence([code("STATION")])]), 0)
        assertStatus(try await service.set(uid, ["00404025": sequence([code("STATION")])]), 0)
        assertStatus(try await service.set(uid, ["00741002": sequence([["00741006": value("ST", "Working")]])]), 0)
        try await service.reportStatus(restarted: true, fallbackAEs: ["WATCHER", "FALLBACK"])
        let events = await reports.types
        XCTAssertEqual(events, [1, 1, 5, 3, 4, 4], "idempotent set emits no duplicate assignment")
        assertStatus(try await service.cancel(uid, [:], requestingAE: "SCU"), 0)
        let finalEvents = await reports.types
        XCTAssertEqual(Array(finalEvents.suffix(3)), [2, 1, 1])
    }

}


private actor UPSReports {
    var types: [UInt16] = []
    func record(_ ae: String, _ uid: String, _ type: UInt16, _ data: DataSet) { types.append(type) }
}
