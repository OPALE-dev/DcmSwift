import Foundation

/// Storage Commitment results that could not be delivered (PS3.4 J.3.3.2):
/// the SCU was unknown or unreachable once the requesting association was
/// released. They are kept in the `storageCommitmentResults` collection of
/// an archive index and sent again on a new association every
/// `retryInterval` seconds, up to `maximumAttempts` times.
public actor DICOMStorageCommitmentOutbox {
    public nonisolated let index: DICOMArchiveIndex
    public nonisolated let retryInterval: TimeInterval
    public nonisolated let maximumAttempts: Int
    private var client: DICOMClient?
    private var service: DICOMStorageCommitmentService?
    private var scheduled = false

    public init(index: DICOMArchiveIndex = DICOMMemoryArchiveIndex(), retryInterval: TimeInterval = 60,
                maximumAttempts: Int = 10) {
        self.index = index
        self.retryInterval = retryInterval
        self.maximumAttempts = maximumAttempts
    }

    /// The client that opens associations, and the service that knows the
    /// SCUs' addresses; given by `DICOMServer`. Pending results are retried.
    func attach(client: DICOMClient, service: DICOMStorageCommitmentService) async {
        self.client = client
        self.service = service
        if (try? await pending().isEmpty) == false { schedule() }
    }

    /// The results waiting for delivery.
    public func pending() async throws -> [DICOMStorageCommitmentResult] {
        try await index.documents(in: .storageCommitmentResults, matching: DICOMQuery(conditions: []))
            .compactMap { try? DICOMStorageCommitmentResult(dataSet: $0.dataSet()) }
    }

    /// Keeps a result for `aeTitle` and schedules its delivery.
    func enqueue(_ result: DICOMStorageCommitmentResult, for aeTitle: String) async throws {
        try await index.save(DICOMArchiveDocument(
            id: result.transactionUID, dataSet: result.dataSet(), metadata: ["aeTitle": aeTitle, "attempts": "0"]),
            in: .storageCommitmentResults)
        schedule()
    }

    private func schedule() {
        guard !scheduled else { return }
        scheduled = true
        Task {
            try? await Task.sleep(nanoseconds: UInt64(retryInterval * 1_000_000_000))
            await self.retry()
        }
    }

    /// Tries to deliver every pending result now.
    public func retry() async {
        scheduled = false
        guard let client, let service,
              let documents = try? await index.documents(in: .storageCommitmentResults, matching: DICOMQuery(conditions: []))
        else { return }
        for var document in documents {
            guard let result = try? DICOMStorageCommitmentResult(dataSet: document.dataSet()) else { continue }
            let aeTitle = document.metadata["aeTitle"] ?? ""
            let attempts = (Int(document.metadata["attempts"] ?? "") ?? 0) + 1
            do {
                guard let destination = await service.destination(for: aeTitle) else {
                    throw DICOMCommandError("no address for \(aeTitle)")
                }
                try await DICOMRequestDispatcher.deliver(result, to: destination, client: client)
                _ = try? await index.delete(document.id, from: .storageCommitmentResults)
            } catch {
                if attempts >= maximumAttempts {
                    Logger.warning("Storage Commitment result \(result.transactionUID) dropped after \(attempts) attempts: \(error)")
                    _ = try? await index.delete(document.id, from: .storageCommitmentResults)
                } else {
                    document.metadata["attempts"] = String(attempts)
                    try? await index.replace(document, in: .storageCommitmentResults)
                }
            }
        }
        if (try? await pending().isEmpty) == false { schedule() }
    }
}
