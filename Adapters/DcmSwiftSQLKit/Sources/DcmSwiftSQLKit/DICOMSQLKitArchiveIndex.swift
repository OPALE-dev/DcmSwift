import Crypto
import DcmSwift
import Foundation
import SQLKit

/// A database-backed archive index for an application's existing SQLKit database.
/// Call `migrate()` before serving requests. The adapter owns no connection pool.
public actor DICOMSQLKitArchiveIndex: DICOMArchiveIndex {
    private let database: any SQLDatabase
    private static let table = "dcmswift_archive_documents"
    private static let indexedUIDs = ["00080018", "0020000D", "0020000E"]

    public init(database: any SQLDatabase) { self.database = database }

    /// Idempotent version-one schema migration. Run once during application startup.
    public func migrate() async throws {
        // SQLKit's `.text` maps to VARCHAR(255) in MySQLKit, which truncates
        // ordinary DICOM JSON documents. Use a native large text type there.
        let largeText: SQLDataType = .custom(SQLRaw(database.dialect.name == "mysql" ? "LONGTEXT" : "TEXT"))
        try await database.create(table: Self.table).ifNotExists()
            .column("keyhash", type: .custom(SQLRaw("VARCHAR(64)")), .notNull)
            .column("collection", type: largeText, .notNull)
            .column("document_id", type: largeText, .notNull)
            .column("version", type: .bigint, .notNull)
            .column("attributes", type: largeText, .notNull)
            .column("metadata", type: largeText, .notNull)
            .column("mutation", type: .custom(SQLRaw("VARCHAR(36)")), .notNull)
            .column("uid_00080018", type: .custom(SQLRaw("VARCHAR(64)")))
            .column("uid_0020000D", type: .custom(SQLRaw("VARCHAR(64)")))
            .column("uid_0020000E", type: .custom(SQLRaw("VARCHAR(64)")))
            .primaryKey("keyhash")
            .run()
        // The primary key already indexes point reads. These additional indexes
        // are optional optimizations and are installed only by the first migration.
        try await database.create(table: "dcmswift_archive_schema").ifNotExists()
            .column("version", type: .int, .notNull).primaryKey("version").run()
        let existing = try await database.select().column("version")
            .from("dcmswift_archive_schema").first()
        if existing == nil {
            for tag in Self.indexedUIDs {
                let name = "dcmswift_archive_\(tag)"
                if try await indexExists(name) == false {
                    try await database.create(index: name)
                        .on(Self.table).column("uid_\(tag)").run()
                }
            }
            try await database.insert(into: "dcmswift_archive_schema")
                .columns("version").values(1).run()
        }
    }

    private func indexExists(_ name: String) async throws -> Bool {
        let query: SQLQueryString
        switch database.dialect.name {
        case "mysql":
            query = "SELECT 1 AS found FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name=\(bind: Self.table) AND index_name=\(bind: name) LIMIT 1"
        case "postgresql":
            query = "SELECT 1 AS found FROM pg_indexes WHERE schemaname=current_schema() AND tablename=\(bind: Self.table) AND indexname=\(bind: name) LIMIT 1"
        case "sqlite":
            query = "SELECT 1 AS found FROM sqlite_master WHERE type='index' AND name=\(bind: name) LIMIT 1"
        default:
            throw SQLKitArchiveError("unsupported SQL dialect: \(database.dialect.name)")
        }
        return try await database.raw(query).first() != nil
    }

    private static func key(_ id: String, _ collection: DICOMArchiveCollection) -> String {
        var input = Data()
        var collectionLength = UInt64(collection.rawValue.utf8.count).bigEndian
        withUnsafeBytes(of: &collectionLength) { input.append(contentsOf: $0) }
        input.append(contentsOf: collection.rawValue.utf8)
        input.append(contentsOf: id.utf8)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    private static func uid(_ document: DICOMArchiveDocument, tag: String) -> String? {
        guard let element = document.attributes[tag] as? [String: Any],
              element["vr"] as? String == "UI",
              let values = element["Value"] as? [String], values.count == 1,
              let value = values.first, value.utf8.count <= 64 else { return nil }
        return value
    }

    private static func json(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else { throw SQLKitArchiveError("invalid JSON encoding") }
        return text
    }

    private static func decode(_ row: any SQLRow) throws -> DICOMArchiveDocument {
        let id = try row.decode(column: "document_id", as: String.self)
        let version = try row.decode(column: "version", as: Int.self)
        let attributesText = try row.decode(column: "attributes", as: String.self)
        let metadataText = try row.decode(column: "metadata", as: String.self)
        guard let attributes = try JSONSerialization.jsonObject(with: Data(attributesText.utf8)) as? [String: Any],
              let metadata = try JSONSerialization.jsonObject(with: Data(metadataText.utf8)) as? [String: String]
        else { throw SQLKitArchiveError("corrupt archive JSON") }
        return DICOMArchiveDocument(id: id, attributes: attributes, metadata: metadata, version: version)
    }

    private static func insertQuery(_ document: DICOMArchiveDocument, collection: DICOMArchiveCollection,
                                    on db: any SQLDatabase) throws -> SQLInsertBuilder {
        let attributes = try json(document.attributes)
        let metadata = try json(document.metadata)
        return db.insert(into: table)
            .columns("keyhash", "collection", "document_id", "version", "attributes", "metadata", "mutation",
                     "uid_00080018", "uid_0020000D", "uid_0020000E")
            .values(SQLBind(key(document.id, collection)), SQLBind(collection.rawValue), SQLBind(document.id),
                    SQLBind(1), SQLBind(attributes), SQLBind(metadata), SQLBind(UUID().uuidString),
                    SQLBind(uid(document, tag: "00080018")), SQLBind(uid(document, tag: "0020000D")),
                    SQLBind(uid(document, tag: "0020000E")))
    }

    public func insert(_ document: DICOMArchiveDocument, into collection: DICOMArchiveCollection) async throws {
        do { try await Self.insertQuery(document, collection: collection, on: database).run() }
        catch {
            if try await self.document(document.id, in: collection) != nil {
                throw DICOMArchiveError.duplicate(document.id)
            }
            throw error
        }
    }

    public func save(_ document: DICOMArchiveDocument, in collection: DICOMArchiveCollection) async throws {
        try await Self.insertQuery(document, collection: collection, on: database)
            .onConflict(with: "keyhash") {
                $0.set("version", to: SQLBinaryExpression(
                    SQLColumn("version", table: Self.table), .add, SQLLiteral.numeric("1")))
                    .set(excludedValueOf: "attributes").set(excludedValueOf: "metadata")
                    .set(excludedValueOf: "mutation")
                    .set(excludedValueOf: "uid_00080018")
                    .set(excludedValueOf: "uid_0020000D")
                    .set(excludedValueOf: "uid_0020000E")
            }.run()
    }

    @discardableResult
    public func replace(_ document: DICOMArchiveDocument, in collection: DICOMArchiveCollection) async throws -> Int {
        let keyhash = Self.key(document.id, collection)
        let attributes = try Self.json(document.attributes)
        let metadata = try Self.json(document.metadata)
        let mutation = UUID().uuidString
        return try await database.withSession { db in
            let isMySQL = db.dialect.name == "mysql"
            if !isMySQL {
                let begin = db.dialect.name == "sqlite" ? "BEGIN IMMEDIATE" : "BEGIN"
                try await db.raw(SQLQueryString(begin)).run()
            }
            do {
                try await db.raw("""
                    UPDATE \(ident: Self.table) SET
                    \(ident: "version")=\(ident: "version")+1,
                    \(ident: "attributes")=\(bind: attributes), \(ident: "metadata")=\(bind: metadata),
                    \(ident: "mutation")=\(bind: mutation),
                    \(ident: "uid_00080018")=\(bind: Self.uid(document, tag: "00080018")),
                    \(ident: "uid_0020000D")=\(bind: Self.uid(document, tag: "0020000D")),
                    \(ident: "uid_0020000E")=\(bind: Self.uid(document, tag: "0020000E"))
                    WHERE \(ident: "keyhash")=\(bind: keyhash) AND \(ident: "version")=\(bind: document.version)
                    """).run()
                if isMySQL {
                    // MySQL does not allow BEGIN via the driver's prepared-query
                    // API. ROW_COUNT() is connection-local; withSession pins it.
                    let changed = try await db.raw("SELECT ROW_COUNT() AS changed")
                        .first(decodingColumn: "changed", as: Int.self)
                    if changed == 1 { return document.version + 1 }
                }
                let row = try await db.select().columns("document_id", "collection", "mutation")
                    .from(Self.table).where("keyhash", .equal, keyhash).first()
                guard let row else { throw DICOMArchiveError.notFound(document.id) }
                guard try row.decode(column: "document_id", as: String.self) == document.id,
                      try row.decode(column: "collection", as: String.self) == collection.rawValue
                else { throw SQLKitArchiveError("archive key collision") }
                if isMySQL { throw DICOMArchiveError.conflict(document.id) }
                guard try row.decode(column: "mutation", as: String.self) == mutation else {
                    throw DICOMArchiveError.conflict(document.id)
                }
                try await db.raw("COMMIT").run()
                return document.version + 1
            } catch {
                if !isMySQL { try? await db.raw("ROLLBACK").run() }
                throw error
            }
        }
    }

    public func document(_ id: String, in collection: DICOMArchiveCollection) async throws -> DICOMArchiveDocument? {
        guard let row = try await database.select().columns("collection", "document_id", "version", "attributes", "metadata")
            .from(Self.table).where("keyhash", .equal, Self.key(id, collection)).first() else { return nil }
        guard try row.decode(column: "collection", as: String.self) == collection.rawValue,
              try row.decode(column: "document_id", as: String.self) == id else {
            throw SQLKitArchiveError("archive key collision")
        }
        return try Self.decode(row)
    }

    @discardableResult
    public func delete(_ id: String, from collection: DICOMArchiveCollection) async throws -> Bool {
        let keyhash = Self.key(id, collection)
        if database.dialect.supportsReturning {
            guard let row = try await database.delete(from: Self.table)
                .where("keyhash", .equal, keyhash)
                .returning("document_id", "collection").first() else { return false }
            guard try row.decode(column: "document_id", as: String.self) == id,
                  try row.decode(column: "collection", as: String.self) == collection.rawValue
            else { throw SQLKitArchiveError("archive key collision") }
            return true
        }
        // MySQL has no DELETE RETURNING. ROW_COUNT() is read on the same
        // connection immediately after the single atomic DELETE statement.
        return try await database.withSession { db in
            try await db.delete(from: Self.table).where("keyhash", .equal, keyhash).run()
            let count = try await db.raw("SELECT ROW_COUNT() AS changed")
                .first(decodingColumn: "changed", as: Int.self)
            return count == 1
        }
    }

    public func documents(in collection: DICOMArchiveCollection,
                          matching query: DICOMQuery) async throws -> [DICOMArchiveDocument] {
        let select = database.select().columns("collection", "document_id", "version", "attributes", "metadata")
            .from(Self.table).where("collection", .equal, collection.rawValue)
        for condition in query.conditions where condition.path.count == 1 && condition.vr == "UI" {
            guard Self.indexedUIDs.contains(condition.path[0]), case .equals(let values) = condition.constraint,
                  !values.isEmpty else { continue }
            // NULL means a multi-valued or unindexable UID; it remains a candidate.
            let column = "uid_\(condition.path[0])"
            select.where(SQLGroupExpression(SQLList([
                SQLBinaryExpression(left: SQLColumn(column), op: SQLRaw("IS"), right: SQLLiteral.null),
                SQLBinaryExpression(left: SQLColumn(column), op: SQLRaw("IN"),
                                    right: SQLGroupExpression(values.map { SQLBind($0) })),
            ], separator: SQLRaw(" OR "))))
        }
        let rows = try await select.orderBy("document_id").all()
        return try rows.compactMap { row in
            guard try row.decode(column: "collection", as: String.self) == collection.rawValue else { return nil }
            return try Self.decode(row)
        }
    }
}

public struct SQLKitArchiveError: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ description: String) { self.description = description }
}
