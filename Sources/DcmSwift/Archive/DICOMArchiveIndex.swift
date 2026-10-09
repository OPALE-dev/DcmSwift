import Foundation

/// A named set of documents in an archive index.
public struct DICOMArchiveCollection: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    /// Composite instances: their indexed attributes, and their location
    /// in the instance store.
    public static let instances = DICOMArchiveCollection(rawValue: "instances")
    /// Modality Worklist items (PS3.4 K.6).
    public static let worklist = DICOMArchiveCollection(rawValue: "worklist")
    /// Modality Performed Procedure Steps (PS3.4 F.7).
    public static let performedProcedureSteps = DICOMArchiveCollection(rawValue: "performedProcedureSteps")
    /// Instance Availability Notifications received (PS3.4 R).
    public static let instanceAvailability = DICOMArchiveCollection(rawValue: "instanceAvailability")
    /// Application events logged (PS3.4 P).
    public static let eventLog = DICOMArchiveCollection(rawValue: "eventLog")
    /// Storage Commitment results waiting for delivery (PS3.4 J).
    public static let storageCommitmentResults = DICOMArchiveCollection(rawValue: "storageCommitmentResults")
    /// Unified Procedure Steps (PS3.4 CC).
    public static let unifiedProcedureSteps = DICOMArchiveCollection(rawValue: "unifiedProcedureSteps")

    public var description: String { rawValue }
}

/// A document of an archive index: DICOM attributes in the DICOM JSON
/// Model (PS3.18 F, IS and DS Values as strings), and metadata the
/// services keep beside them.
public struct DICOMArchiveDocument: @unchecked Sendable {
    /// Unique in its collection, such as a SOP Instance UID.
    public var id: String
    /// Attributes in the DICOM JSON Model, keyed by 8 upper-case
    /// hexadecimal digits.
    public var attributes: [String: Any]
    /// Service data, such as an instance's location and transfer syntax.
    public var metadata: [String: String]
    /// Incremented by the index at each replacement, for optimistic
    /// concurrency; 0 before the first insertion.
    public var version: Int

    public init(id: String, attributes: [String: Any], metadata: [String: String] = [:], version: Int = 0) {
        self.id = id
        self.attributes = attributes
        self.metadata = metadata
        self.version = version
    }

    /// A document from a data set.
    public init(id: String, dataSet: DataSet, metadata: [String: String] = [:]) throws {
        self.init(id: id, attributes: try DICOMJSON.object(
            dataSet, options: DICOMJSON.EncodingOptions(numbersAsStrings: true)), metadata: metadata)
    }

    /// The attributes as a data set.
    public func dataSet() throws -> DataSet {
        try DICOMJSON.dataSet(attributes)
    }
}

public enum DICOMArchiveError: Error, Equatable, Sendable {
    /// A document with this identifier already exists.
    case duplicate(String)
    /// The document changed since it was read (its version differs).
    case conflict(String)
    /// No document has this identifier.
    case notFound(String)
}

/// Where an archive keeps its documents: the protocol a database adapter
/// implements. DcmSwift provides `DICOMMemoryArchiveIndex` and
/// `DICOMFileArchiveIndex`; adapters for databases live in their own
/// packages and pass `DICOMArchiveConformance`.
///
/// Implementations must be safe to call concurrently. Each method acts on
/// one document atomically; `replace` fails with `conflict` when the stored
/// version is not the one the caller read, which lets several processes
/// share an index.
public protocol DICOMArchiveIndex: Sendable {
    /// Adds a document with version 1; throws `duplicate` if its
    /// identifier exists.
    func insert(_ document: DICOMArchiveDocument, into collection: DICOMArchiveCollection) async throws

    /// Adds or replaces a document whatever its version.
    func save(_ document: DICOMArchiveDocument, in collection: DICOMArchiveCollection) async throws

    /// Replaces a document whose stored version is `document.version`, and
    /// stores it with the next version, which is returned; throws
    /// `notFound` or `conflict`.
    @discardableResult
    func replace(_ document: DICOMArchiveDocument, in collection: DICOMArchiveCollection) async throws -> Int

    /// The document with this identifier.
    func document(_ id: String, in collection: DICOMArchiveCollection) async throws -> DICOMArchiveDocument?

    /// Removes a document; returns whether it existed.
    @discardableResult
    func delete(_ id: String, from collection: DICOMArchiveCollection) async throws -> Bool

    /// Every document that may match `query`: at least all those that do,
    /// in a stable order. Conditions that cannot be translated may be
    /// ignored; the caller filters the documents.
    func documents(in collection: DICOMArchiveCollection, matching query: DICOMQuery) async throws -> [DICOMArchiveDocument]
}

/// An index in memory. It ignores query conditions: the services filter
/// every document of the collection.
public actor DICOMMemoryArchiveIndex: DICOMArchiveIndex {
    private var collections: [DICOMArchiveCollection: [String: DICOMArchiveDocument]] = [:]

    public init() {}

    public func insert(_ document: DICOMArchiveDocument, into collection: DICOMArchiveCollection) throws {
        guard collections[collection]?[document.id] == nil else { throw DICOMArchiveError.duplicate(document.id) }
        var stored = document
        stored.version = 1
        collections[collection, default: [:]][document.id] = stored
    }

    public func save(_ document: DICOMArchiveDocument, in collection: DICOMArchiveCollection) {
        var stored = document
        stored.version = (collections[collection]?[document.id]?.version ?? 0) + 1
        collections[collection, default: [:]][document.id] = stored
    }

    public func replace(_ document: DICOMArchiveDocument, in collection: DICOMArchiveCollection) throws -> Int {
        guard let current = collections[collection]?[document.id] else { throw DICOMArchiveError.notFound(document.id) }
        guard current.version == document.version else { throw DICOMArchiveError.conflict(document.id) }
        var stored = document
        stored.version += 1
        collections[collection]![document.id] = stored
        return stored.version
    }

    /// Stores a document as it is, version included.
    func restore(_ document: DICOMArchiveDocument, in collection: DICOMArchiveCollection) {
        collections[collection, default: [:]][document.id] = document
    }

    public func document(_ id: String, in collection: DICOMArchiveCollection) -> DICOMArchiveDocument? {
        collections[collection]?[id]
    }

    public func delete(_ id: String, from collection: DICOMArchiveCollection) -> Bool {
        collections[collection]?.removeValue(forKey: id) != nil
    }

    public func documents(in collection: DICOMArchiveCollection, matching query: DICOMQuery) -> [DICOMArchiveDocument] {
        (collections[collection] ?? [:]).values.sorted { $0.id < $1.id }
    }
}

/// An index kept as files: one directory per collection, one JSON file per
/// document (`{"id", "version", "metadata", "attributes"}`), written
/// atomically and read once at start-up. It suits a single process.
public actor DICOMFileArchiveIndex: DICOMArchiveIndex {
    public nonisolated let directory: URL
    private let memory = DICOMMemoryArchiveIndex()
    private var loaded: Set<DICOMArchiveCollection> = []

    public init(directory: URL) {
        self.directory = directory
    }

    private func folder(_ collection: DICOMArchiveCollection) -> URL {
        directory.appendingPathComponent(collection.rawValue, isDirectory: true)
    }

    /// The file of a document; identifiers are percent-encoded.
    private func file(_ id: String, _ collection: DICOMArchiveCollection) -> URL {
        let name = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ".-_")))
            ?? id
        return folder(collection).appendingPathComponent(name + ".json")
    }

    private func load(_ collection: DICOMArchiveCollection) async throws {
        guard !loaded.contains(collection) else { return }
        loaded.insert(collection)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder(collection), includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "json" {
            guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
                  let id = object["id"] as? String else { continue }
            let document = DICOMArchiveDocument(
                id: id, attributes: object["attributes"] as? [String: Any] ?? [:],
                metadata: object["metadata"] as? [String: String] ?? [:], version: object["version"] as? Int ?? 1)
            await memory.restore(document, in: collection)
        }
    }

    private func write(_ id: String, _ collection: DICOMArchiveCollection) async throws {
        guard let document = await memory.document(id, in: collection) else { return }
        try FileManager.default.createDirectory(at: folder(collection), withIntermediateDirectories: true)
        let object: [String: Any] = ["id": document.id, "version": document.version, "metadata": document.metadata,
                                     "attributes": document.attributes]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: file(id, collection), options: .atomic)
    }

    public func insert(_ document: DICOMArchiveDocument, into collection: DICOMArchiveCollection) async throws {
        try await load(collection)
        try await memory.insert(document, into: collection)
        try await write(document.id, collection)
    }

    public func save(_ document: DICOMArchiveDocument, in collection: DICOMArchiveCollection) async throws {
        try await load(collection)
        await memory.save(document, in: collection)
        try await write(document.id, collection)
    }

    public func replace(_ document: DICOMArchiveDocument, in collection: DICOMArchiveCollection) async throws -> Int {
        try await load(collection)
        let version = try await memory.replace(document, in: collection)
        try await write(document.id, collection)
        return version
    }

    public func document(_ id: String, in collection: DICOMArchiveCollection) async throws -> DICOMArchiveDocument? {
        try await load(collection)
        return await memory.document(id, in: collection)
    }

    public func delete(_ id: String, from collection: DICOMArchiveCollection) async throws -> Bool {
        try await load(collection)
        guard await memory.delete(id, from: collection) else { return false }
        try? FileManager.default.removeItem(at: file(id, collection))
        return true
    }

    public func documents(
        in collection: DICOMArchiveCollection, matching query: DICOMQuery
    ) async throws -> [DICOMArchiveDocument] {
        try await load(collection)
        return await memory.documents(in: collection, matching: query)
    }
}
