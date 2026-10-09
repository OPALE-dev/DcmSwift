import Foundation

/// A Modality Worklist SCP (PS3.4 K.6): the worklist items it holds answer
/// C-FIND on the Modality Worklist Information Model.
///
/// Each item is a data set with the attributes of one Scheduled Procedure
/// Step and of the Requested Procedure, Imaging Service Request, Visit, and
/// Patient it belongs to (PS3.4 Table K.6-1). Items come from `add(_:)` or,
/// with a directory, from the files found there at each query: Part 10
/// files, data sets without File Meta Information (such as DCMTK `.wl`
/// files), and DICOM JSON files (`.json`), searched recursively.
///
/// Every attribute of an item can be matched, with the rules of
/// `DICOMQueryMatcher.modalityWorklist`; there are no unsupported optional
/// keys, so every match is answered with status FF00.
public actor DICOMModalityWorklist: DICOMQueryService {
    /// A directory read at each query, or nil.
    public nonisolated let directory: URL?
    private var items: [String: DataSet] = [:]
    private let matcher: DICOMQueryMatcher

    public init(directory: URL? = nil, matcher: DICOMQueryMatcher = .modalityWorklist) {
        self.directory = directory
        self.matcher = matcher
    }

    /// Adds or replaces an item; returns its identifier for `remove(_:)`.
    @discardableResult
    public func add(_ item: DataSet, id: String = UUID().uuidString) -> String {
        items[id] = item
        return id
    }

    /// Removes an item added with `add(_:id:)`.
    @discardableResult
    public func remove(_ id: String) -> DataSet? {
        items.removeValue(forKey: id)
    }

    /// The items added and those of the directory.
    public func allItems() -> [DataSet] {
        items.keys.sorted().compactMap { items[$0] } + (directory.map(Self.items(in:)) ?? [])
    }

    /// The worklist items of a directory; unreadable or empty files are
    /// skipped.
    public static func items(in directory: URL) -> [DataSet] {
        let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var urls: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { urls.append(url) }
        }
        // Files that hold no attribute, such as DCMTK's lockfile, are not
        // items.
        return urls.sorted { $0.path < $1.path }.compactMap { try? item(at: $0) }.filter { !$0.allElements.isEmpty }
    }

    /// A worklist item from a Part 10 file, a bare data set in Little Endian
    /// (Implicit or Explicit VR), or a DICOM JSON file.
    public static func item(at url: URL) throws -> DataSet {
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "json" {
            guard let item = try DICOMJSON.decode(data).first else { throw DICOMJSONError("no data set") }
            return item
        }
        if data.count > 132, data[128..<132].elementsEqual("DICM".utf8) {
            let header = try DICOMPart10Header.read(url)
            let offset = Int(header.dataSetOffset)
            return try DICOMDataSetCoding.decode(
                data.subdata(in: offset..<(offset + header.dataSetLength)), transferSyntax: header.transferSyntaxUID)
        }
        // A bare data set: Explicit VR when the first element carries a VR,
        // two upper-case letters.
        let start = data.startIndex
        let explicit = data.count >= 6 && (start + 4..<start + 6).allSatisfy { (0x41...0x5A).contains(data[$0]) }
        return try DICOMDataSetCoding.decode(
            data, transferSyntax: explicit ? TransferSyntax.explicitVRLittleEndian : TransferSyntax.implicitVRLittleEndian)
    }

    /// The response Identifiers of a C-FIND request.
    ///
    /// - Throws: `DICOMServiceError` with status A900 when the Identifier
    ///   does not fit the information model: a Scheduled Procedure Step
    ///   Sequence with more than one Item (Table K.6-1).
    public func matches(_ identifier: DataSet) throws -> [DataSet] {
        if let sequence = identifier.sequence(forTagName: "ScheduledProcedureStepSequence"), sequence.items.count > 1 {
            throw DICOMServiceError(
                status: .identifierDoesNotMatchSOPClass,
                comment: "the Scheduled Procedure Step Sequence has more than one Item")
        }
        return try allItems().compactMap { try matcher.match(identifier, against: $0) }
    }

    public nonisolated func find(
        _ identifier: DataSet, informationModel: String, context: DICOMServiceContext
    ) async throws -> AsyncThrowingStream<DataSet, Error> {
        let matches = try await matches(identifier)
        return AsyncThrowingStream { continuation in
            for match in matches { continuation.yield(match) }
            continuation.finish()
        }
    }
}
