import Foundation

/// A Modality Worklist SCP (PS3.4 K.6): the worklist items it holds answer
/// C-FIND on the Modality Worklist Information Model.
///
/// Each item is a data set with the attributes of one Scheduled Procedure
/// Step and of the Requested Procedure, Imaging Service Request, Visit, and
/// Patient it belongs to (PS3.4 Table K.6-1). Items are kept in the
/// `worklist` collection of an archive index (`add(_:id:)`), and, with a
/// directory, also read from the files found there at each query: Part 10
/// files, data sets without File Meta Information (such as DCMTK `.wl`
/// files), and DICOM JSON files (`.json`), searched recursively.
///
/// Every attribute of an item can be matched, with the rules of
/// `DICOMQueryMatcher.modalityWorklist`; there are no unsupported optional
/// keys, so every match is answered with status FF00.
public actor DICOMModalityWorklist: DICOMQueryService {
    /// A directory read at each query, or nil.
    public nonisolated let directory: URL?
    /// Where the items added are kept.
    public nonisolated let index: DICOMArchiveIndex
    private let matcher: DICOMQueryMatcher

    public init(index: DICOMArchiveIndex = DICOMMemoryArchiveIndex(), directory: URL? = nil,
                matcher: DICOMQueryMatcher = .modalityWorklist) {
        self.index = index
        self.directory = directory
        self.matcher = matcher
    }

    /// Adds or replaces an item; returns its identifier for `remove(_:)`.
    @discardableResult
    public func add(_ item: DataSet, id: String = UUID().uuidString) async throws -> String {
        try await index.save(DICOMArchiveDocument(id: id, dataSet: item), in: .worklist)
        return id
    }

    /// Removes an item added with `add(_:id:)`; returns whether it existed.
    @discardableResult
    public func remove(_ id: String) async throws -> Bool {
        try await index.delete(id, from: .worklist)
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
    public func matches(_ identifier: DataSet) async throws -> [DataSet] {
        if let sequence = identifier.sequence(forTagName: "ScheduledProcedureStepSequence"), sequence.items.count > 1 {
            throw DICOMServiceError(
                status: .identifierDoesNotMatchSOPClass,
                comment: "the Scheduled Procedure Step Sequence has more than one Item")
        }
        let keys = try DICOMJSON.object(identifier, options: DICOMJSON.EncodingOptions(numbersAsStrings: true))
        var items = try await index.documents(in: .worklist, matching: DICOMQuery(identifier: keys, matcher: matcher))
            .map(\.attributes)
        if let directory {
            items += try Self.items(in: directory).map {
                try DICOMJSON.object($0, options: DICOMJSON.EncodingOptions(numbersAsStrings: true))
            }
        }
        return try items.compactMap { try matcher.match(keys, against: $0).map { try DICOMJSON.dataSet($0) } }
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
