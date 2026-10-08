import Foundation
import NIOCore

/// A reference to a composite instance.
public struct DICOMSOPReference: Hashable, Sendable {
    public var sopClassUID: String
    public var sopInstanceUID: String

    public init(sopClassUID: String, sopInstanceUID: String) {
        self.sopClassUID = sopClassUID
        self.sopInstanceUID = sopInstanceUID
    }
}

/// A Storage Commitment request (PS3.4 J.3.2.1.1): N-ACTION Action Type 1.
public struct DICOMStorageCommitmentRequest: Equatable, Sendable {
    public var transactionUID: String
    public var references: [DICOMSOPReference]
    public var storageMediaFileSetID: String?
    public var storageMediaFileSetUID: String?

    public init(
        transactionUID: String, references: [DICOMSOPReference], storageMediaFileSetID: String? = nil,
        storageMediaFileSetUID: String? = nil
    ) {
        self.transactionUID = transactionUID
        self.references = references
        self.storageMediaFileSetID = storageMediaFileSetID
        self.storageMediaFileSetUID = storageMediaFileSetUID
    }
}

/// A Storage Commitment Result (PS3.4 J.3.3.1): N-EVENT-REPORT Event Type
/// 1 when every instance is committed, 2 when failures exist.
public struct DICOMStorageCommitmentResult: Equatable, Sendable {
    /// Failure Reason values (PS3.3 C.14.1.1).
    public enum FailureReason {
        public static let processingFailure: UInt16 = 0x0110
        public static let noSuchSOPInstance: UInt16 = 0x0112
        public static let resourceLimitation: UInt16 = 0x0213
        public static let referencedSOPClassNotSupported: UInt16 = 0x0122
        public static let classInstanceConflict: UInt16 = 0x0119
        public static let duplicateTransactionUID: UInt16 = 0x0131
    }

    public struct Failure: Hashable, Sendable {
        public var reference: DICOMSOPReference
        public var reason: UInt16

        public init(reference: DICOMSOPReference, reason: UInt16) {
            self.reference = reference
            self.reason = reason
        }
    }

    public var transactionUID: String
    public var committed: [DICOMSOPReference]
    public var failed: [Failure]
    /// Where the committed instances can be retrieved.
    public var retrieveAETitle: String?

    public init(
        transactionUID: String, committed: [DICOMSOPReference], failed: [Failure] = [], retrieveAETitle: String? = nil
    ) {
        self.transactionUID = transactionUID
        self.committed = committed
        self.failed = failed
        self.retrieveAETitle = retrieveAETitle
    }

    /// The Event Type ID of the notification.
    public var eventTypeID: UInt16 { failed.isEmpty ? 1 : 2 }

    /// Every referenced instance failed for `reason`.
    public static func failure(of request: DICOMStorageCommitmentRequest, reason: UInt16) -> Self {
        Self(transactionUID: request.transactionUID, committed: [],
             failed: request.references.map { Failure(reference: $0, reason: reason) })
    }
}

/// Commits to storing instances, as the SCP of the Storage Commitment Push
/// Model SOP Class (PS3.4 J.3). The server answers the N-ACTION at once,
/// then calls `commit` and sends its result by N-EVENT-REPORT: on the same
/// association while it is open, otherwise on a new association to
/// `destination(for:)` of the requestor's AE title, proposing the SCP role.
public protocol DICOMStorageCommitmentService: Sendable {
    /// Decides which referenced instances are committed. Every reference
    /// must appear in the result, committed or failed; an error fails them
    /// all with Processing Failure.
    func commit(
        _ request: DICOMStorageCommitmentRequest, context: DICOMServiceContext
    ) async throws -> DICOMStorageCommitmentResult

    /// The SCU's address, for results sent on a new association.
    func destination(for aeTitle: String) async -> DICOMRemoteNode?
}

/// Receives Storage Commitment results as the SCU, on any association
/// (PS3.4 J.3.3.1.3). Results that arrive on the association that sent the
/// request are also available through `storageCommitmentResult`.
public protocol DICOMStorageCommitmentReceiver: Sendable {
    func received(_ result: DICOMStorageCommitmentResult, context: DICOMServiceContext) async throws
}

extension DICOMSOPClass {
    /// The well-known Storage Commitment Push Model SOP Instance (PS3.4
    /// J.3.6).
    public static let storageCommitmentPushModelInstance = "1.2.840.10008.1.20.1.1"
}

// MARK: Coding

extension DICOMStorageCommitmentRequest {
    /// The Action Information.
    func dataSet() -> DataSet {
        let dataSet = DataSet()
        _ = dataSet.set(value: transactionUID, forTagName: "TransactionUID")
        if let storageMediaFileSetID { _ = dataSet.set(value: storageMediaFileSetID, forTagName: "StorageMediaFileSetID") }
        if let storageMediaFileSetUID { _ = dataSet.set(value: storageMediaFileSetUID, forTagName: "StorageMediaFileSetUID") }
        dataSet.appendSequence("ReferencedSOPSequence", items: references.map {
            [("ReferencedSOPClassUID", $0.sopClassUID), ("ReferencedSOPInstanceUID", $0.sopInstanceUID)]
        })
        return dataSet
    }

    init(dataSet: DataSet) throws {
        guard let transaction = dataSet.string(forTag: "TransactionUID"), !transaction.isEmpty else {
            throw DICOMCommandError("Storage Commitment request without Transaction UID")
        }
        let references = try DICOMStorageCommitmentResult.references(in: dataSet, "ReferencedSOPSequence")
        guard !references.isEmpty else { throw DICOMCommandError("Storage Commitment request without references") }
        self.init(
            transactionUID: transaction, references: references.map(\.0),
            storageMediaFileSetID: dataSet.string(forTag: "StorageMediaFileSetID"),
            storageMediaFileSetUID: dataSet.string(forTag: "StorageMediaFileSetUID"))
    }
}

extension DICOMStorageCommitmentResult {
    /// The Event Information.
    func dataSet() -> DataSet {
        let dataSet = DataSet()
        _ = dataSet.set(value: transactionUID, forTagName: "TransactionUID")
        if let retrieveAETitle { _ = dataSet.set(value: retrieveAETitle, forTagName: "RetrieveAETitle") }
        if !committed.isEmpty || failed.isEmpty {
            dataSet.appendSequence("ReferencedSOPSequence", items: committed.map {
                [("ReferencedSOPClassUID", $0.sopClassUID), ("ReferencedSOPInstanceUID", $0.sopInstanceUID)]
            })
        }
        if !failed.isEmpty {
            dataSet.appendSequence("FailedSOPSequence", items: failed.map {
                [("ReferencedSOPClassUID", $0.reference.sopClassUID),
                 ("ReferencedSOPInstanceUID", $0.reference.sopInstanceUID), ("FailureReason", $0.reason)]
            })
        }
        return dataSet
    }

    init(dataSet: DataSet) throws {
        guard let transaction = dataSet.string(forTag: "TransactionUID"), !transaction.isEmpty else {
            throw DICOMCommandError("Storage Commitment result without Transaction UID")
        }
        let committed = try Self.references(in: dataSet, "ReferencedSOPSequence")
        let failed = try Self.references(in: dataSet, "FailedSOPSequence").map { reference, item in
            Failure(reference: reference,
                    reason: (item.element(withName: "FailureReason")?.value as? UInt16) ?? FailureReason.processingFailure)
        }
        self.init(transactionUID: transaction, committed: committed.map(\.0), failed: failed,
                  retrieveAETitle: dataSet.string(forTag: "RetrieveAETitle"))
    }

    static func references(in dataSet: DataSet, _ sequence: String) throws -> [(DICOMSOPReference, DataItem)] {
        try (dataSet.sequence(forTagName: sequence)?.items ?? []).map { item in
            func uid(_ name: String) -> String? {
                (item.element(withName: name)?.value as? String)?.trimmingCharacters(in: [" ", "\0"])
            }
            guard let sopClass = uid("ReferencedSOPClassUID"), let sopInstance = uid("ReferencedSOPInstanceUID") else {
                throw DICOMCommandError("\(sequence) item without Referenced SOP Class and Instance UIDs")
            }
            return (DICOMSOPReference(sopClassUID: sopClass, sopInstanceUID: sopInstance), item)
        }
    }
}

extension DataSet {
    /// Adds a sequence whose items hold the given attributes, by keyword.
    func appendSequence(_ name: String, items: [[(String, Any)]]) {
        guard let tag = DicomSpec.shared.dataTag(forName: name) else { return }
        let sequence = DataSequence(withTag: tag, parent: nil)
        sequence.dataset = self
        sequence.vr = .SQ
        for attributes in items {
            let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
            item.dataset = self
            for (keyword, value) in attributes {
                guard let element = DataElement(withTagName: keyword, dataset: self, parent: item),
                      element.setValue(value) else { continue }
                item.elements.append(element)
            }
            item.elements.sort { $0.tagCode() < $1.tagCode() }
            sequence.items.append(item)
        }
        add(element: sequence)
        sortElements()
    }
}

// MARK: SCU

extension DICOMAssociation {
    /// Asks the peer to commit to storing instances (N-ACTION, PS3.4
    /// J.3.2). Returns the Transaction UID once the request is accepted;
    /// the result comes later by N-EVENT-REPORT.
    @discardableResult
    public func requestStorageCommitment(
        _ references: [DICOMSOPReference], transactionUID: String = UID.generate()
    ) async throws -> String {
        let request = DICOMStorageCommitmentRequest(transactionUID: transactionUID, references: references)
        let response = try await nAction(
            sopClassUID: DICOMSOPClass.storageCommitmentPushModel,
            sopInstanceUID: DICOMSOPClass.storageCommitmentPushModelInstance, actionTypeID: 1,
            information: request.dataSet())
        guard response.status.category == .success || response.status.category == .warning else {
            throw DICOMServiceError(status: response.status, comment: response.errorComment)
        }
        return transactionUID
    }

    /// Waits for the result of a Storage Commitment request on this
    /// association, at most `timeout`; nil if it does not come in time or
    /// the association ends first.
    public func storageCommitmentResult(
        transactionUID: String, timeout: TimeAmount = .seconds(60)
    ) async -> DICOMStorageCommitmentResult? {
        await runtime.commitmentResult(transactionUID, timeout: timeout)
    }

    /// Requests Storage Commitment and waits for its result on this
    /// association (see `requestStorageCommitment` and
    /// `storageCommitmentResult`).
    public func commit(
        _ references: [DICOMSOPReference], timeout: TimeAmount = .seconds(60)
    ) async throws -> DICOMStorageCommitmentResult? {
        let transaction = try await requestStorageCommitment(references)
        return await storageCommitmentResult(transactionUID: transaction, timeout: timeout)
    }
}

extension DICOMRetrieveItem {
    /// The SOP Class and Instance of the item.
    public var reference: DICOMSOPReference {
        DICOMSOPReference(sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID)
    }
}
