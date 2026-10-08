import Foundation
import NIOCore
import NIOSSL

/// A DIMSE operation failed with a status other than success or warning.
public struct DICOMServiceError: Error, Equatable, CustomStringConvertible {
    public let status: DICOMStatus
    public let comment: String?

    public var description: String {
        "DIMSE status \(status)" + (comment.map { ": \($0)" } ?? "")
    }
}

/// An established association. On the requestor side it performs DIMSE
/// operations (PS3.7 9, 10); on either side it is valid only within the
/// scope that provides it.
public final class DICOMAssociation: Sendable {
    let runtime: DICOMAssociationRuntime

    init(runtime: DICOMAssociationRuntime) {
        self.runtime = runtime
    }

    /// The negotiated parameters.
    public var negotiated: DICOMNegotiatedAssociation { runtime.negotiated }

    /// The peer's address.
    public var remoteAddress: String { runtime.remoteAddress }

    /// The certificate the peer presented over TLS: the server's, or with
    /// mutual authentication the client's.
    public var peerCertificate: NIOSSLCertificate? { runtime.peerCertificate }

    /// Aborts the association (A-ABORT).
    public func abort() async {
        await runtime.abort()
    }

    // MARK: Presentation contexts

    /// An accepted context for `abstractSyntax` on which this side may
    /// issue requests, preferring the given transfer syntaxes.
    func context(for abstractSyntax: String, preferring syntaxes: [String] = []) throws -> DICOMAcceptedPresentationContext {
        let isRequestor = runtime.role == .requestor
        let usable = negotiated.contexts(for: abstractSyntax).filter { isRequestor ? $0.requestorIsSCU : $0.requestorIsSCP }
        for syntax in syntaxes {
            if let context = usable.first(where: { $0.transferSyntax == syntax }) { return context }
        }
        guard let context = usable.first else { throw DICOMNetworkError.noPresentationContext(abstractSyntax: abstractSyntax) }
        return context
    }

    // MARK: Operations

    /// Sends a request and waits for its final response.
    public func perform(
        _ command: DICOMCommand, dataSet: DICOMDataSetPayload? = nil, abstractSyntax: String
    ) async throws -> DICOMMessage {
        let context = try context(for: abstractSyntax)
        let (_, queue) = try await runtime.request(command, dataSet: dataSet, contextID: context.id)
        var last: DICOMMessage?
        while let response = try await queue.next() { last = response }
        guard let last else { throw DICOMNetworkError.connectionClosed }
        try Self.check(last, answers: command)
        return last
    }

    private static func check(_ response: DICOMMessage, answers request: DICOMCommand) throws {
        guard response.command.field == request.field.response else {
            throw DICOMNetworkError.protocolViolation("\(response.command.field) answers \(request.field)")
        }
    }

    /// C-ECHO (PS3.7 9.1.5).
    @discardableResult
    public func echo() async throws -> DICOMStatus {
        var command = DICOMCommand(field: .cEchoRequest)
        command.affectedSOPClassUID = DICOMSOPClass.verification
        let response = try await perform(command, abstractSyntax: DICOMSOPClass.verification)
        return response.command.statusValue ?? .success
    }

    /// C-STORE of an instance (PS3.7 9.1.1). The data set is sent as
    /// encoded when a context accepted its transfer syntax, and converted
    /// otherwise between uncompressed transfer syntaxes.
    @discardableResult
    public func store(
        _ item: DICOMRetrieveItem, priority: DICOMCommand.Priority = .medium,
        moveOriginator: (aeTitle: String, messageID: UInt16)? = nil
    ) async throws -> DICOMStatus {
        let (context, payload) = try prepare(item)
        var command = DICOMCommand(field: .cStoreRequest, hasDataSet: true)
        command.affectedSOPClassUID = item.sopClassUID
        command.affectedSOPInstanceUID = item.sopInstanceUID
        command.priority = priority.rawValue
        command.moveOriginatorAETitle = moveOriginator?.aeTitle
        command.moveOriginatorMessageID = moveOriginator?.messageID
        let (_, queue) = try await runtime.request(command, dataSet: payload, contextID: context.id)
        var last: DICOMMessage?
        while let response = try await queue.next() { last = response }
        guard let last else { throw DICOMNetworkError.connectionClosed }
        try Self.check(last, answers: command)
        return last.command.statusValue ?? .success
    }

    /// C-STORE of a data set.
    @discardableResult
    public func store(_ dataSet: DataSet, priority: DICOMCommand.Priority = .medium) async throws -> DICOMStatus {
        let syntax = dataSet.transferSyntax?.tsUID ?? TransferSyntax.explicitVRLittleEndian
        let item = try DICOMRetrieveItem(
            dataSet: dataSet, transferSyntaxUID: Self.isUncompressed(syntax) ? TransferSyntax.explicitVRLittleEndian : syntax)
        return try await store(item, priority: priority)
    }

    /// C-STORE of a Part 10 file, streamed from disk.
    @discardableResult
    public func store(file url: URL, priority: DICOMCommand.Priority = .medium) async throws -> DICOMStatus {
        try await store(DICOMRetrieveItem(file: url), priority: priority)
    }

    static func isUncompressed(_ uid: String) -> Bool {
        [TransferSyntax.implicitVRLittleEndian, TransferSyntax.explicitVRLittleEndian,
         TransferSyntax.explicitVRBigEndian, TransferSyntax.deflatedExplicitVRLittleEndian].contains(uid)
    }

    /// The context to send an item on and its bytes in that context's
    /// transfer syntax.
    func prepare(_ item: DICOMRetrieveItem) throws -> (DICOMAcceptedPresentationContext, DICOMDataSetPayload) {
        // The item's own syntax, else, for an uncompressed item, any
        // uncompressed one: another context of the class may hold a
        // compressed syntax the item cannot be converted to.
        let fallbacks = Self.isUncompressed(item.transferSyntaxUID)
            ? [TransferSyntax.explicitVRLittleEndian, TransferSyntax.implicitVRLittleEndian,
               TransferSyntax.deflatedExplicitVRLittleEndian, TransferSyntax.explicitVRBigEndian] : []
        let context = try context(for: item.sopClassUID, preferring: [item.transferSyntaxUID] + fallbacks)
        if context.transferSyntax == item.transferSyntaxUID { return (context, item.payload) }
        guard Self.isUncompressed(item.transferSyntaxUID), Self.isUncompressed(context.transferSyntax) else {
            throw DICOMNetworkError.noPresentationContext(abstractSyntax: item.sopClassUID)
        }
        let dataSet = try DICOMDataSetCoding.decode(item.payload.data(), transferSyntax: item.transferSyntaxUID)
        let converted = try DICOMDataSetCoding.encode(dataSet, transferSyntax: context.transferSyntax)
        return (context, DICOMDataSetPayload(data: converted))
    }

    /// C-FIND (PS3.7 9.1.2): the matches, as they arrive. Stopping the
    /// iteration early cancels the query (C-CANCEL).
    public func find(
        _ identifier: DataSet, informationModel: String = DICOMSOPClass.studyRootFind,
        priority: DICOMCommand.Priority = .medium
    ) -> DICOMQueryResults {
        DICOMQueryResults(association: self, identifier: identifier, informationModel: informationModel, priority: priority)
    }

    /// C-MOVE (PS3.7 9.1.4) to `destination`; cancelling the task cancels
    /// the retrieval (C-CANCEL) and waits for its final response.
    public func move(
        _ identifier: DataSet, destination: String, informationModel: String = DICOMSOPClass.studyRootMove,
        priority: DICOMCommand.Priority = .medium,
        progress: (@Sendable (DICOMRetrieveProgress) -> Void)? = nil
    ) async throws -> DICOMRetrieveResult {
        var command = DICOMCommand(field: .cMoveRequest, hasDataSet: true)
        command.affectedSOPClassUID = informationModel
        command.priority = priority.rawValue
        command.moveDestination = destination
        return try await retrieve(command, identifier: identifier, progress: progress)
    }

    /// C-GET (PS3.7 9.1.3): the instances arrive on this association as
    /// C-STORE requests, handled by the storage service the association
    /// was opened with; their SOP classes need contexts proposing the SCP
    /// role.
    public func get(
        _ identifier: DataSet, informationModel: String = DICOMSOPClass.studyRootGet,
        priority: DICOMCommand.Priority = .medium,
        progress: (@Sendable (DICOMRetrieveProgress) -> Void)? = nil
    ) async throws -> DICOMRetrieveResult {
        var command = DICOMCommand(field: .cGetRequest, hasDataSet: true)
        command.affectedSOPClassUID = informationModel
        command.priority = priority.rawValue
        return try await retrieve(command, identifier: identifier, progress: progress)
    }

    private func retrieve(
        _ command: DICOMCommand, identifier: DataSet, progress: (@Sendable (DICOMRetrieveProgress) -> Void)?
    ) async throws -> DICOMRetrieveResult {
        let context = try context(for: command.affectedSOPClassUID ?? "")
        let payload = DICOMDataSetPayload(data: try DICOMDataSetCoding.encode(identifier, transferSyntax: context.transferSyntax))
        let (id, queue) = try await runtime.request(command, dataSet: payload, contextID: context.id)
        let runtime = self.runtime
        return try await withTaskCancellationHandler {
            var last: DICOMMessage?
            while let response = try await queue.next() {
                last = response
                if response.command.statusValue?.isPending == true {
                    progress?(Self.progress(of: response.command))
                }
            }
            guard let last else { throw DICOMNetworkError.connectionClosed }
            try Self.check(last, answers: command)
            let status = last.command.statusValue ?? .success
            let failures = try last.dataSet.map {
                try DICOMDataSetCoding.decode($0.data(), transferSyntax: context.transferSyntax)
                    .string(forTag: "FailedSOPInstanceUIDList")?.split(separator: "\\").map(String.init) ?? []
            } ?? []
            if status.category == .failure {
                throw DICOMServiceError(status: status, comment: last.command.errorComment)
            }
            return DICOMRetrieveResult(status: status, progress: Self.progress(of: last.command), failedInstances: failures)
        } onCancel: {
            Task { await runtime.cancel(messageID: id, contextID: context.id) }
        }
    }

    static func progress(of command: DICOMCommand) -> DICOMRetrieveProgress {
        DICOMRetrieveProgress(
            remaining: Int(command.remainingSuboperations ?? 0), completed: Int(command.completedSuboperations ?? 0),
            failed: Int(command.failedSuboperations ?? 0), warning: Int(command.warningSuboperations ?? 0))
    }
}

/// The matches of a C-FIND, read as they arrive.
public struct DICOMQueryResults: AsyncSequence, Sendable {
    public typealias Element = DataSet

    let association: DICOMAssociation
    let identifier: DataSet
    let informationModel: String
    let priority: DICOMCommand.Priority

    public func makeAsyncIterator() -> Iterator {
        Iterator(results: self)
    }

    /// Iterates the matches; an error is a failure status or a network
    /// failure.
    public final class Iterator: AsyncIteratorProtocol {
        private let results: DICOMQueryResults
        private var started: (id: UInt16, queue: DICOMMessageQueue, context: DICOMAcceptedPresentationContext)?
        private var finished = false
        /// The final status, once the iteration ended.
        public private(set) var status: DICOMStatus?

        init(results: DICOMQueryResults) {
            self.results = results
        }

        deinit {
            // Abandoned before the final response: cancel the query.
            if let started, !finished {
                let runtime = results.association.runtime
                started.queue.abandon()
                Task {
                    await runtime.cancel(messageID: started.id, contextID: started.context.id)
                    await runtime.forget(messageID: started.id)
                }
            }
        }

        public func next() async throws -> DataSet? {
            if finished { return nil }
            if started == nil {
                let association = results.association
                let context = try association.context(for: results.informationModel)
                var command = DICOMCommand(field: .cFindRequest, hasDataSet: true)
                command.affectedSOPClassUID = results.informationModel
                command.priority = results.priority.rawValue
                let payload = DICOMDataSetPayload(
                    data: try DICOMDataSetCoding.encode(results.identifier, transferSyntax: context.transferSyntax))
                let (id, queue) = try await association.runtime.request(command, dataSet: payload, contextID: context.id)
                started = (id, queue, context)
            }
            guard let started else { return nil }
            do {
                guard let response = try await started.queue.next() else {
                    finished = true
                    throw DICOMNetworkError.connectionClosed
                }
                guard response.command.field == .cFindResponse else {
                    throw DICOMNetworkError.protocolViolation("\(response.command.field) answers C-FIND-RQ")
                }
                let status = response.command.statusValue ?? .success
                if status.isPending {
                    guard let dataSet = response.dataSet else {
                        throw DICOMNetworkError.protocolViolation("pending C-FIND-RSP without identifier")
                    }
                    return try DICOMDataSetCoding.decode(dataSet.data(), transferSyntax: started.context.transferSyntax)
                }
                finished = true
                self.status = status
                if status.category == .failure {
                    throw DICOMServiceError(status: status, comment: response.command.errorComment)
                }
                return nil
            } catch {
                finished = true
                throw error
            }
        }
    }
}
