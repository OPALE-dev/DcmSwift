import Foundation
import NIOCore

/// A DIMSE message: a command and, optionally, a data set encoded in the
/// presentation context's transfer syntax (PS3.7 6.3).
public struct DICOMMessage: Sendable {
    public var presentationContextID: UInt8
    public var command: DICOMCommand
    public var dataSet: DICOMDataSetPayload?

    public init(presentationContextID: UInt8, command: DICOMCommand, dataSet: DICOMDataSetPayload? = nil) {
        self.presentationContextID = presentationContextID
        self.command = command
        self.dataSet = dataSet
    }
}

/// Encoded data set bytes held in memory or in a file. A temporary file
/// created for a received data set is removed with its last payload.
public final class DICOMDataSetPayload: @unchecked Sendable {
    private enum Storage {
        case memory(Data)
        case file(URL, offset: UInt64, owned: Bool)
    }

    private let storage: Storage
    public let length: Int

    public init(data: Data) {
        storage = .memory(data)
        length = data.count
    }

    /// Bytes of an existing file, which is not removed.
    public init(file: URL, offset: UInt64 = 0, length: Int) {
        storage = .file(file, offset: offset, owned: false)
        self.length = length
    }

    /// Bytes of a temporary file, removed with this payload.
    init(temporaryFile: URL, offset: UInt64 = 0, length: Int) {
        storage = .file(temporaryFile, offset: offset, owned: true)
        self.length = length
    }

    deinit {
        if case .file(let url, _, true) = storage {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// The temporary file holding the bytes, if they were spilled to disk.
    public var fileURL: URL? {
        if case .file(let url, _, _) = storage { return url }
        return nil
    }

    /// All bytes in memory.
    public func data() throws -> Data {
        switch storage {
        case .memory(let data):
            return data
        case .file(let url, let offset, _):
            let file = try DICOMPOSIXFile.open(reading: url)
            try file.seek(to: offset)
            var data = Data()
            while data.count < length {
                let chunk = try file.read(upTo: Swift.min(length - data.count, 1 << 20))
                guard !chunk.isEmpty else { throw DICOMCommandError("data set file is shorter than \(length) bytes") }
                data.append(chunk)
            }
            return data
        }
    }

    /// Reads the bytes in chunks of at most `chunk` bytes.
    func chunks(of chunk: Int) throws -> AnyIterator<Data> {
        switch storage {
        case .memory(let data):
            var position = 0
            return AnyIterator {
                guard position < data.count else { return nil }
                defer { position += chunk }
                return data.subdata(
                    in: (data.startIndex + position)..<(data.startIndex + Swift.min(position + chunk, data.count)))
            }
        case .file(let url, let offset, _):
            let file = try DICOMPOSIXFile.open(reading: url)
            try file.seek(to: offset)
            var remaining = length
            // A read error ends the sequence early; the receiver sees a
            // shorter data set and the sender fails on the length check.
            return AnyIterator {
                guard remaining > 0, let data = try? file.read(upTo: Swift.min(chunk, remaining)), !data.isEmpty else {
                    return nil
                }
                remaining -= data.count
                return data
            }
        }
    }
}

/// Splits a message into P-DATA-TF PDUs that fit the peer's Maximum Length
/// Received (PS3.8 9.3.5, PS3.7 Annex E): the command first, then the data
/// set, one PDV per PDU.
public struct DICOMMessageFragmenter: Sequence, IteratorProtocol {
    private let presentationContextID: UInt8
    private var command: Data?
    private var dataChunks: AnyIterator<Data>?
    private var pendingChunk: Data?
    private let fragmentLength: Int

    /// `maximumLength` is the peer's Maximum Length Received (0 for no
    /// limit); fragments never exceed `preferredFragmentLength` either.
    public init(_ message: DICOMMessage, maximumLength: UInt32, preferredFragmentLength: Int = 1 << 16) throws {
        // A P-DATA-TF of one PDV holds 6 bytes besides the fragment.
        let limit = maximumLength == 0 ? Int.max : Int(maximumLength) - 6
        guard limit >= 2 else { throw DICOMCommandError("peer maximum length \(maximumLength) is too small") }
        guard message.command.hasDataSet == (message.dataSet != nil) else {
            throw DICOMCommandError("Command Data Set Type does not match the message")
        }
        presentationContextID = message.presentationContextID
        fragmentLength = Swift.min(limit, preferredFragmentLength)
        command = try message.command.encoded()
        dataChunks = try message.dataSet?.chunks(of: fragmentLength)
        // An empty data set is still sent, as one empty last fragment.
        pendingChunk = message.dataSet.map { _ in dataChunks?.next() ?? Data() }
    }

    public mutating func next() -> DICOMPDU? {
        if var remaining = command {
            let fragment = remaining.prefix(fragmentLength)
            remaining = remaining.dropFirst(fragmentLength)
            command = remaining.isEmpty ? nil : Data(remaining)
            return pdu(Data(fragment), isCommand: true, isLast: remaining.isEmpty)
        }
        guard let chunk = pendingChunk else { return nil }
        pendingChunk = dataChunks?.next()
        return pdu(chunk, isCommand: false, isLast: pendingChunk == nil)
    }

    private func pdu(_ data: Data, isCommand: Bool, isLast: Bool) -> DICOMPDU {
        .data([DICOMPresentationDataValue(
            presentationContextID: presentationContextID, isCommand: isCommand, isLast: isLast,
            data: ByteBufferAllocator().buffer(bytes: data))])
    }
}

/// Reassembles messages from received PDVs (PS3.7 Annex E, PS3.8 9.3.5),
/// enforcing their order and bounding memory: a data set larger than
/// `memoryLimit` is spilled to a temporary file, and one larger than
/// `maximumDataSetLength` aborts the association.
public struct DICOMMessageAssembler {
    public var maximumCommandLength: Int
    public var memoryLimit: Int
    public var maximumDataSetLength: Int
    public var temporaryDirectory: URL

    private enum State {
        case idle
        case command(UInt8, Data)
        case dataSet(UInt8, DICOMCommand, DataSetSink)
    }

    private var state = State.idle

    public init(
        maximumCommandLength: Int = 1 << 16, memoryLimit: Int = 32 << 20, maximumDataSetLength: Int = 1 << 32,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.maximumCommandLength = maximumCommandLength
        self.memoryLimit = memoryLimit
        self.maximumDataSetLength = maximumDataSetLength
        self.temporaryDirectory = temporaryDirectory
    }

    /// Whether a message is partially received.
    public var isIdle: Bool {
        if case .idle = state { return true }
        return false
    }

    /// Appends a PDV; returns the message it completes, if any.
    public mutating func append(_ value: DICOMPresentationDataValue) throws -> DICOMMessage? {
        let data = Data(value.data.readableBytesView)
        switch state {
        case .idle:
            guard value.isCommand else { throw DICOMPDUError(.unexpectedPDUParameter, "data set fragment before a command") }
            state = .command(value.presentationContextID, Data())
            return try append(value)

        case .command(let id, var command):
            guard value.isCommand, value.presentationContextID == id else {
                throw DICOMPDUError(.unexpectedPDUParameter, "fragment interleaved with a command")
            }
            guard command.count + data.count <= maximumCommandLength else {
                throw DICOMPDUError(.invalidPDUParameterValue, "command longer than \(maximumCommandLength) bytes")
            }
            command.append(data)
            guard value.isLast else {
                state = .command(id, command)
                return nil
            }
            let decoded: DICOMCommand
            do {
                decoded = try DICOMCommand(encoded: command, maximumLength: maximumCommandLength)
            } catch {
                throw DICOMPDUError(.invalidPDUParameterValue, "\(error)")
            }
            guard decoded.hasDataSet else {
                state = .idle
                return DICOMMessage(presentationContextID: id, command: decoded)
            }
            state = .dataSet(id, decoded, DataSetSink(
                memoryLimit: memoryLimit, maximumLength: maximumDataSetLength, directory: temporaryDirectory))
            return nil

        case .dataSet(let id, let command, let sink):
            guard !value.isCommand, value.presentationContextID == id else {
                throw DICOMPDUError(.unexpectedPDUParameter, "fragment interleaved with a data set")
            }
            try sink.append(data)
            guard value.isLast else { return nil }
            state = .idle
            return DICOMMessage(presentationContextID: id, command: command, dataSet: try sink.finish())
        }
    }
}

/// Collects data set fragments, in memory then in a temporary file.
final class DataSetSink {
    private let memoryLimit: Int
    private let maximumLength: Int
    private let directory: URL
    private var memory = Data()
    private var file: (url: URL, handle: DICOMPOSIXFile)?
    private(set) var length = 0
    /// The first bytes received, at most `headLength`, kept in memory.
    private(set) var head = Data()
    static let headLength = 1 << 16

    init(memoryLimit: Int, maximumLength: Int, directory: URL) {
        self.memoryLimit = memoryLimit
        self.maximumLength = maximumLength
        self.directory = directory
    }

    deinit {
        // An unfinished transfer leaves no file behind.
        if let file {
            try? file.handle.close()
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    func append(_ data: Data) throws {
        guard length + data.count <= maximumLength else {
            throw DICOMPDUError(.invalidPDUParameterValue, "data set longer than \(maximumLength) bytes")
        }
        length += data.count
        if head.count < Self.headLength { head.append(data.prefix(Self.headLength - head.count)) }
        if file == nil, memory.count + data.count <= memoryLimit {
            memory.append(data)
            return
        }
        if file == nil {
            let url = directory.appendingPathComponent("dcmswift-\(UUID().uuidString).dimse")
            let handle = try DICOMPOSIXFile.create(url)
            file = (url, handle)
            try handle.write(memory)
            memory = Data()
        }
        try file!.handle.write(data)
    }

    func finish() throws -> DICOMDataSetPayload {
        try finish(skipping: 0)
    }

    /// The bytes received after the first `offset` ones, such as the data
    /// set of a Part 10 file after its File Meta Information.
    func finish(skipping offset: Int) throws -> DICOMDataSetPayload {
        precondition(offset <= length)
        guard let file else { return DICOMDataSetPayload(data: Data(memory.dropFirst(offset))) }
        try file.handle.close()
        self.file = nil
        return DICOMDataSetPayload(temporaryFile: file.url, offset: UInt64(offset), length: length - offset)
    }
}

/// Data sets in a presentation context's transfer syntax.
public enum DICOMDataSetCoding {
    /// Encodes the data set elements (not the File Meta Information).
    public static func encode(_ dataset: DataSet, transferSyntax uid: String) throws -> Data {
        guard let syntax = TransferSyntax(uid) else { throw DICOMCommandError("unknown transfer syntax \(uid)") }
        if uid == TransferSyntax.deflatedExplicitVRLittleEndian {
            let explicit = dataset.DIMSEData(transferSyntax: TransferSyntax(TransferSyntax.explicitVRLittleEndian)!)
            return try DICOMDeflate.compress(explicit)
        }
        return dataset.DIMSEData(transferSyntax: syntax)
    }

    /// Decodes data set bytes; `limits` bounds the parser.
    public static func decode(
        _ data: Data, transferSyntax uid: String, limits: DicomReadLimits = DicomReadLimits()
    ) throws -> DataSet {
        guard let syntax = TransferSyntax(uid) else { throw DICOMCommandError("unknown transfer syntax \(uid)") }
        var bytes = data
        var effective = syntax
        if uid == TransferSyntax.deflatedExplicitVRLittleEndian {
            bytes = try DICOMDeflate.decompress(data, maximumOutputLength: limits.maximumInflatedDataSetLength)
            effective = TransferSyntax(TransferSyntax.explicitVRLittleEndian)!
        }
        let stream = DicomInputStream(data: bytes)
        stream.limits = limits
        stream.vrMethod = effective.vrMethod
        stream.byteOrder = effective.byteOrder
        guard let dataset = try stream.readDataset(enforceVR: false) else {
            throw DICOMCommandError("cannot parse the data set")
        }
        dataset.transferSyntax = syntax
        return dataset
    }
}
