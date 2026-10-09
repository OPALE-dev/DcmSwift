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

    func testCreationStateLockAndFinalRequirements() async throws {
        let index = DICOMMemoryArchiveIndex()
        let service = DICOMUnifiedProcedureStepService(index: index)
        assertStatus(try await service.create(uid, scheduled()), 0)
        let created = try await index.document(uid, in: .unifiedProcedureSteps)
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
            "00404028": ["vr": "SQ", "Value": [["00080100": value("SH", "STATION")]]],
            "00404050": value("DT", "20261009120500+0200"),
            "00404019": ["vr": "SQ", "Value": [["00080100": value("SH", "WORK")]]],
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
        XCTAssertNotNil(canceled?.attributes["00404052"], "the SCP fills Cancellation DateTime")
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
        let subscriptions = try await index.documents(in: .unifiedProcedureStepSubscriptions,
                                                       matching: DICOMQuery(conditions: []))
        XCTAssertEqual(subscriptions.count, 2)
        XCTAssertTrue(subscriptions.contains { $0.metadata["uid"] == uid && $0.metadata["lock"] == "TRUE" })
        assertStatus(try await service.subscription(DICOMSOPClass.upsGlobalSubscription,
                                                       action: 4, object: subscribe), 0)
        let after = try await index.documents(in: .unifiedProcedureStepSubscriptions,
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
        let subscriptions = try await index.documents(in: .unifiedProcedureStepSubscriptions,
                                                       matching: DICOMQuery(conditions: []))
        XCTAssertEqual(subscriptions.count, 2)
        XCTAssertTrue(subscriptions.contains { $0.metadata["uid"] == "2.25.341342" })
        XCTAssertFalse(subscriptions.contains { $0.metadata["uid"] == uid })
    }
}
