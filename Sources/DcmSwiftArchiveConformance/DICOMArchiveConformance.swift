import DcmSwift
import Foundation

/// Checks that a `DICOMArchiveIndex` behaves as DcmSwift's services expect.
/// It needs no test framework: call `check` from XCTest, Swift Testing, or
/// a command, with a factory of empty indexes.
///
/// ```swift
/// func testConformance() async throws {
///     try await DICOMArchiveConformance.check { try await MySQLIndex.makeEmpty() }
/// }
/// ```
public enum DICOMArchiveConformance {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// Runs every check, each on a new empty index; throws the first
    /// failure.
    public static func check(_ makeIndex: () async throws -> DICOMArchiveIndex) async throws {
        try await documents(makeIndex())
        try await versions(makeIndex())
        try await collections(makeIndex())
        try await queries(makeIndex())
    }

    static func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw Failure(description: message()) }
    }

    static func expectError(_ expected: DICOMArchiveError, _ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch let error as DICOMArchiveError {
            try expect(error == expected, "expected \(expected), got \(error)")
            return
        }
        throw Failure(description: "expected \(expected), got no error")
    }

    static func attribute(_ vr: String, _ values: [Any]) -> [String: Any] {
        values.isEmpty ? ["vr": vr] : ["vr": vr, "Value": values]
    }

    /// Insertion, reading, saving, deletion, and identifiers with any
    /// character.
    static func documents(_ index: DICOMArchiveIndex) async throws {
        let collection = DICOMArchiveCollection.instances
        let id = "1.2.826.0.1.3680043.2.1125.1"
        let document = DICOMArchiveDocument(
            id: id, attributes: ["00100010": attribute("PN", [["Alphabetic": "Müller^Hans"]])],
            metadata: ["location": "a/b.dcm"])
        try await index.insert(document, into: collection)
        let read = try await index.document(id, in: collection)
        try expect(read?.id == id, "an inserted document is read back")
        try expect(read?.metadata == ["location": "a/b.dcm"], "metadata are kept")
        try expect(read?.version == 1, "an inserted document has version 1, not \(read?.version ?? 0)")
        let name = ((read?.attributes["00100010"] as? [String: Any])?["Value"] as? [[String: Any]])?.first?["Alphabetic"]
        try expect(name as? String == "Müller^Hans", "attributes are kept, Unicode included")
        try await expectError(.duplicate(id)) { try await index.insert(document, into: collection) }

        var changed = document
        changed.metadata = ["location": "c.dcm"]
        try await index.save(changed, in: collection)
        try expect(try await index.document(id, in: collection)?.metadata["location"] == "c.dcm", "save replaces")

        let odd = "a/b c:é?"
        try await index.save(DICOMArchiveDocument(id: odd, attributes: [:]), in: collection)
        try expect(try await index.document(odd, in: collection) != nil, "identifiers may hold any character")

        try expect(try await index.delete(id, from: collection), "delete reports an existing document")
        try expect(try await index.document(id, in: collection) == nil, "a deleted document is gone")
        try expect(!(try await index.delete(id, from: collection)), "delete reports a missing document")
    }

    /// Optimistic concurrency of `replace`.
    static func versions(_ index: DICOMArchiveIndex) async throws {
        let collection = DICOMArchiveCollection.performedProcedureSteps
        let id = "step"
        try await expectError(.notFound(id)) {
            try await index.replace(DICOMArchiveDocument(id: id, attributes: [:], version: 1), in: collection)
        }
        try await index.insert(DICOMArchiveDocument(id: id, attributes: [:]), into: collection)
        var read = try await index.document(id, in: collection)!
        read.metadata = ["state": "A"]
        let next = try await index.replace(read, in: collection)
        try expect(next == read.version + 1, "replace returns the next version")
        try expect(try await index.document(id, in: collection)?.version == next, "replace stores the next version")
        read.metadata = ["state": "B"]
        try await expectError(.conflict(id)) { try await index.replace(read, in: collection) }
        try expect(try await index.document(id, in: collection)?.metadata["state"] == "A",
                   "a conflicting replacement changes nothing")
    }

    /// Collections do not share identifiers.
    static func collections(_ index: DICOMArchiveIndex) async throws {
        let document = DICOMArchiveDocument(id: "same", attributes: [:])
        try await index.insert(document, into: .worklist)
        try await index.insert(document, into: .unifiedProcedureSteps)
        try expect(try await index.delete("same", from: .worklist), "a document is deleted from its collection")
        try expect(try await index.document("same", in: .unifiedProcedureSteps) != nil,
                   "a deletion leaves other collections alone")
        let other = try await index.documents(in: .worklist, matching: DICOMQuery(conditions: []))
        try expect(other.isEmpty, "an emptied collection has no documents")
    }

    // MARK: Queries

    /// Worklist items covering every kind of condition.
    static let items: [[String: Any]] = [
        item("DOE^JANE", "P1", "CT1", "CT", "20240706", "080000", physician: "SMITH^ANN", accession: "A1"),
        item("DOE^JOHN", "P2", "CT1", "CT", "20240705", "113000", physician: "SMITH^ANN", accession: "A2"),
        item("ROE^RICHARD", "P3", "MR1", "MR", "20240707", "190000", physician: "JONES^BOB", accession: "A3"),
        item("Müller^Hans=ミュラー^ハンス", "P4", "MR1", "MR", "20240707", "170000", physician: "", accession: "A4"),
        item("MOE^ANNA", "P5", "US1", "US", "2024.07.08", "09:30:00", physician: "", accession: ""),
        item("NOE^PAT", "P6", "CT2", "CT\\PT", "20240704", "235959.5", physician: "SMITH^ANN", accession: "A6",
             weight: "70.0"),
    ]

    static func item(
        _ name: String, _ id: String, _ station: String, _ modality: String, _ date: String, _ time: String,
        physician: String, accession: String, weight: String = ""
    ) -> [String: Any] {
        [
            "00080005": attribute("CS", ["ISO_IR 192"]),
            "00080050": attribute("SH", accession.isEmpty ? [] : [accession]),
            "00100010": attribute("PN", [name.split(separator: "=").count > 1
                ? ["Alphabetic": String(name.split(separator: "=")[0]), "Ideographic": String(name.split(separator: "=")[1])]
                : ["Alphabetic": name]]),
            "00100020": attribute("LO", [id]),
            "00101030": attribute("DS", weight.isEmpty ? [] : [weight]),
            "0020000D": attribute("UI", ["1.2.826.0.1.3680043.2.1125.\(id.dropFirst())"]),
            "00400100": attribute("SQ", [[
                "00080060": attribute("CS", modality.split(separator: "\\").map(String.init)),
                "00400001": attribute("AE", [station]),
                "00400002": attribute("DA", [date]),
                "00400003": attribute("TM", [time]),
                "00400006": attribute("PN", physician.isEmpty ? [] : [["Alphabetic": physician]]),
                "00400009": attribute("SH", ["SPS\(id)"]),
            ]]),
        ]
    }

    static func step(_ keys: [String: [String: Any]]) -> [String: Any] {
        ["00400100": attribute("SQ", [keys])]
    }

    /// Identifiers and the items they match, by Patient ID.
    static let cases: [(String, [String: Any], [String])] = [
        ("all", [:], ["P1", "P2", "P3", "P4", "P5", "P6"]),
        ("patient id", ["00100020": attribute("LO", ["P3"])], ["P3"]),
        ("UID list", ["0020000D": attribute("UI", ["1.2.826.0.1.3680043.2.1125.1", "1.2.826.0.1.3680043.2.1125.4"])],
         ["P1", "P4"]),
        ("name wild card, case and accents", ["00100010": attribute("PN", [["Alphabetic": "muller*"]])], ["P4"]),
        ("ideographic group", ["00100010": attribute("PN", [["Alphabetic": "ミュラー*"]])], ["P4"]),
        ("name single character", ["00100010": attribute("PN", [["Alphabetic": "?OE^JANE"]])], ["P1"]),
        ("multi-valued modality", step(["00080060": attribute("CS", ["PT"])]), ["P6"]),
        ("station wild card", step(["00400001": attribute("AE", ["CT*"])]), ["P1", "P2", "P6"]),
        ("station case", step(["00400001": attribute("AE", ["ct1"])]), []),
        ("date single, retired form stored", step(["00400002": attribute("DA", ["20240708"])]), ["P5"]),
        ("date range", step(["00400002": attribute("DA", ["20240705-20240707"])]), ["P1", "P2", "P3", "P4"]),
        ("date open low", step(["00400002": attribute("DA", ["-20240705"])]), ["P2", "P6"]),
        ("time precision", step(["00400003": attribute("TM", ["2359"])]), ["P6"]),
        ("time range", step(["00400003": attribute("TM", ["0800-1200"])]), ["P1", "P2", "P5"]),
        ("combined date and time", step([
            "00400002": attribute("DA", ["20240705-20240707"]), "00400003": attribute("TM", ["1000-1800"]),
        ]), ["P1", "P2", "P4"]),
        ("unknown value", ["00080050": attribute("SH", ["A*"])], ["P1", "P2", "P3", "P4", "P6"]),
        ("physician unknown", step(["00400006": attribute("PN", [["Alphabetic": "*"]])]),
         ["P1", "P2", "P3", "P4", "P5", "P6"]),
        ("number", ["00101030": attribute("DS", ["70"])], ["P6"]),
        ("same Item", step([
            "00080060": attribute("CS", ["CT"]), "00400001": attribute("AE", ["CT2"]),
        ]), ["P6"]),
    ]

    /// `documents(in:matching:)` returns at least every matching document.
    static func queries(_ index: DICOMArchiveIndex) async throws {
        for (offset, item) in items.enumerated() {
            try await index.insert(DICOMArchiveDocument(id: "item\(offset)", attributes: item), into: .worklist)
        }
        let matcher = DICOMQueryMatcher.modalityWorklist
        for (name, identifier, expected) in cases {
            let candidates = try await index.documents(
                in: .worklist, matching: DICOMQuery(identifier: identifier, matcher: matcher))
            let found = candidates.compactMap { document -> String? in
                guard matcher.match(identifier, against: document.attributes) != nil else { return nil }
                return ((document.attributes["00100020"] as? [String: Any])?["Value"] as? [Any])?.first as? String
            }.sorted()
            try expect(found == expected, "query \"\(name)\" found \(found), expected \(expected)")
        }
    }
}
