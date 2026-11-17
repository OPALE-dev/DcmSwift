import DcmSwift
import DcmSwiftArchiveConformance
import DcmSwiftSQLite
import Foundation
import XCTest

final class DcmSwiftSQLiteTests: XCTestCase {
    func testArchiveConformance() async throws {
        try await DICOMArchiveConformance.check { try DICOMSQLiteArchiveIndex(path: ":memory:") }
    }

    func testPersistsAndDetectsCrossConnectionConflicts() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("dcmswift-sqlite-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try DICOMSQLiteArchiveIndex(path: path)
        let second = try DICOMSQLiteArchiveIndex(path: path)
        let collection = DICOMArchiveCollection.unifiedProcedureSteps
        let original = DICOMArchiveDocument(id: "1.2.3", attributes: [
            "00080018": ["vr": "UI", "Value": ["1.2.3"]],
        ])
        try await first.insert(original, into: collection)
        let staleRead = try await second.document("1.2.3", in: collection)
        let stale = try XCTUnwrap(staleRead)
        let currentRead = try await first.document("1.2.3", in: collection)
        var current = try XCTUnwrap(currentRead)
        current.metadata["state"] = "IN PROGRESS"
        let version = try await first.replace(current, in: collection)
        XCTAssertEqual(version, 2)
        do {
            _ = try await second.replace(stale, in: collection)
            XCTFail("stale version was accepted")
        } catch DICOMArchiveError.conflict(let id) {
            XCTAssertEqual(id, "1.2.3")
        }
        let query = DICOMQuery(identifier: ["00080018": ["vr": "UI", "Value": ["1.2.3"]]])
        let matches = try await second.documents(in: collection, matching: query)
        XCTAssertEqual(matches.count, 1)
    }
}
