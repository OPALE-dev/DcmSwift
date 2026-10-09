import DcmSwift
import DcmSwiftArchiveConformance
import DcmSwiftSQLKit
import Logging
import NIOPosix
import SQLiteKit
import XCTest

final class DcmSwiftSQLKitTests: XCTestCase {
    private func connection() async throws -> SQLiteConnection {
        try await SQLiteConnectionSource(
            configuration: .init(storage: .memory, enableForeignKeys: true),
            threadPool: .singleton
        ).makeConnection(logger: Logger(label: "dcmswift-sqlkit-tests"),
                         on: MultiThreadedEventLoopGroup.singleton.any()).get()
    }

    func testConformanceAndIdempotentMigration() async throws {
        var connections: [SQLiteConnection] = []
        defer { for connection in connections { _ = connection.close() } }
        try await DICOMArchiveConformance.check {
            let db = try await connection()
            connections.append(db)
            let index = DICOMSQLKitArchiveIndex(database: db.sql())
            try await index.migrate()
            try await index.migrate()
            return index
        }
    }

    func testCrossAdapterConflictAndUIDPruning() async throws {
        let db = try await connection()
        defer { _ = db.close() }
        let first = DICOMSQLKitArchiveIndex(database: db.sql())
        let second = DICOMSQLKitArchiveIndex(database: db.sql())
        try await first.migrate()
        let collection = DICOMArchiveCollection.instances
        let original = DICOMArchiveDocument(id: "instance", attributes: [
            "0020000D": ["vr": "UI", "Value": ["1.2.3"]],
        ])
        try await first.insert(original, into: collection)
        try await first.save(original, in: collection)
        let saved = try await first.document("instance", in: collection)
        XCTAssertEqual(saved?.version, 2)
        let staleRead = try await second.document("instance", in: collection)
        let stale = try XCTUnwrap(staleRead)
        _ = try await first.replace(stale, in: collection)
        do {
            _ = try await second.replace(stale, in: collection)
            XCTFail("stale replacement succeeded")
        } catch DICOMArchiveError.conflict(let id) {
            XCTAssertEqual(id, "instance")
        }
        let query = DICOMQuery(identifier: ["0020000D": ["vr": "UI", "Value": ["1.2.3"]]])
        let hits = try await second.documents(in: collection, matching: query)
        XCTAssertEqual(hits.count, 1)
        let miss = DICOMQuery(identifier: ["0020000D": ["vr": "UI", "Value": ["9.9.9"]]])
        let misses = try await second.documents(in: collection, matching: miss)
        XCTAssertEqual(misses.count, 0)

        let multiple = DICOMArchiveDocument(id: "multiple", attributes: [
            "0020000D": ["vr": "UI", "Value": ["2.3.4", "1.2.3"]],
        ])
        try await first.insert(multiple, into: collection)
        let candidates = try await second.documents(in: collection, matching: query)
        XCTAssertEqual(Set(candidates.map(\.id)), ["instance", "multiple"])
    }
}
