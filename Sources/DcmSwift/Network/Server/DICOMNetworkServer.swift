import Foundation
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import NIOSSL

/// Settings of an association acceptor.
public struct DICOMServerConfiguration: Sendable {
    public var aeTitle: String
    public var host: String
    /// 0 binds an ephemeral port, reported by `run(onBound:)`.
    public var port: Int
    /// Also accept associations addressed to another called AE title.
    public var acceptsAnyCalledAETitle: Bool
    /// Calling AE titles allowed; nil allows any.
    public var allowedCallingAETitles: Set<String>?
    /// Associations served at once; more are rejected (transient, local
    /// limit exceeded).
    public var maximumAssociations: Int
    public var limits: DICOMNetworkLimits
    public var timeouts: DICOMNetworkTimeouts
    /// TLS for incoming connections.
    public var tls: DICOMTLSConfiguration?
    /// TLS for C-MOVE destinations that use it.
    public var clientTLS: DICOMTLSConfiguration?
    /// Transfer syntaxes of the verification and query/retrieve contexts.
    public var transferSyntaxes: [String]
    /// Transfer syntaxes accepted for storage; instances are kept as sent.
    public var storageTransferSyntaxes: [String]
    public var storageSOPClasses: [String]
    /// Requests performed at once on an association (PS3.7 D.3.3.3).
    public var maximumOperationsPerformed: UInt16
    /// Decides on the user identity (see `DICOMAcceptorPolicy`).
    public var authenticate: (@Sendable (DICOMUserIdentity?) -> [UInt8]?)?
    public var logger: Logging.Logger

    public init(
        aeTitle: String, host: String = "0.0.0.0", port: Int = 11112, acceptsAnyCalledAETitle: Bool = false,
        allowedCallingAETitles: Set<String>? = nil, maximumAssociations: Int = 32,
        limits: DICOMNetworkLimits = DICOMNetworkLimits(), timeouts: DICOMNetworkTimeouts = DICOMNetworkTimeouts(),
        tls: DICOMTLSConfiguration? = nil, clientTLS: DICOMTLSConfiguration? = nil,
        transferSyntaxes: [String] = DICOMTransferSyntaxes.uncompressed,
        storageTransferSyntaxes: [String] = DICOMTransferSyntaxes.storage,
        storageSOPClasses: [String] = DICOMSOPClass.allStorage, maximumOperationsPerformed: UInt16 = 1,
        authenticate: (@Sendable (DICOMUserIdentity?) -> [UInt8]?)? = nil,
        logger: Logging.Logger = Logging.Logger(label: "DcmSwift.network.server")
    ) {
        self.aeTitle = aeTitle
        self.host = host
        self.port = port
        self.acceptsAnyCalledAETitle = acceptsAnyCalledAETitle
        self.allowedCallingAETitles = allowedCallingAETitles
        self.maximumAssociations = maximumAssociations
        self.limits = limits
        self.timeouts = timeouts
        self.tls = tls
        self.clientTLS = clientTLS
        self.transferSyntaxes = transferSyntaxes
        self.storageTransferSyntaxes = storageTransferSyntaxes
        self.storageSOPClasses = storageSOPClasses
        self.maximumOperationsPerformed = maximumOperationsPerformed
        self.authenticate = authenticate
        self.logger = logger
    }
}

/// An association acceptor for verification, storage, query, retrieval,
/// Storage Commitment, and DIMSE-N services. `run` serves until its task is
/// cancelled; each association runs in its own child task, so a failing
/// peer never affects others.
public final class DICOMServer: Sendable {
    public let configuration: DICOMServerConfiguration
    private let group: EventLoopGroup
    private let sslContext: NIOSSLContext?
    private let dispatcher: DICOMRequestDispatcher
    private let policy: DICOMAcceptorPolicy
    private let active = NIOLockedValueBox(0)

    /// - Parameters:
    ///   - storageCommitment: the Storage Commitment SCP.
    ///   - storageCommitmentReceiver: receives Storage Commitment results as
    ///     the SCU, from SCPs that answer on a new association.
    ///   - normalized: DIMSE-N services by SOP Class (or Meta SOP Class) UID.
    public init(
        configuration: DICOMServerConfiguration, storage: DICOMStorageService? = nil,
        query: DICOMQueryService? = nil, retrieve: DICOMRetrieveService? = nil,
        storageCommitment: DICOMStorageCommitmentService? = nil,
        storageCommitmentReceiver: DICOMStorageCommitmentReceiver? = nil,
        normalized: [String: DICOMNormalizedService] = [:],
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup.singleton
    ) throws {
        self.configuration = configuration
        group = eventLoopGroup
        sslContext = try configuration.tls.map { try NIOSSLContext(configuration: $0.configuration) }
        let outgoingClient = retrieve == nil && storageCommitment == nil ? nil : try DICOMClient(
            configuration: DICOMClientConfiguration(
                aeTitle: configuration.aeTitle, limits: configuration.limits, timeouts: configuration.timeouts,
                tls: configuration.clientTLS, logger: configuration.logger),
            eventLoopGroup: eventLoopGroup)
        dispatcher = DICOMRequestDispatcher(
            verification: true, storage: storage, query: query, retrieve: retrieve, normalized: normalized,
            storageCommitment: storageCommitment, commitmentReceiver: storageCommitmentReceiver,
            outgoingClient: outgoingClient)

        var syntaxes: [String: DICOMAbstractSyntaxSupport] = [
            DICOMSOPClass.verification: DICOMAbstractSyntaxSupport(transferSyntaxes: configuration.transferSyntaxes),
        ]
        if storage != nil || retrieve != nil {
            // Storage contexts: received as SCP, or sent as SCU for C-GET.
            for sopClass in configuration.storageSOPClasses {
                syntaxes[sopClass] = DICOMAbstractSyntaxSupport(
                    transferSyntaxes: configuration.storageTransferSyntaxes, scpRole: storage != nil,
                    scuRole: retrieve != nil, prefersProposedOrder: true)
            }
        }
        if query != nil {
            for model in [DICOMSOPClass.patientRootFind, DICOMSOPClass.studyRootFind, DICOMSOPClass.patientStudyOnlyFind] {
                syntaxes[model] = DICOMAbstractSyntaxSupport(transferSyntaxes: configuration.transferSyntaxes)
            }
        }
        if retrieve != nil {
            for model in [DICOMSOPClass.patientRootMove, DICOMSOPClass.studyRootMove, DICOMSOPClass.patientStudyOnlyMove,
                          DICOMSOPClass.compositeInstanceRootMove, DICOMSOPClass.patientRootGet,
                          DICOMSOPClass.studyRootGet, DICOMSOPClass.patientStudyOnlyGet,
                          DICOMSOPClass.compositeInstanceRootGet] {
                syntaxes[model] = DICOMAbstractSyntaxSupport(transferSyntaxes: configuration.transferSyntaxes)
            }
        }
        // DIMSE-N: this side performs operations, and receives notifications
        // from requestors granted the SCP role.
        for sopClass in normalized.keys {
            syntaxes[sopClass] = DICOMAbstractSyntaxSupport(
                transferSyntaxes: configuration.transferSyntaxes, scpRole: true, scuRole: true)
        }
        if storageCommitment != nil || storageCommitmentReceiver != nil {
            // A receiver also accepts SCPs that send results without
            // proposing their role (PS3.4 J.3.3.2 requires it).
            syntaxes[DICOMSOPClass.storageCommitmentPushModel] = DICOMAbstractSyntaxSupport(
                transferSyntaxes: configuration.transferSyntaxes, scpRole: true,
                scuRole: storageCommitmentReceiver != nil)
        }
        policy = DICOMAcceptorPolicy(
            aeTitle: configuration.aeTitle, abstractSyntaxes: syntaxes,
            acceptsAnyCalledAETitle: configuration.acceptsAnyCalledAETitle,
            allowedCallingAETitles: configuration.allowedCallingAETitles,
            maximumLength: configuration.limits.maximumPDULength,
            maximumOperationsPerformed: configuration.maximumOperationsPerformed,
            authenticate: configuration.authenticate)
    }

    /// The number of associations being served.
    public var activeAssociations: Int { active.withLockedValue { $0 } }

    /// Binds and serves until the task is cancelled. `onBound` receives the
    /// bound port once connections are accepted.
    public func run(onBound: (@Sendable (Int) -> Void)? = nil) async throws {
        let configuration = self.configuration
        let sslContext = self.sslContext
        let server = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
            .childChannelOption(ChannelOptions.socketOption(.so_keepalive), value: 1)
            .bind(host: configuration.host, port: configuration.port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try DICOMChannel.configure(
                        channel, tls: sslContext, serverHostname: nil, isServer: true,
                        limits: configuration.limits, timeouts: configuration.timeouts)
                }
            }
        let port = server.channel.localAddress?.port ?? configuration.port
        configuration.logger.info("\(configuration.aeTitle) listening on \(configuration.host):\(port)")
        onBound?(port)

        try await server.executeThenClose { connections in
            if #available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *) {
                try await withThrowingDiscardingTaskGroup { group in
                    for try await connection in connections {
                        group.addTask { await self.serve(connection) }
                    }
                }
            } else {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    // Finished tasks are collected as connections arrive, so
                    // that a long-running server does not accumulate them.
                    var spawned = 0
                    for try await connection in connections {
                        while spawned >= 2 * configuration.maximumAssociations + 1 {
                            _ = try await group.next()
                            spawned -= 1
                        }
                        spawned += 1
                        group.addTask { await self.serve(connection) }
                    }
                }
            }
        }
    }

    /// Serves one connection; never throws.
    private func serve(_ connection: DICOMChannel.Async) async {
        let logger = configuration.logger
        let peer = connection.channel.remoteAddress?.description ?? "unknown"
        let admitted = active.withLockedValue { count -> Bool in
            count += 1
            return count <= configuration.maximumAssociations
        }
        defer { active.withLockedValue { $0 -= 1 } }
        do {
            try await connection.executeThenClose { inbound, outbound in
                try await self.associate(
                    inbound: inbound, outbound: outbound, channel: connection.channel, admitted: admitted)
            }
        } catch {
            logger.debug("connection from \(peer) ended: \(error)")
        }
    }

    private func associate(
        inbound: NIOAsyncChannelInboundStream<DICOMPDU>, outbound: NIOAsyncChannelOutboundWriter<DICOMPDU>,
        channel: Channel, admitted: Bool
    ) async throws {
        let configuration = self.configuration
        let logger = configuration.logger
        var iterator = inbound.makeAsyncIterator()
        var machine = DICOMAssociationStateMachine(role: .acceptor)
        _ = machine.handle(.transportConnectIndication)

        // ARTIM: the requestor must send its A-ASSOCIATE-RQ in time.
        let artim = channel.eventLoop.scheduleTask(in: configuration.timeouts.artim) { channel.close(promise: nil) }
        let first: DICOMPDU?
        do {
            first = try await iterator.next()
        } catch let error as DICOMPDUError {
            artim.cancel()
            try? await outbound.write(.abort(DICOMAbort(source: .serviceUser)))
            throw error
        }
        artim.cancel()
        guard let first else { return }

        let actions = machine.handle(.init(received: first))
        guard case .associateRequest(let request) = first, machine.state == .awaitingLocalAssociateResponse else {
            for case .send(let pdu) in actions { try? await outbound.write(pdu) }
            await Self.awaitClose(&iterator, channel: channel, artim: configuration.timeouts.artim)
            return
        }

        let answer: Result<(DICOMAssociateAccept, DICOMNegotiatedAssociation), DICOMAssociateReject> = admitted
            ? DICOMAssociationNegotiator.respond(to: request, policy: policy)
            : .failure(DICOMAssociateReject(result: .transient, reason: .localLimitExceeded))
        switch answer {
        case .failure(let reject):
            logger.info("rejecting \(request.callingAETitle) at \(channel.remoteAddress?.description ?? "?"): \(reject.reason)")
            for case .send(let pdu) in machine.handle(.associateRejectPrimitive(reject)) { try? await outbound.write(pdu) }
            await Self.awaitClose(&iterator, channel: channel, artim: configuration.timeouts.artim)
        case .success(let (accept, negotiated)):
            for case .send(let pdu) in machine.handle(.associateAcceptPrimitive(accept)) { try await outbound.write(pdu) }
            logger.info("association with \(request.callingAETitle) at \(channel.remoteAddress?.description ?? "?"): \(negotiated.presentationContexts.count) contexts")
            let runtime = DICOMAssociationRuntime(
                machine: machine, negotiated: negotiated, outbound: outbound, channel: channel,
                limits: configuration.limits, timeouts: configuration.timeouts, logger: logger,
                peerCertificate: await DICOMChannel.peerCertificate(of: channel))
            await DICOMAssociationRuntime.serve(
                runtime: runtime, association: DICOMAssociation(runtime: runtime), iterator: &iterator,
                dispatcher: dispatcher)
        }
    }

    /// Waits for the peer to close after a rejection or abort, at most ARTIM.
    private static func awaitClose(
        _ iterator: inout NIOAsyncChannelInboundStream<DICOMPDU>.AsyncIterator, channel: Channel, artim: TimeAmount
    ) async {
        let timer = channel.eventLoop.scheduleTask(in: artim) { channel.close(promise: nil) }
        while (try? await iterator.next()) != nil {}
        timer.cancel()
    }
}
