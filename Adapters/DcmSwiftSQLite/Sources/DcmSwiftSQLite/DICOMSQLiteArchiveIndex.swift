import CSQLite
import DcmSwift
import Foundation

private final class SQLiteConnection: @unchecked Sendable {
    let handle: OpaquePointer
    init(_ handle: OpaquePointer) { self.handle = handle }
    deinit { sqlite3_close(handle) }
}

/// A standalone SQLite archive index. It keeps one JSON document per
/// collection/identifier and indexes top-level UI values for safe C-FIND
/// candidate pruning. Other conditions are left to DcmSwift's exact matcher.
///
/// The schema is created on open. A SQLite transaction makes each mutation
/// atomic across processes; `replace` compares the stored document version.
public actor DICOMSQLiteArchiveIndex: DICOMArchiveIndex {
    public let path: String
    private let connection: SQLiteConnection

    public init(path: String) throws {
        self.path = path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open SQLite"
            if let handle { sqlite3_close(handle) }
            throw SQLiteArchiveError(message)
        }
        sqlite3_busy_timeout(handle, 5_000)
        do {
            try Self.execute(handle, "PRAGMA foreign_keys = ON")
            try Self.execute(handle, "CREATE TABLE IF NOT EXISTS archive_documents (collection TEXT NOT NULL, id TEXT NOT NULL, version INTEGER NOT NULL, attributes BLOB NOT NULL, metadata BLOB NOT NULL, PRIMARY KEY (collection,id))")
            try Self.execute(handle, "CREATE TABLE IF NOT EXISTS archive_uids (collection TEXT NOT NULL, id TEXT NOT NULL, tag TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY (collection,id,tag,value), FOREIGN KEY (collection,id) REFERENCES archive_documents(collection,id) ON DELETE CASCADE)")
            try Self.execute(handle, "CREATE INDEX IF NOT EXISTS archive_uids_find ON archive_uids(collection,tag,value,id)")
        } catch {
            sqlite3_close(handle)
            throw error
        }
        connection = SQLiteConnection(handle)
    }

    private var db: OpaquePointer { connection.handle }

    private static func execute(_ db: OpaquePointer, _ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(message)
            throw SQLiteArchiveError(detail)
        }
    }

    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try Self.execute(db, "BEGIN IMMEDIATE")
        do {
            let result = try body()
            try Self.execute(db, "COMMIT")
            return result
        } catch {
            try? Self.execute(db, "ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteArchiveError(String(cString: sqlite3_errmsg(db)))
        }
        return statement
    }

    private func bind(_ text: String, to statement: OpaquePointer, at position: Int32) throws {
        let result = text.withCString { sqlite3_bind_text(statement, position, $0, -1,
                                                           unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        guard result == SQLITE_OK else { throw SQLiteArchiveError(String(cString: sqlite3_errmsg(db))) }
    }

    private func bind(_ data: Data, to statement: OpaquePointer, at position: Int32) throws {
        let result = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, position, bytes.baseAddress, Int32(bytes.count),
                              unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard result == SQLITE_OK else { throw SQLiteArchiveError(String(cString: sqlite3_errmsg(db))) }
    }

    private func step(_ statement: OpaquePointer) throws -> Int32 {
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW || result == SQLITE_DONE else {
            throw SQLiteArchiveError(String(cString: sqlite3_errmsg(db)))
        }
        return result
    }

    private func encode(_ document: DICOMArchiveDocument) throws -> (Data, Data) {
        (try JSONSerialization.data(withJSONObject: document.attributes, options: [.sortedKeys]),
         try JSONSerialization.data(withJSONObject: document.metadata, options: [.sortedKeys]))
    }

    private func decode(_ statement: OpaquePointer) throws -> DICOMArchiveDocument {
        guard let idText = sqlite3_column_text(statement, 0),
              let attrBytes = sqlite3_column_blob(statement, 2),
              let metaBytes = sqlite3_column_blob(statement, 3) else {
            throw SQLiteArchiveError("corrupt archive row")
        }
        let attributesData = Data(bytes: attrBytes, count: Int(sqlite3_column_bytes(statement, 2)))
        let metadataData = Data(bytes: metaBytes, count: Int(sqlite3_column_bytes(statement, 3)))
        guard let attributes = try JSONSerialization.jsonObject(with: attributesData) as? [String: Any],
              let metadata = try JSONSerialization.jsonObject(with: metadataData) as? [String: String] else {
            throw SQLiteArchiveError("corrupt archive JSON")
        }
        return DICOMArchiveDocument(id: String(cString: idText), attributes: attributes, metadata: metadata,
                                    version: Int(sqlite3_column_int64(statement, 1)))
    }

    private func writeUIDs(_ document: DICOMArchiveDocument, collection: DICOMArchiveCollection) throws {
        let remove = try prepare("DELETE FROM archive_uids WHERE collection=? AND id=?")
        defer { sqlite3_finalize(remove) }
        try bind(collection.rawValue, to: remove, at: 1)
        try bind(document.id, to: remove, at: 2)
        _ = try step(remove)
        let insert = try prepare("INSERT INTO archive_uids(collection,id,tag,value) VALUES(?,?,?,?)")
        defer { sqlite3_finalize(insert) }
        for (tag, raw) in document.attributes.sorted(by: { $0.key < $1.key }) {
            guard let item = raw as? [String: Any], item["vr"] as? String == "UI",
                  let values = item["Value"] as? [String] else { continue }
            for value in Set(values) where !value.isEmpty {
                sqlite3_reset(insert)
                sqlite3_clear_bindings(insert)
                try bind(collection.rawValue, to: insert, at: 1)
                try bind(document.id, to: insert, at: 2)
                try bind(tag, to: insert, at: 3)
                try bind(value, to: insert, at: 4)
                _ = try step(insert)
            }
        }
    }

    public func insert(_ document: DICOMArchiveDocument, into collection: DICOMArchiveCollection) throws {
        try transaction {
            let (attributes, metadata) = try encode(document)
            let statement = try prepare("INSERT OR IGNORE INTO archive_documents(collection,id,version,attributes,metadata) VALUES(?,?,1,?,?)")
            defer { sqlite3_finalize(statement) }
            try bind(collection.rawValue, to: statement, at: 1)
            try bind(document.id, to: statement, at: 2)
            try bind(attributes, to: statement, at: 3)
            try bind(metadata, to: statement, at: 4)
            _ = try step(statement)
            guard sqlite3_changes(db) == 1 else { throw DICOMArchiveError.duplicate(document.id) }
            try writeUIDs(document, collection: collection)
        }
    }

    public func save(_ document: DICOMArchiveDocument, in collection: DICOMArchiveCollection) throws {
        try transaction {
            let (attributes, metadata) = try encode(document)
            let statement = try prepare("INSERT INTO archive_documents(collection,id,version,attributes,metadata) VALUES(?,?,1,?,?) ON CONFLICT(collection,id) DO UPDATE SET version=version+1, attributes=excluded.attributes, metadata=excluded.metadata")
            defer { sqlite3_finalize(statement) }
            try bind(collection.rawValue, to: statement, at: 1)
            try bind(document.id, to: statement, at: 2)
            try bind(attributes, to: statement, at: 3)
            try bind(metadata, to: statement, at: 4)
            _ = try step(statement)
            try writeUIDs(document, collection: collection)
        }
    }

    @discardableResult
    public func replace(_ document: DICOMArchiveDocument, in collection: DICOMArchiveCollection) throws -> Int {
        try transaction {
            let (attributes, metadata) = try encode(document)
            let statement = try prepare("UPDATE archive_documents SET version=version+1, attributes=?, metadata=? WHERE collection=? AND id=? AND version=?")
            defer { sqlite3_finalize(statement) }
            try bind(attributes, to: statement, at: 1)
            try bind(metadata, to: statement, at: 2)
            try bind(collection.rawValue, to: statement, at: 3)
            try bind(document.id, to: statement, at: 4)
            sqlite3_bind_int64(statement, 5, Int64(document.version))
            _ = try step(statement)
            guard sqlite3_changes(db) == 1 else {
                if try self.document(document.id, in: collection) == nil { throw DICOMArchiveError.notFound(document.id) }
                throw DICOMArchiveError.conflict(document.id)
            }
            try writeUIDs(document, collection: collection)
            return document.version + 1
        }
    }

    public func document(_ id: String, in collection: DICOMArchiveCollection) throws -> DICOMArchiveDocument? {
        let statement = try prepare("SELECT id,version,attributes,metadata FROM archive_documents WHERE collection=? AND id=?")
        defer { sqlite3_finalize(statement) }
        try bind(collection.rawValue, to: statement, at: 1)
        try bind(id, to: statement, at: 2)
        return try step(statement) == SQLITE_ROW ? try decode(statement) : nil
    }

    @discardableResult
    public func delete(_ id: String, from collection: DICOMArchiveCollection) throws -> Bool {
        let statement = try prepare("DELETE FROM archive_documents WHERE collection=? AND id=?")
        defer { sqlite3_finalize(statement) }
        try bind(collection.rawValue, to: statement, at: 1)
        try bind(id, to: statement, at: 2)
        _ = try step(statement)
        return sqlite3_changes(db) == 1
    }

    public func documents(in collection: DICOMArchiveCollection,
                          matching query: DICOMQuery) throws -> [DICOMArchiveDocument] {
        var sql = "SELECT d.id,d.version,d.attributes,d.metadata FROM archive_documents d WHERE d.collection=?"
        var constraints: [(String, [String])] = []
        for condition in query.conditions where condition.path.count == 1 && condition.vr == "UI" {
            if case .equals(let values) = condition.constraint, !values.isEmpty {
                sql += " AND EXISTS (SELECT 1 FROM archive_uids u WHERE u.collection=d.collection AND u.id=d.id AND u.tag=? AND u.value IN ("
                    + Array(repeating: "?", count: values.count).joined(separator: ",") + "))"
                constraints.append((condition.path[0], values))
            }
        }
        sql += " ORDER BY d.id"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(collection.rawValue, to: statement, at: 1)
        var position: Int32 = 2
        for (tag, values) in constraints {
            try bind(tag, to: statement, at: position)
            position += 1
            for value in values { try bind(value, to: statement, at: position); position += 1 }
        }
        var found: [DICOMArchiveDocument] = []
        while try step(statement) == SQLITE_ROW { found.append(try decode(statement)) }
        return found
    }
}

public struct SQLiteArchiveError: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ description: String) { self.description = description }
}
