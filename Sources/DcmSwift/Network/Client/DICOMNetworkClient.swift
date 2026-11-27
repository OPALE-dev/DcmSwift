import Foundation
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import NIOSSL

/// Settings of an association requestor.
public struct DICOMClientConfiguration: Sendable {
    public var aeTitle: String
    public var limits: DICOMNetworkLimits
    public var timeouts: DICOMNetworkTimeouts
    /// TLS for remote nodes that use it.
    public var tls: DICOMTLSConfiguration?
    /// Operations this side may invoke asynchronously; 1 disables
    /// asynchronous operations (PS3.7 D.3.3.3).
    public var maximumOperationsInvoked: UInt16
    public var logger: Logging.Logger
    /// Announced in the association requests.
    public var implementation: DICOMImplementationIdentity
    /// Given each PDU sent and received, with its bytes (PS3.8 9.3).
    public var pduTrace: DICOMPDUTrace?

    public init(
        aeTitle: String, limits: DICOMNetworkLimits = DICOMNetworkLimits(),
        timeouts: DICOMNetworkTimeouts = DICOMNetworkTimeouts(), tls: DICOMTLSConfiguration? = nil,
        maximumOperationsInvoked: UInt16 = 1, logger: Logging.Logger = Logging.Logger(label: "DcmSwift.network.client"),
        implementation: DICOMImplementationIdentity = .dcmSwift, pduTrace: DICOMPDUTrace? = nil
    ) {
        self.pduTrace = pduTrace
        self.implementation = implementation
        self.aeTitle = aeTitle
        self.limits = limits
        self.timeouts = timeouts
        self.tls = tls
        self.maximumOperationsInvoked = maximumOperationsInvoked
        self.logger = logger
    }
}

extension DICOMPresentationContextProposal {
    /// One context per abstract syntax, with odd IDs from 1.
    public static func proposals(
        abstractSyntaxes: [String],
        transferSyntaxes: [String] = [TransferSyntax.explicitVRLittleEndian, TransferSyntax.implicitVRLittleEndian]
    ) -> [DICOMPresentationContextProposal] {
        abstractSyntaxes.prefix(128).enumerated().map { index, uid in
            DICOMPresentationContextProposal(id: UInt8(2 * index + 1), abstractSyntax: uid, transferSyntaxes: transferSyntaxes)
        }
    }
}

extension DICOMPresentationContextProposal {
    /// Contexts to send these instances: for each SOP class, one context
    /// per compressed transfer syntax among them, alone so that the
    /// acceptor cannot choose another, and one for the uncompressed
    /// syntaxes, to which uncompressed instances convert. At most 128.
    ///
    /// - Parameter uncompressed: the uncompressed transfer syntaxes proposed,
    ///   in order of preference; one alone sends every uncompressed instance
    ///   in it, converted if need be.
    public static func proposals(
        for items: [DICOMRetrieveItem], uncompressed: [String] = DICOMTransferSyntaxes.uncompressed
    ) -> [DICOMPresentationContextProposal] {
        Array(contexts(for: items, uncompressed: uncompressed).prefix(128))
    }

    /// Compressed syntaxes a C-GET accepts besides the uncompressed ones, most
    /// used first: an SCP that does not transcode sends an instance only in
    /// the syntax it keeps it in.
    public static let retrieveCompressed = [
        "1.2.840.10008.1.2.4.50", "1.2.840.10008.1.2.4.70", "1.2.840.10008.1.2.4.90", "1.2.840.10008.1.2.4.91",
        "1.2.840.10008.1.2.5", "1.2.840.10008.1.2.4.80", "1.2.840.10008.1.2.4.51", "1.2.840.10008.1.2.4.81",
        "1.2.840.10008.1.2.4.57", "1.2.840.10008.1.2.1.99",
    ]

    /// The contexts of a C-GET (PS3.4 C.4.3): the retrieve model first; then,
    /// for each storage SOP class, one context for the uncompressed syntaxes
    /// and one per compressed syntax, alone, so that the SCP may send each
    /// instance as it keeps it. Within 128 contexts (PS3.8 9.3.2.2), the
    /// first classes keep every compressed syntax and the last ones lose
    /// them first; the classes beyond 127 are left out. The role selections
    /// ask the SCP role for each class proposed (PS3.7 D.3.3.4).
    public static func getProposals(
        informationModel: String, sopClasses: [String], uncompressed: [String] = DICOMTransferSyntaxes.uncompressed,
        compressed: [String] = retrieveCompressed
    ) -> (proposals: [DICOMPresentationContextProposal], roles: [DICOMRoleSelection]) {
        var classes: [String] = []
        for uid in sopClasses where !classes.contains(uid) { classes.append(uid) }
        classes = Array(classes.prefix(127))
        var budget = 127 - classes.count
        var contexts = [DICOMPresentationContextProposal(id: 0, abstractSyntax: informationModel, transferSyntaxes: uncompressed)]
        for sopClass in classes {
            contexts.append(DICOMPresentationContextProposal(id: 0, abstractSyntax: sopClass, transferSyntaxes: uncompressed))
            for syntax in compressed where budget > 0 {
                contexts.append(DICOMPresentationContextProposal(id: 0, abstractSyntax: sopClass, transferSyntaxes: [syntax]))
                budget -= 1
            }
        }
        let proposals = contexts.enumerated().map { index, proposal in
            var proposal = proposal
            proposal.id = UInt8(truncatingIfNeeded: 2 * index + 1)
            return proposal
        }
        return (proposals, classes.map { DICOMRoleSelection(sopClassUID: $0, scuRole: false, scpRole: true) })
    }

    /// The items in consecutive batches whose contexts fit in one
    /// association (128 presentation contexts, PS3.8 9.3.2.2).
    public static func batches(for items: [DICOMRetrieveItem], limit: Int = 128) -> [[DICOMRetrieveItem]] {
        var batches: [[DICOMRetrieveItem]] = []
        var batch: [DICOMRetrieveItem] = []
        var needed: Set<String> = []
        for item in items {
            var keys = ["\(item.sopClassUID) *"]
            if !DICOMAssociation.isUncompressed(item.transferSyntaxUID) {
                keys.append("\(item.sopClassUID) \(item.transferSyntaxUID)")
            }
            let added = keys.filter { !needed.contains($0) }
            if needed.count + added.count > limit, !batch.isEmpty {
                batches.append(batch)
                batch = []
                needed = []
                keys.forEach { needed.insert($0) }
            } else {
                added.forEach { needed.insert($0) }
            }
            batch.append(item)
        }
        if !batch.isEmpty { batches.append(batch) }
        return batches
    }

    /// Every context the items need, with odd IDs.
    static func contexts(
        for items: [DICOMRetrieveItem], uncompressed: [String] = DICOMTransferSyntaxes.uncompressed
    ) -> [DICOMPresentationContextProposal] {
        var order: [String] = []
        var compressed: [String: [String]] = [:]
        for item in items {
            if compressed[item.sopClassUID] == nil {
                order.append(item.sopClassUID)
                compressed[item.sopClassUID] = []
            }
            if !DICOMAssociation.isUncompressed(item.transferSyntaxUID),
               !compressed[item.sopClassUID]!.contains(item.transferSyntaxUID) {
                compressed[item.sopClassUID]!.append(item.transferSyntaxUID)
            }
        }
        var proposals: [DICOMPresentationContextProposal] = []
        for sopClass in order {
            for syntax in compressed[sopClass]! {
                proposals.append(DICOMPresentationContextProposal(id: 0, abstractSyntax: sopClass, transferSyntaxes: [syntax]))
            }
            proposals.append(DICOMPresentationContextProposal(
                id: 0, abstractSyntax: sopClass, transferSyntaxes: uncompressed))
        }
        return proposals.enumerated().map { index, proposal in
            var proposal = proposal
            proposal.id = UInt8(truncatingIfNeeded: 2 * index + 1)
            return proposal
        }
    }
}

extension Array where Element == DICOMPresentationContextProposal {
    /// One context per abstract syntax, with odd IDs from 1.
    public static func proposals(
        abstractSyntaxes: [String],
        transferSyntaxes: [String] = [TransferSyntax.explicitVRLittleEndian, TransferSyntax.implicitVRLittleEndian]
    ) -> [DICOMPresentationContextProposal] {
        DICOMPresentationContextProposal.proposals(abstractSyntaxes: abstractSyntaxes, transferSyntaxes: transferSyntaxes)
    }
}

/// An association requestor (SCU). Associations live within the scope of
/// `withAssociation`, which releases them, or aborts them on error, and
/// always closes the connection.
public final class DICOMClient: Sendable {
    public let configuration: DICOMClientConfiguration
    private let group: EventLoopGroup
    private let sslContext: NIOSSLContext?

    public init(
        configuration: DICOMClientConfiguration, eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup.singleton
    ) throws {
        self.configuration = configuration
        group = eventLoopGroup
        sslContext = try configuration.tls.map { try NIOSSLContext(configuration: $0.configuration) }
    }

    /// Opens an association, runs `body`, then releases it.
    ///
    /// - Parameters:
    ///   - remote: the called Application Entity and network endpoint.
    ///   - presentationContexts: abstract and transfer syntaxes to propose.
    ///   - roleSelections: SCP roles to propose, for C-GET.
    ///   - extendedNegotiations: SOP Class Extended Negotiation items to
    ///     propose.
    ///   - commonExtendedNegotiations: SOP Class Common Extended Negotiation
    ///     items to propose.
    ///   - userIdentity: optional user identity negotiation item.
    ///   - storage: receives the C-STORE requests of C-GET sub-operations.
    ///   - normalized: receives DIMSE-N requests and notifications from the
    ///     acceptor, by SOP Class UID.
    ///   - body: asynchronous work to run on the established association.
    public func withAssociation<Result>(
        to remote: DICOMRemoteNode, presentationContexts: [DICOMPresentationContextProposal],
        roleSelections: [DICOMRoleSelection] = [], extendedNegotiations: [DICOMExtendedNegotiation] = [],
        commonExtendedNegotiations: [DICOMCommonExtendedNegotiation] = [], userIdentity: DICOMUserIdentity? = nil,
        storage: DICOMStorageService? = nil, normalized: [String: DICOMNormalizedService] = [:],
        _ body: (DICOMAssociation) async throws -> Result
    ) async throws -> Result {
        if remote.useTLS, remote.tls == nil, sslContext == nil {
            throw DICOMNetworkError.invalidState("\(remote.aeTitle) uses TLS but the client has no TLS configuration")
        }
        let configuration = self.configuration
        let window = configuration.maximumOperationsInvoked == 1
            ? nil : DICOMAsynchronousOperationsWindow(maximumInvoked: configuration.maximumOperationsInvoked, maximumPerformed: 1)
        let request = DICOMAssociateRequest(
            calledAETitle: remote.aeTitle, callingAETitle: configuration.aeTitle,
            presentationContexts: presentationContexts,
            userInformation: DICOMUserInformation(
                maximumLength: configuration.limits.maximumPDULength,
                implementationClassUID: configuration.implementation.classUID,
                implementationVersionName: configuration.implementation.versionName,
                asynchronousOperationsWindow: window, roleSelections: roleSelections, extendedNegotiations: extendedNegotiations,
                commonExtendedNegotiations: commonExtendedNegotiations, userIdentity: userIdentity))
        // Invalid AE titles or UIDs fail before connecting.
        _ = try DICOMPDUCodec.encode(.associateRequest(request))

        // The node's own configuration first, else the client's.
        let tls = try remote.tls.map { try NIOSSLContext(configuration: $0.configuration) } ?? (remote.useTLS ? sslContext : nil)
        let hostname = (try? SocketAddress(ipAddress: remote.host, port: remote.port)) == nil ? remote.host : nil
        let asyncChannel: DICOMChannel.Async
        do {
            asyncChannel = try await ClientBootstrap(group: group)
                .connectTimeout(configuration.timeouts.connect)
                .channelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)
                .connect(host: remote.host, port: remote.port) { channel in
                    channel.eventLoop.makeCompletedFuture {
                        try DICOMChannel.configure(
                            channel, tls: tls, serverHostname: hostname, isServer: false,
                            limits: configuration.limits, timeouts: configuration.timeouts,
                            trace: configuration.pduTrace)
                    }
                }
        } catch let error as ChannelError where error == .connectTimeout(configuration.timeouts.connect) {
            throw DICOMNetworkError.timeout("connecting to \(remote.host):\(remote.port)")
        }

        let channel = asyncChannel.channel
        let dispatcher = DICOMRequestDispatcher(verification: false, storage: storage, normalized: normalized)
        return try await asyncChannel.executeThenClose { inbound, outbound in
            let established = DICOMEstablishment()
            return try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    await Self.read(
                        inbound: inbound, outbound: outbound, channel: channel, request: request,
                        configuration: configuration, dispatcher: dispatcher, established: established)
                }
                let association: DICOMAssociation
                do {
                    association = try await established.value()
                } catch {
                    group.cancelAll()
                    throw error
                }
                do {
                    let result = try await body(association)
                    try await association.runtime.release()
                    try await group.waitForAll()
                    return result
                } catch {
                    await association.runtime.abort()
                    group.cancelAll()
                    throw error
                }
            }
        }
    }

    /// Establishes the association, then serves it until it ends.
    private static func read(
        inbound: NIOAsyncChannelInboundStream<DICOMPDU>, outbound: NIOAsyncChannelOutboundWriter<DICOMPDU>,
        channel: Channel, request: DICOMAssociateRequest, configuration: DICOMClientConfiguration,
        dispatcher: DICOMRequestDispatcher, established: DICOMEstablishment
    ) async {
        var iterator = inbound.makeAsyncIterator()
        var machine = DICOMAssociationStateMachine(role: .requestor)
        _ = machine.handle(.associateRequestPrimitive(request))
        _ = machine.handle(.transportConnectConfirm)
        do {
            try await outbound.write(.associateRequest(request))
        } catch {
            established.fail(DICOMNetworkError.from(error))
            return
        }

        // The acceptor has ARTIM to answer.
        let timedOut = NIOLockedValueBox(false)
        let timer = channel.eventLoop.scheduleTask(in: configuration.timeouts.artim) {
            timedOut.withLockedValue { $0 = true }
            channel.close(promise: nil)
        }
        let first: DICOMPDU?
        do {
            first = try await iterator.next()
        } catch {
            timer.cancel()
            channel.close(promise: nil)
            established.fail(DICOMNetworkError.from(error))
            return
        }
        timer.cancel()
        guard let first else {
            established.fail(timedOut.withLockedValue { $0 }
                ? DICOMNetworkError.timeout("no answer to the A-ASSOCIATE-RQ") : DICOMNetworkError.connectionClosed)
            return
        }

        let actions = machine.handle(.init(received: first))
        switch first {
        case .associateAccept(let accept):
            guard machine.state == .established,
                  let negotiated = try? DICOMAssociationNegotiator.negotiated(request: request, accept: accept) else {
                try? await outbound.write(.abort(DICOMAbort(source: .serviceProvider, reason: .invalidPDUParameterValue)))
                channel.close(promise: nil)
                established.fail(DICOMNetworkError.protocolViolation("the A-ASSOCIATE-AC does not match the request"))
                return
            }
            let runtime = DICOMAssociationRuntime(
                machine: machine, negotiated: negotiated, outbound: outbound, channel: channel,
                limits: configuration.limits, timeouts: configuration.timeouts, logger: configuration.logger,
                peerCertificate: await DICOMChannel.peerCertificate(of: channel))
            let association = DICOMAssociation(runtime: runtime)
            established.succeed(association)
            await DICOMAssociationRuntime.serve(
                runtime: runtime, association: association, iterator: &iterator, dispatcher: dispatcher)
        case .associateReject(let reject):
            channel.close(promise: nil)
            established.fail(DICOMNetworkError.associationRejected(reject))
        case .abort(let abort):
            channel.close(promise: nil)
            established.fail(DICOMNetworkError.associationAborted(abort))
        default:
            for case .send(let pdu) in actions { try? await outbound.write(pdu) }
            channel.close(promise: nil)
            established.fail(DICOMNetworkError.protocolViolation("unexpected PDU before the A-ASSOCIATE-AC"))
        }
    }
}

/// The outcome of association establishment, set once by the reader.
final class DICOMEstablishment: @unchecked Sendable {
    private let state = NIOLockedValueBox<(Result<DICOMAssociation, Error>?, CheckedContinuation<DICOMAssociation, Error>?)>((nil, nil))

    func succeed(_ association: DICOMAssociation) { resolve(.success(association)) }
    func fail(_ error: Error) { resolve(.failure(error)) }

    private func resolve(_ result: Result<DICOMAssociation, Error>) {
        let waiter = state.withLockedValue { state -> CheckedContinuation<DICOMAssociation, Error>? in
            guard state.0 == nil else { return nil }
            state.0 = result
            defer { state.1 = nil }
            return state.1
        }
        waiter?.resume(with: result)
    }

    func value() async throws -> DICOMAssociation {
        try await withCheckedThrowingContinuation { continuation in
            let result = state.withLockedValue { state -> Result<DICOMAssociation, Error>? in
                if let result = state.0 { return result }
                state.1 = continuation
                return nil
            }
            if let result { continuation.resume(with: result) }
        }
    }
}

extension DICOMAssociationRuntime {
    /// Reads PDUs until the association ends, performing peer requests
    /// concurrently within the asynchronous operations window.
    static func serve(
        runtime: DICOMAssociationRuntime, association: DICOMAssociation,
        iterator: inout NIOAsyncChannelInboundStream<DICOMPDU>.AsyncIterator, dispatcher: DICOMRequestDispatcher
    ) async {
        await withTaskGroup(of: Void.self) { handlers in
            var running = 0
            do {
                while let pdu = try await iterator.next() {
                    for request in await runtime.receive(pdu) {
                        // Finished handlers are collected so that a long
                        // association does not accumulate them. The runtime
                        // admits at most `maximumPerforming` unfinished
                        // requests, so this waits only for finished ones and
                        // never for a handler awaiting this reader.
                        while running > runtime.maximumPerforming + 1 {
                            _ = await handlers.next()
                            running -= 1
                        }
                        running += 1
                        handlers.addTask { await dispatcher.perform(request, on: association) }
                    }
                }
                if Task.isCancelled { await runtime.abort() }
                await runtime.transportClosed()
            } catch {
                if Task.isCancelled || error is CancellationError {
                    await runtime.abort()
                } else {
                    await runtime.inboundFailed(error)
                }
            }
            handlers.cancelAll()
        }
    }
}
