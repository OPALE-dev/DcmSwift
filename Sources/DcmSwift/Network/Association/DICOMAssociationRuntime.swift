import Foundation
import Logging
import NIOCore
import NIOSSL

/// The machinery of an established association, shared by requestors and
/// acceptors: it drives the PS3.8 state machine, serializes outgoing
/// messages, reassembles incoming ones, routes responses to the operation
/// waiting for them and requests to the service side, and runs the ARTIM
/// timer, release, and abort.
actor DICOMAssociationRuntime {
    nonisolated let negotiated: DICOMNegotiatedAssociation
    nonisolated let role: DICOMAssociationStateMachine.Role
    nonisolated let logger: Logging.Logger
    /// Remote address, for logging and service contexts.
    nonisolated let remoteAddress: String
    /// The certificate the peer presented over TLS, if any.
    nonisolated let peerCertificate: NIOSSLCertificate?

    private let outbound: NIOAsyncChannelOutboundWriter<DICOMPDU>
    private let channel: Channel
    private let timeouts: DICOMNetworkTimeouts
    private var machine: DICOMAssociationStateMachine
    private var assembler: DICOMMessageAssembler
    private var artim: Scheduled<Void>?

    private var nextMessageID: UInt16 = 1
    /// Operations waiting for responses, by Message ID.
    private var responses: [UInt16: DICOMMessageQueue] = [:]
    /// Requests from the peer being performed, and whether C-CANCEL arrived.
    private var performing: [UInt16: Bool] = [:]
    /// The most peer requests performed at once (the negotiated window).
    nonisolated let maximumPerforming: Int

    private var sending = false
    private var sendWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Error>?
    private var releaseRequestedByPeer = false
    private var releaseConfirmed = false
    private(set) var failure: DICOMNetworkError?

    /// Storage Commitment results received, and the operations waiting for
    /// them, by Transaction UID.
    private var commitmentResults: [String: DICOMStorageCommitmentResult] = [:]
    private var commitmentWaiters: [String: [(UInt64, CheckedContinuation<DICOMStorageCommitmentResult?, Never>)]] = [:]
    private var nextWaiter: UInt64 = 0
    /// Waiting for the peer requests being performed to finish.
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        machine: DICOMAssociationStateMachine, negotiated: DICOMNegotiatedAssociation,
        outbound: NIOAsyncChannelOutboundWriter<DICOMPDU>, channel: Channel,
        limits: DICOMNetworkLimits, timeouts: DICOMNetworkTimeouts, logger: Logging.Logger,
        peerCertificate: NIOSSLCertificate? = nil
    ) {
        self.peerCertificate = peerCertificate
        self.machine = machine
        self.negotiated = negotiated
        self.role = machine.role
        self.outbound = outbound
        self.channel = channel
        self.timeouts = timeouts
        self.logger = logger
        remoteAddress = channel.remoteAddress?.description ?? "unknown"
        assembler = limits.makeAssembler()
        let window = machine.role == .acceptor
            ? negotiated.asynchronousOperationsWindow.maximumPerformed
            : negotiated.asynchronousOperationsWindow.maximumInvoked
        maximumPerforming = window == 0 ? 64 : Int(min(window, 64))
    }

    // MARK: Sending

    private func acquireSend() async {
        if !sending {
            sending = true
            return
        }
        await withCheckedContinuation { sendWaiters.append($0) }
    }

    private func releaseSend() {
        if sendWaiters.isEmpty {
            sending = false
        } else {
            sendWaiters.removeFirst().resume()
        }
    }

    /// Sends a message, its fragments contiguous on the wire.
    func send(_ message: DICOMMessage) async throws {
        if let failure { throw failure }
        await acquireSend()
        defer { releaseSend() }
        if let failure { throw failure }
        guard machine.state == .established || machine.state == .awaitingLocalReleaseResponse
                || machine.state == .awaitingReleaseResponse else {
            throw DICOMNetworkError.invalidState("cannot send in state \(machine.state)")
        }
        let maximum = role == .requestor ? negotiated.acceptorMaximumLength : negotiated.requestorMaximumLength
        let fragments = try DICOMMessageFragmenter(message, maximumLength: maximum)
        for pdu in fragments {
            if let failure { throw failure }
            do {
                try await outbound.write(pdu)
            } catch {
                fail(.connectionClosed)
                throw DICOMNetworkError.connectionClosed
            }
        }
    }

    /// Sends a request and returns the queue its responses arrive on.
    func request(
        _ command: DICOMCommand, dataSet: DICOMDataSetPayload?, contextID: UInt8
    ) async throws -> (UInt16, DICOMMessageQueue) {
        if let failure { throw failure }
        var command = command
        var id = nextMessageID
        while responses[id] != nil { id &+= 1 }
        nextMessageID = id &+ 1
        command.messageID = id
        let queue = DICOMMessageQueue()
        responses[id] = queue
        do {
            try await send(DICOMMessage(presentationContextID: contextID, command: command, dataSet: dataSet))
        } catch {
            responses[id] = nil
            throw error
        }
        return (id, queue)
    }

    /// Asks the peer to cancel a C-FIND, C-GET, or C-MOVE (PS3.7 9.3.2.3).
    func cancel(messageID: UInt16, contextID: UInt8) async {
        guard responses[messageID] != nil, failure == nil else { return }
        var command = DICOMCommand(field: .cCancelRequest)
        command.messageIDBeingRespondedTo = messageID
        try? await send(DICOMMessage(presentationContextID: contextID, command: command))
    }

    /// Stops routing responses of an operation that no longer listens.
    func forget(messageID: UInt16) {
        responses.removeValue(forKey: messageID)?.abandon()
    }

    /// Whether a service should stop working on a peer request: the peer
    /// cancelled it, or it is no longer being performed (answered, or the
    /// association ended).
    func isCancelled(_ messageID: UInt16) -> Bool {
        performing[messageID] ?? true
    }

    /// Marks a peer request as performed; a pending release proceeds once
    /// none is left.
    func finishedPerforming(_ messageID: UInt16) async {
        performing[messageID] = nil
        guard performing.isEmpty else { return }
        resumeIdleWaiters()
        if releaseRequestedByPeer {
            await respondToRelease()
        }
    }

    private func resumeIdleWaiters() {
        let waiters = idleWaiters
        idleWaiters = []
        waiters.forEach { $0.resume() }
    }

    /// Whether new requests may still be sent: the association is
    /// established and the peer has not asked to release it.
    var acceptsRequests: Bool {
        failure == nil && machine.state == .established && !releaseRequestedByPeer
    }

    // MARK: Storage Commitment results

    func deliverCommitment(_ result: DICOMStorageCommitmentResult) {
        if let waiters = commitmentWaiters.removeValue(forKey: result.transactionUID) {
            waiters.forEach { $0.1.resume(returning: result) }
        } else if commitmentResults[result.transactionUID] == nil {
            commitmentResults[result.transactionUID] = result
        }
    }

    func commitmentResult(_ transactionUID: String, timeout: TimeAmount) async -> DICOMStorageCommitmentResult? {
        if let result = commitmentResults.removeValue(forKey: transactionUID) { return result }
        if failure != nil || machine.state == .idle { return nil }
        let token = nextWaiter
        nextWaiter += 1
        let expiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, timeout.nanoseconds)))
            await self?.expireCommitmentWaiter(transactionUID, token: token)
        }
        defer { expiry.cancel() }
        return await withCheckedContinuation { continuation in
            commitmentWaiters[transactionUID, default: []].append((token, continuation))
        }
    }

    private func expireCommitmentWaiter(_ transactionUID: String, token: UInt64) {
        guard var waiters = commitmentWaiters[transactionUID],
              let index = waiters.firstIndex(where: { $0.0 == token }) else { return }
        waiters.remove(at: index).1.resume(returning: nil)
        commitmentWaiters[transactionUID] = waiters.isEmpty ? nil : waiters
    }

    // MARK: Receiving

    /// Handles a received PDU; returns the peer requests to perform.
    func receive(_ pdu: DICOMPDU) async -> [DICOMMessage] {
        await perform(machine.handle(.init(received: pdu)))
    }

    /// The inbound stream failed: an invalid PDU, a timeout, or a transport
    /// error.
    func inboundFailed(_ error: Error) async {
        // Peers often close without a TLS close_notify; once the release
        // completed nothing can be truncated, so that is a normal close.
        if case NIOSSLError.uncleanShutdown? = error as? NIOSSLError, releaseConfirmed {
            await transportClosed()
            return
        }
        if let pduError = error as? DICOMPDUError {
            logger.warning("invalid PDU from \(remoteAddress): \(pduError.message)")
            fail(.protocolViolation(pduError.message))
            _ = await perform(machine.handle(.invalidPDU(pduError.reason)))
        } else if let networkError = error as? DICOMNetworkError {
            logger.warning("association with \(remoteAddress): \(networkError)")
            fail(networkError)
            await sendAbort()
        } else {
            // A TLS failure drops the connection (PS3.15 B.12): an A-P-ABORT
            // with DICOMNetworkError.tls as the provider reason.
            let networkError = DICOMNetworkError.from(error)
            if case .tls = networkError { logger.warning("association with \(remoteAddress): \(networkError)") }
            fail(networkError)
        }
        channel.close(promise: nil)
    }

    /// The transport closed.
    func transportClosed() async {
        _ = await perform(machine.handle(.transportClosed))
        if !releaseConfirmed { fail(.connectionClosed) }
        cancelARTIM()
    }

    private func perform(_ actions: [DICOMAssociationStateMachine.Action]) async -> [DICOMMessage] {
        var requests: [DICOMMessage] = []
        for action in actions {
            switch action {
            case .send(let pdu):
                try? await outbound.write(pdu)
            case .indicate(let indication):
                requests += await handle(indication)
            case .startARTIM:
                startARTIM()
            case .stopARTIM:
                cancelARTIM()
            case .closeTransport:
                channel.close(promise: nil)
            case .openTransport:
                break
            }
        }
        return requests
    }

    private func handle(_ indication: DICOMAssociationStateMachine.Indication) async -> [DICOMMessage] {
        switch indication {
        case .data(let values):
            var requests: [DICOMMessage] = []
            for value in values {
                do {
                    guard negotiated.presentationContexts[value.presentationContextID] != nil else {
                        throw DICOMPDUError(.invalidPDUParameterValue,
                                            "presentation context \(value.presentationContextID) was not accepted")
                    }
                    if let message = try assembler.append(value), let request = await route(message) {
                        requests.append(request)
                    }
                } catch let error as DICOMPDUError {
                    await abort(reason: error.reason, message: error.message)
                    return []
                } catch {
                    await abort(reason: .notSpecified, message: "\(error)")
                    return []
                }
            }
            return requests
        case .releaseRequested:
            releaseRequestedByPeer = true
            if role == .requestor || performing.isEmpty {
                await respondToRelease()
            }
            return []
        case .releaseConfirmed:
            releaseConfirmed = true
            releaseWaiter?.resume()
            releaseWaiter = nil
            if machine.state == .idle { finishQueues(throwing: nil) }
            return []
        case .aborted:
            fail(.associationAborted(DICOMAbort(source: .serviceUser)))
            return []
        case .providerAborted(let reason):
            fail(.associationAborted(DICOMAbort(source: .serviceProvider, reason: reason)))
            return []
        case .associateRequested, .associateAccepted, .associateRejected:
            return []
        }
    }

    /// Routes a message: responses to their operation, C-CANCEL to the
    /// request it cancels, other requests to the caller.
    private func route(_ message: DICOMMessage) async -> DICOMMessage? {
        let command = message.command
        if command.field.isResponse {
            guard let id = command.messageIDBeingRespondedTo, let queue = responses[id] else {
                logger.debug("ignoring \(command.field) for no pending request")
                return nil
            }
            let final = command.statusValue?.isPending != true
            if final { responses[id] = nil }
            await queue.push(message)
            if final { queue.finish() }
            return nil
        }
        if command.field == .cCancelRequest {
            if let id = command.messageIDBeingRespondedTo, performing[id] != nil { performing[id] = true }
            return nil
        }
        guard let id = command.messageID else {
            await abort(reason: .invalidPDUParameterValue, message: "\(command.field) without Message ID")
            return nil
        }
        guard performing[id] == nil else {
            await abort(reason: .invalidPDUParameterValue, message: "Message ID \(id) is already in use")
            return nil
        }
        guard performing.count < maximumPerforming else {
            await abort(reason: .unexpectedPDU, message: "more operations than the asynchronous window allows")
            return nil
        }
        performing[id] = false
        return message
    }

    // MARK: Release and abort

    /// Releases the association (requestor side, PS3.8 7.2): no message
    /// may start once the A-RELEASE-RQ is sent.
    func release() async throws {
        // Peer requests being performed are answered first: a C-STORE of a
        // C-GET, or an N-EVENT-REPORT whose result the caller already has.
        while !performing.isEmpty, failure == nil {
            await withCheckedContinuation { idleWaiters.append($0) }
        }
        if let failure { throw failure }
        await acquireSend()
        guard machine.state == .established else {
            releaseSend()
            throw DICOMNetworkError.invalidState("cannot release in state \(machine.state)")
        }
        _ = await perform(machine.handle(.releaseRequestPrimitive))
        // The peer has ARTIM to answer.
        startARTIM()
        releaseSend()
        if releaseConfirmed { return }
        if let failure { throw failure }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            releaseWaiter = continuation
        }
    }

    private func respondToRelease() async {
        releaseRequestedByPeer = false
        _ = await perform(machine.handle(.releaseResponsePrimitive))
        if machine.state == .awaitingTransportClose || machine.state == .idle {
            releaseConfirmed = true
            finishQueues(throwing: nil)
        }
    }

    /// Aborts the association as the service user (A-ABORT) and closes the
    /// connection.
    func abort() async {
        guard failure == nil, machine.state != .idle else { return }
        fail(.associationAborted(DICOMAbort(source: .serviceUser)))
        _ = await perform(machine.handle(.abortRequestPrimitive))
        channel.close(promise: nil)
    }

    private func abort(reason: DICOMAbort.Reason, message: String) async {
        logger.warning("aborting association with \(remoteAddress): \(message)")
        fail(.protocolViolation(message))
        _ = await perform(machine.handle(.invalidPDU(reason)))
        channel.close(promise: nil)
    }

    private func sendAbort() async {
        guard machine.state != .idle, machine.state != .awaitingTransportClose else { return }
        try? await outbound.write(.abort(DICOMAbort(source: .serviceProvider, reason: .notSpecified)))
    }

    private func fail(_ error: DICOMNetworkError) {
        guard failure == nil, !releaseConfirmed || error != .connectionClosed else { return }
        failure = error
        finishQueues(throwing: error)
        releaseWaiter?.resume(throwing: error)
        releaseWaiter = nil
        resumeIdleWaiters()
        // Pending senders proceed and see the failure.
        let waiters = sendWaiters
        sendWaiters = []
        sending = false
        waiters.forEach { $0.resume() }
    }

    private func finishQueues(throwing error: Error?) {
        let queues = responses.values
        responses = [:]
        for queue in queues { queue.finish(throwing: error ?? DICOMNetworkError.connectionClosed) }
        // No result can arrive any more.
        let waiters = commitmentWaiters.values.joined()
        commitmentWaiters = [:]
        for (_, waiter) in waiters { waiter.resume(returning: nil) }
    }

    // MARK: ARTIM

    private func startARTIM() {
        cancelARTIM()
        let channel = self.channel
        artim = channel.eventLoop.scheduleTask(in: timeouts.artim) {
            channel.close(promise: nil)
        }
    }

    private func cancelARTIM() {
        artim?.cancel()
        artim = nil
    }

    /// Whether the association reached its end.
    var isFinished: Bool { machine.state == .idle }
}
