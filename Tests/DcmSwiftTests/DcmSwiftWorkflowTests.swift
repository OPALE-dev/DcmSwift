import XCTest
@testable import DcmSwift

/// Workflow services (PS3.4 F, K): C-FIND matching rules and the Modality
/// Worklist over the loopback interface.
final class DcmSwiftWorkflowTests: XCTestCase {
    // MARK: Fixtures

    /// A data set from DICOM JSON attributes, written as tag: (VR, values);
    /// a SQ takes arrays of such dictionaries.
    static func dataSet(_ attributes: [String: (String, [Any])]) throws -> DataSet {
        try DICOMJSON.dataSet(object(attributes))
    }

    static func object(_ attributes: [String: (String, [Any])]) -> [String: Any] {
        attributes.mapValues { vr, values -> [String: Any] in
            var attribute: [String: Any] = ["vr": vr]
            if vr == "SQ" {
                attribute["Value"] = values.map { object($0 as! [String: (String, [Any])]) }
            } else if vr == "PN" {
                attribute["Value"] = values.map { ["Alphabetic": $0] }
            } else if !values.isEmpty {
                attribute["Value"] = values
            }
            return attribute
        }
    }

    /// A worklist item: one Scheduled Procedure Step.
    static func item(
        patient: String, id: String, station: String, modality: String, date: String, time: String,
        physician: String = "Smith^Ann", accession: String = "A1"
    ) throws -> DataSet {
        try dataSet([
            "00100010": ("PN", [patient]),
            "00100020": ("LO", [id]),
            "00080050": ("SH", [accession]),
            "0020000D": ("UI", ["1.2.826.0.1.3680043.2.1125.\(id.count)"]),
            "00400100": ("SQ", [[
                "00400001": ("AE", [station]),
                "00080060": ("CS", [modality]),
                "00400002": ("DA", [date]),
                "00400003": ("TM", [time]),
                "00400006": ("PN", [physician]),
                "00400009": ("SH", ["SPS-\(id)"]),
            ]]),
        ])
    }

    static func worklistQuery(
        patient: String = "", station: String = "", modality: String = "", date: String = "", time: String = ""
    ) throws -> DataSet {
        try dataSet([
            "00100010": ("PN", patient.isEmpty ? [] : [patient]),
            "00100020": ("LO", []),
            "00400100": ("SQ", [[
                "00400001": ("AE", station.isEmpty ? [] : [station]),
                "00080060": ("CS", modality.isEmpty ? [] : [modality]),
                "00400002": ("DA", date.isEmpty ? [] : [date]),
                "00400003": ("TM", time.isEmpty ? [] : [time]),
                "00400009": ("SH", []),
            ]]),
        ])
    }

    // MARK: Matching (PS3.4 C.2.2.2)

    func testValueMatchingRules() {
        typealias M = DICOMQueryMatcher
        XCTAssertTrue(M.matches("DOE^JOHN", key: "doe*", vr: "PN"))
        XCTAssertTrue(M.matches("Müller^Hans", key: "MULLER*", vr: "PN"))
        XCTAssertTrue(M.matches("Wang^XiaoDong=王^小東", key: "王^小東", vr: "PN"))
        XCTAssertTrue(M.matches("DOE^JOHN^^^", key: "DOE^JOHN", vr: "PN"))
        XCTAssertFalse(M.matches("CT", key: "ct", vr: "CS"))
        XCTAssertTrue(M.matches("CT", key: "C?", vr: "CS"))
        XCTAssertTrue(M.matches("007", key: "7", vr: "IS"))
        // Dates and times by meaning, each bound covering its precision.
        XCTAssertTrue(M.matches("223000", key: "2230", vr: "TM"))
        XCTAssertTrue(M.matches("22:30:59", key: "2230", vr: "TM"))
        XCTAssertFalse(M.matches("223100", key: "2230", vr: "TM"))
        XCTAssertTrue(M.matches("101500", key: "10-11", vr: "TM"))
        XCTAssertTrue(M.matches("115959.999", key: "10-11", vr: "TM"))
        XCTAssertFalse(M.matches("120000", key: "10-11", vr: "TM"))
        XCTAssertFalse(M.matches("120000", key: "2200-0200", vr: "TM"), "ranges crossing midnight are not supported")
        XCTAssertTrue(M.matches("20240131", key: "20240101-20240131", vr: "DA"))
        XCTAssertTrue(M.matches("2024.01.31", key: "-20240131", vr: "DA"))
        XCTAssertFalse(M.matches("20240201", key: "-20240131", vr: "DA"))
        XCTAssertTrue(M.matches("19980128103000.0000", key: "19980128103000", vr: "DT"))
        XCTAssertTrue(M.matches("19980128103000", key: "19980128073000-0300-", vr: "DT"))
        XCTAssertTrue(M.matches("19980128103000+0100", key: "199801280930", vr: "DT"))
        XCTAssertTrue(M.matches("20240315", key: "202403", vr: "DT"))
    }

    func testCombinedDateTimeAndSequenceMatching() throws {
        let item = try Self.item(patient: "DOE^JANE", id: "P1", station: "CT1", modality: "CT",
                                 date: "20240706", time: "080000")
        let matcher = DICOMQueryMatcher.modalityWorklist
        // July 5 10:00 to July 7 18:00 includes July 6 08:00 as one period...
        XCTAssertNotNil(try matcher.match(
            Self.worklistQuery(date: "20240705-20240707", time: "1000-1800"), against: item))
        // ...but not as three daily periods.
        XCTAssertNil(try DICOMQueryMatcher().match(
            Self.worklistQuery(date: "20240705-20240707", time: "1000-1800"), against: item))
        XCTAssertNil(try matcher.match(Self.worklistQuery(date: "20240706", time: "1000-1800"), against: item))
        XCTAssertNil(try matcher.match(Self.worklistQuery(station: "CT2"), against: item))
        XCTAssertNil(try matcher.match(Self.worklistQuery(modality: "MR"), against: item))

        let response = try XCTUnwrap(matcher.match(Self.worklistQuery(patient: "doe*", station: "CT1"), against: item))
        XCTAssertEqual(response.string(forTag: "PatientID"), "P1")
        XCTAssertNil(response.element(forTagName: "AccessionNumber"), "only requested keys are returned")
        let step = try XCTUnwrap(response.sequence(forTagName: "ScheduledProcedureStepSequence")?.items.first)
        XCTAssertEqual(step.element(withName: "ScheduledProcedureStepID")?.value as? String, "SPS-P1")
        XCTAssertNil(step.element(withName: "ScheduledPerformingPhysicianName"))

        // An empty sequence key returns the whole sequence.
        let whole = try Self.dataSet(["00400100": ("SQ", [])])
        let all = try XCTUnwrap(matcher.match(whole, against: item))
        XCTAssertEqual(all.sequence(forTagName: "ScheduledProcedureStepSequence")?.items.first?.elements.count, 6)

        // An unknown value does not match a key that is not universal.
        let noAccession = try Self.dataSet(["00080050": ("SH", ["A1"])])
        let bare = try Self.dataSet(["00100020": ("LO", ["P2"])])
        XCTAssertNil(try matcher.match(noAccession, against: bare))
        XCTAssertNotNil(try matcher.match(try Self.dataSet(["00080050": ("SH", [])]), against: bare))
    }

    // MARK: Modality Worklist (PS3.4 K.6)

    func testModalityWorklistOverTheNetwork() async throws {
        let worklist = DICOMModalityWorklist()
        await worklist.add(try Self.item(patient: "DOE^JANE", id: "P1", station: "CT1", modality: "CT",
                                         date: "20240706", time: "080000"))
        await worklist.add(try Self.item(patient: "ROE^RICHARD", id: "P2", station: "MR1", modality: "MR",
                                         date: "20240707", time: "190000"))
        let server = try DICOMServer(
            configuration: DICOMServerConfiguration(aeTitle: "RIS", host: "127.0.0.1", port: 0), worklist: worklist)
        let ready = AsyncStream<Int>.makeStream()
        let task = Task { try await server.run { ready.continuation.yield($0) } }
        var iterator = ready.stream.makeAsyncIterator()
        guard let port = await iterator.next() else { throw DICOMNetworkError.connectionClosed }
        defer { task.cancel() }

        let client = try DICOMClient(configuration: DICOMClientConfiguration(aeTitle: "CT1"))
        let model = DICOMSOPClass.modalityWorklistFind
        try await client.withAssociation(
            to: DICOMRemoteNode(aeTitle: "RIS", host: "127.0.0.1", port: port),
            presentationContexts: .proposals(abstractSyntaxes: [model])
        ) { association in
            var ids: [String] = []
            for try await match in association.find(try Self.worklistQuery(station: "CT1"), informationModel: model) {
                ids.append(match.string(forTag: "PatientID") ?? "")
            }
            XCTAssertEqual(ids, ["P1"])
            ids = []
            for try await match in association.find(
                try Self.worklistQuery(date: "20240705-20240707", time: "1000-1800"), informationModel: model) {
                ids.append(match.string(forTag: "PatientID") ?? "")
            }
            XCTAssertEqual(ids, ["P1"])

            // A Scheduled Procedure Step Sequence with two Items: A900.
            let invalid = try Self.dataSet(["00400100": ("SQ", [
                ["00080060": ("CS", ["CT"])], ["00080060": ("CS", ["MR"])],
            ])])
            do {
                for try await _ in association.find(invalid, informationModel: model) {}
                XCTFail("an invalid Identifier was answered")
            } catch let error as DICOMServiceError {
                XCTAssertEqual(error.status, .identifierDoesNotMatchSOPClass)
            }
        }
        task.cancel()
        _ = try? await task.value
    }

    func testWorklistItemsFromADirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dcmswift-worklist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let item = try Self.item(patient: "DOE^JANE", id: "P1", station: "CT1", modality: "CT",
                                 date: "20240706", time: "080000")
        // A bare data set in Implicit VR (as DCMTK .wl files), DICOM JSON.
        try DICOMDataSetCoding.encode(item, transferSyntax: TransferSyntax.implicitVRLittleEndian)
            .write(to: directory.appendingPathComponent("one.wl"))
        try DICOMJSON.encode(item).write(to: directory.appendingPathComponent("two.json"))
        let items = DICOMModalityWorklist.items(in: directory)
        XCTAssertEqual(items.count, 2)
        for item in items {
            XCTAssertEqual(item.sequence(forTagName: "ScheduledProcedureStepSequence")?.items.count, 1)
            XCTAssertEqual(item.string(forTag: "PatientID"), "P1")
        }
    }
}
