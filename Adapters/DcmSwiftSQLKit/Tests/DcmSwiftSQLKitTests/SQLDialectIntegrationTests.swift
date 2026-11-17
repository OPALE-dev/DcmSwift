import DcmSwift
import DcmSwiftArchiveConformance
import DcmSwiftSQLKit
import Foundation
import Logging
import MySQLKit
import NIOCore
import NIOPosix
import PostgresKit
import SQLKit
import XCTest

final class SQLDialectIntegrationTests: XCTestCase {
    private let logger = Logger(label: "dcmswift-sqlkit-integration")

    func testPostgreSQL() async throws {
        guard let url = ProcessInfo.processInfo.environment["DCMSWIFT_SQLKIT_POSTGRES_URL"] else {
            throw XCTSkip("Set DCMSWIFT_SQLKIT_POSTGRES_URL to run PostgreSQL integration")
        }
        let config = try SQLPostgresConfiguration(url: url)
        let source = PostgresConnectionSource(sqlConfiguration: config)
        let connection = try await source.makeConnection(
            logger: logger, on: MultiThreadedEventLoopGroup.singleton.any()).get()
        defer { let _: EventLoopFuture<Void> = connection.close() }
        let second = try await source.makeConnection(
            logger: logger, on: MultiThreadedEventLoopGroup.singleton.any()).get()
        defer { let _: EventLoopFuture<Void> = second.close() }
        do {
            try await checkDialect(connection.sql())
            try await checkCrossConnection(connection.sql(), second.sql())
        }
        catch { XCTFail(String(reflecting: error)); throw error }
    }

    func testMySQL() async throws {
        guard let url = ProcessInfo.processInfo.environment["DCMSWIFT_SQLKIT_MYSQL_URL"] else {
            throw XCTSkip("Set DCMSWIFT_SQLKIT_MYSQL_URL to run MySQL integration")
        }
        let config = try XCTUnwrap(MySQLConfiguration(url: url))
        let source = MySQLConnectionSource(configuration: config)
        let connection = try await source.makeConnection(
            logger: logger, on: MultiThreadedEventLoopGroup.singleton.any()).get()
        defer { _ = connection.close() }
        let second = try await source.makeConnection(
            logger: logger, on: MultiThreadedEventLoopGroup.singleton.any()).get()
        defer { _ = second.close() }
        do {
            try await checkDialect(connection.sql())
            try await checkCrossConnection(connection.sql(), second.sql())
        }
        catch { XCTFail(String(reflecting: error)); throw error }
    }

    private func checkDialect(_ db: any SQLDatabase) async throws {
        try await DICOMArchiveConformance.check {
            try await db.raw("DROP TABLE IF EXISTS dcmswift_archive_documents").run()
            try await db.raw("DROP TABLE IF EXISTS dcmswift_archive_schema").run()
            let index = DICOMSQLKitArchiveIndex(database: db)
            try await index.migrate()
            try await index.migrate()
            return index
        }
        try await db.raw("DROP TABLE IF EXISTS dcmswift_archive_documents").run()
        try await db.raw("DROP TABLE IF EXISTS dcmswift_archive_schema").run()
    }

    private func checkCrossConnection(_ firstDB: any SQLDatabase, _ secondDB: any SQLDatabase) async throws {
        let first = DICOMSQLKitArchiveIndex(database: firstDB)
        let second = DICOMSQLKitArchiveIndex(database: secondDB)
        try await first.migrate()
        // Simulate a deployment interrupted after indexes but before its marker.
        try await firstDB.delete(from: "dcmswift_archive_schema").run()
        try await first.migrate()
        let collection = DICOMArchiveCollection.unifiedProcedureSteps
        try await first.insert(DICOMArchiveDocument(id: "step", attributes: [:]), into: collection)
        let staleRead = try await second.document("step", in: collection)
        let stale = try XCTUnwrap(staleRead)
        _ = try await first.replace(stale, in: collection)
        do {
            _ = try await second.replace(stale, in: collection)
            XCTFail("a stale replacement succeeded across connections")
        } catch DICOMArchiveError.conflict(let id) {
            XCTAssertEqual(id, "step")
        }
        let deleted = try await second.delete("step", from: collection)
        let missing = try await first.delete("step", from: collection)
        XCTAssertTrue(deleted)
        XCTAssertFalse(missing)
        try await firstDB.raw("DROP TABLE IF EXISTS dcmswift_archive_documents").run()
        try await firstDB.raw("DROP TABLE IF EXISTS dcmswift_archive_schema").run()
    }
}
