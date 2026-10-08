import Foundation
import NIOSSL

/// What a service knows about the request it performs.
public struct DICOMServiceContext: Sendable {
    public let callingAETitle: String
    public let calledAETitle: String
    public let remoteAddress: String
    public let userIdentity: DICOMUserIdentity?
    public let presentationContext: DICOMAcceptedPresentationContext
    /// The certificate the peer presented over TLS, for access control.
    public var peerCertificate: NIOSSLCertificate? = nil
    let cancelled: @Sendable () async -> Bool

    /// Whether the requestor cancelled the operation (C-CANCEL).
    public var isCancelled: Bool {
        get async { await cancelled() }
    }
}

/// A composite instance received by C-STORE, as encoded in the presentation
/// context's transfer syntax.
public struct DICOMReceivedInstance: Sendable {
    public let sopClassUID: String
    public let sopInstanceUID: String
    public let transferSyntaxUID: String
    public let payload: DICOMDataSetPayload
    /// The AE that asked for this instance with C-MOVE, if any.
    public let moveOriginatorAETitle: String?
    public let moveOriginatorMessageID: UInt16?
    /// The sender's AE title.
    public let sourceAETitle: String

    /// Decodes the data set.
    public func dataSet(limits: DicomReadLimits = DicomReadLimits()) throws -> DataSet {
        try DICOMDataSetCoding.decode(payload.data(), transferSyntax: transferSyntaxUID, limits: limits)
    }

    /// Writes a Part 10 file: the File Meta Information, then the received
    /// bytes unchanged. The file appears atomically.
    public func write(to url: URL) throws {
        let partial = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).partial")
        do {
            let file = try DICOMPOSIXFile.create(partial)
            try file.write(DICOMPart10Header.encodeMetaInformation(
                sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID, transferSyntaxUID: transferSyntaxUID,
                sourceAETitle: sourceAETitle))
            for chunk in try payload.chunks(of: 1 << 20) { try file.write(chunk) }
            try file.close()
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: partial)
            } else {
                try FileManager.default.moveItem(at: partial, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }
}

/// A composite instance to send by C-STORE, for C-MOVE and C-GET.
public struct DICOMRetrieveItem: Sendable {
    public let sopClassUID: String
    public let sopInstanceUID: String
    public let transferSyntaxUID: String
    public let payload: DICOMDataSetPayload

    public init(sopClassUID: String, sopInstanceUID: String, transferSyntaxUID: String, payload: DICOMDataSetPayload) {
        self.sopClassUID = sopClassUID
        self.sopInstanceUID = sopInstanceUID
        self.transferSyntaxUID = transferSyntaxUID
        self.payload = payload
    }

    /// The data set of a Part 10 file, read when sent.
    public init(file url: URL) throws {
        let header = try DICOMPart10Header.read(url)
        self.init(
            sopClassUID: header.sopClassUID, sopInstanceUID: header.sopInstanceUID,
            transferSyntaxUID: header.transferSyntaxUID,
            payload: DICOMDataSetPayload(file: url, offset: header.dataSetOffset, length: header.dataSetLength))
    }

    /// A data set in memory, encoded in `transferSyntaxUID`.
    public init(dataSet: DataSet, transferSyntaxUID: String = TransferSyntax.explicitVRLittleEndian) throws {
        guard let sopClass = dataSet.string(forTag: "SOPClassUID"),
              let sopInstance = dataSet.string(forTag: "SOPInstanceUID") else {
            throw DICOMCommandError("the data set has no SOP Class or SOP Instance UID")
        }
        self.init(
            sopClassUID: sopClass, sopInstanceUID: sopInstance, transferSyntaxUID: transferSyntaxUID,
            payload: DICOMDataSetPayload(data: try DICOMDataSetCoding.encode(dataSet, transferSyntax: transferSyntaxUID)))
    }
}

/// Receives C-STORE requests (PS3.4 Annex B), on an SCP or during C-GET.
public protocol DICOMStorageService: Sendable {
    /// Stores an instance and returns the C-STORE status.
    func store(_ instance: DICOMReceivedInstance, context: DICOMServiceContext) async throws -> DICOMStatus
}

/// Answers C-FIND requests (PS3.4 C.4.1).
public protocol DICOMQueryService: Sendable {
    /// The matches of `identifier` in the information model (a FIND SOP
    /// Class UID). Each match is answered with a Pending response.
    func find(
        _ identifier: DataSet, informationModel: String, context: DICOMServiceContext
    ) async throws -> AsyncThrowingStream<DataSet, Error>
}

/// Answers C-MOVE and C-GET requests (PS3.4 C.4.2, C.4.3).
public protocol DICOMRetrieveService: Sendable {
    /// The instances matching `identifier` in the information model (a MOVE
    /// or GET SOP Class UID).
    func retrieve(
        _ identifier: DataSet, informationModel: String, context: DICOMServiceContext
    ) async throws -> [DICOMRetrieveItem]

    /// The C-MOVE destination with this AE title, or nil if unknown.
    func destination(for aeTitle: String) async -> DICOMRemoteNode?
}

/// Sub-operation counts of C-MOVE and C-GET (PS3.7 9.1.3, 9.1.4).
public struct DICOMRetrieveProgress: Equatable, Sendable {
    public var remaining: Int
    public var completed: Int
    public var failed: Int
    public var warning: Int

    public init(remaining: Int = 0, completed: Int = 0, failed: Int = 0, warning: Int = 0) {
        self.remaining = remaining
        self.completed = completed
        self.failed = failed
        self.warning = warning
    }
}

/// The final response of C-MOVE or C-GET.
public struct DICOMRetrieveResult: Sendable {
    public let status: DICOMStatus
    public let progress: DICOMRetrieveProgress
    /// SOP Instance UIDs of failed sub-operations, when reported (Failed
    /// SOP Instance UID List).
    public let failedInstances: [String]
}
