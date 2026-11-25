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
    /// Decides on the calling AE title of each new association, after
    /// `allowedCallingAETitles`; it may follow a list that changes while the
    /// server runs (see `DICOMAcceptorPolicy.acceptsCallingAETitle`).
    public var acceptsCallingAETitle: (@Sendable (String) -> Bool)?
    /// Decides on each new association from its AE titles and the
    /// requestor's IP address, after `acceptsCallingAETitle`; a refusal is
    /// a permanent rejection, reason calling-AE-title-not-recognized (see
    /// `DICOMAcceptorPolicy.acceptsAssociation`). nil accepts every request.
    public var acceptsAssociation: (@Sendable (DICOMAssociationCandidate) -> Bool)?
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
    /// Receives Security Alert messages for rejected associations and User
    /// Authentication messages for user identities (PS3.15 A.5.3).
    public var audit: DICOMAuditRecorder?
    public var auditSource: DICOMAuditSource?
    public var logger: Logging.Logger
    /// Announced in accepted associations and in those the server opens.
    public var implementation: DICOMImplementationIdentity = .dcmSwift

    public init(
        aeTitle: String, host: String = "0.0.0.0", port: Int = 11112, acceptsAnyCalledAETitle: Bool = false,
        allowedCallingAETitles: Set<String>? = nil, maximumAssociations: Int = 32,
        limits: DICOMNetworkLimits = DICOMNetworkLimits(), timeouts: DICOMNetworkTimeouts = DICOMNetworkTimeouts(),
        tls: DICOMTLSConfiguration? = nil, clientTLS: DICOMTLSConfiguration? = nil,
        transferSyntaxes: [String] = DICOMTransferSyntaxes.uncompressed,
        storageTransferSyntaxes: [String] = DICOMTransferSyntaxes.storage,
        storageSOPClasses: [String] = DICOMSOPClass.allStorage, maximumOperationsPerformed: UInt16 = 1,
        authenticate: (@Sendable (DICOMUserIdentity?) -> [UInt8]?)? = nil,
        audit: DICOMAuditRecorder? = nil, auditSource: DICOMAuditSource? = nil,
        logger: Logging.Logger = Logging.Logger(label: "DcmSwift.network.server"),
        acceptsCallingAETitle: (@Sendable (String) -> Bool)? = nil,
        acceptsAssociation: (@Sendable (DICOMAssociationCandidate) -> Bool)? = nil
    ) {
        self.aeTitle = aeTitle
        self.acceptsCallingAETitle = acceptsCallingAETitle
        self.acceptsAssociation = acceptsAssociation
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
        self.audit = audit
        self.auditSource = auditSource
        self.logger = logger
    }
}

/// An association acceptor for verification, storage, query, retrieval,
/// Storage Commitment, and DIMSE-N services. `run` serves until its task is
/// cancelled; each association runs in its own child task, so a failing
/// peer never affects others.
/// The services an acceptor offers, as negotiation sees them.
public struct DICOMOfferedServices: Sendable, Equatable {
    public var storage: Bool
    /// Query/Retrieve FIND models, with the extended negotiation options; nil when not offered.
    public var query: DICOMQueryRetrieveOptions?
    public var worklist: Bool
    public var upsQuery: Bool
    public var relevantPatientInformation: Bool
    /// The FIND models answered; nil answers every model.
    public var queryModels: Set<String>?
    /// MOVE and GET models, with the extended negotiation options; nil when not offered.
    public var retrieve: DICOMQueryRetrieveOptions?
    /// The MOVE and GET models answered; nil answers every model.
    public var retrieveModels: Set<String>?
    /// DIMSE-N SOP Classes (or Meta SOP Classes).
    public var normalized: [String]
    public var storageCommitment: Bool
    public var storageCommitmentReceiver: Bool

    public init(storage: Bool = false, query: DICOMQueryRetrieveOptions? = nil, worklist: Bool = false,
                upsQuery: Bool = false, relevantPatientInformation: Bool = false,
                retrieve: DICOMQueryRetrieveOptions? = nil, normalized: [String] = [],
                queryModels: Set<String>? = nil, retrieveModels: Set<String>? = nil,
                storageCommitment: Bool = false, storageCommitmentReceiver: Bool = false) {
        self.storage = storage; self.query = query; self.worklist = worklist; self.upsQuery = upsQuery
        self.relevantPatientInformation = relevantPatientInformation; self.retrieve = retrieve
        self.normalized = normalized; self.storageCommitment = storageCommitment
        self.storageCommitmentReceiver = storageCommitmentReceiver
        self.queryModels = queryModels; self.retrieveModels = retrieveModels
    }
}

public final class DICOMServer: Sendable {
    public let configuration: DICOMServerConfiguration
    private let group: EventLoopGroup
    private let sslContext: NIOSSLContext?
    private let dispatcher: DICOMRequestDispatcher
    private let policy: DICOMAcceptorPolicy
    private let active = NIOLockedValueBox(0)
    /// The listening socket while `run` accepts connections.
    private let listening = NIOLockedValueBox<Channel?>(nil)

    /// - Parameters:
    ///   - configuration: local AE, listener, security, and protocol limits.
    ///   - storage: the Storage SCP service.
    ///   - query: the Query SCP service.
    ///   - worklist: the Modality Worklist SCP service.
    ///   - upsQuery: the UPS Query SCP service.
    ///   - relevantPatientInformation: the Relevant Patient Information Query
    ///     SCP service.
    ///   - retrieve: the C-GET and C-MOVE retrieval service.
    ///   - storageCommitment: the Storage Commitment SCP.
    ///   - storageCommitmentReceiver: receives Storage Commitment results as
    ///     the SCU, from SCPs that answer on a new association.
    ///   - storageCommitmentOutbox: keeps the Storage Commitment results
    ///     that cannot be delivered, and retries them.
    ///   - normalized: DIMSE-N services by SOP Class (or Meta SOP Class) UID.
    ///   - timing: receives the duration of each DIMSE exchange.
    ///   - eventLoopGroup: NIO event loops used by the listener and associations.
    public init(
        configuration: DICOMServerConfiguration, storage: DICOMStorageService? = nil,
        query: DICOMQueryService? = nil, worklist: DICOMQueryService? = nil,
        upsQuery: DICOMQueryService? = nil, relevantPatientInformation: DICOMQueryService? = nil, retrieve: DICOMRetrieveService? = nil,
        storageCommitment: DICOMStorageCommitmentService? = nil,
        storageCommitmentReceiver: DICOMStorageCommitmentReceiver? = nil,
        storageCommitmentOutbox: DICOMStorageCommitmentOutbox? = nil,
        normalized: [String: DICOMNormalizedService] = [:],
        timing: DIMSETiming = NoopDIMSETiming(),
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup.singleton
    ) throws {
        self.configuration = configuration
        group = eventLoopGroup
        sslContext = try configuration.tls.map { try NIOSSLContext(configuration: $0.configuration) }
        let outgoingClient = retrieve == nil && storageCommitment == nil ? nil : try DICOMClient(
            configuration: DICOMClientConfiguration(
                aeTitle: configuration.aeTitle, limits: configuration.limits, timeouts: configuration.timeouts,
                tls: configuration.clientTLS, logger: configuration.logger,
                implementation: configuration.implementation),
            eventLoopGroup: eventLoopGroup)
        dispatcher = DICOMRequestDispatcher(
            verification: true, storage: storage, query: query, worklist: worklist, upsQuery: upsQuery,
            relevantPatientInformation: relevantPatientInformation, retrieve: retrieve, normalized: normalized,
            storageCommitment: storageCommitment, commitmentReceiver: storageCommitmentReceiver,
            commitmentOutbox: storageCommitmentOutbox,
            outgoingClient: outgoingClient, timing: timing)

        let syntaxes = Self.abstractSyntaxes(
            configuration: configuration, offered: DICOMOfferedServices(
                storage: storage != nil, query: query?.queryRetrieveOptions, worklist: worklist != nil,
                upsQuery: upsQuery != nil, relevantPatientInformation: relevantPatientInformation != nil,
                retrieve: retrieve?.queryRetrieveOptions, normalized: Array(normalized.keys),
                queryModels: query?.informationModels, retrieveModels: retrieve?.informationModels,
                storageCommitment: storageCommitment != nil, storageCommitmentReceiver: storageCommitmentReceiver != nil))
        policy = DICOMAcceptorPolicy(
            aeTitle: configuration.aeTitle, abstractSyntaxes: syntaxes,
            acceptsAnyCalledAETitle: configuration.acceptsAnyCalledAETitle,
            allowedCallingAETitles: configuration.allowedCallingAETitles,
            maximumLength: configuration.limits.maximumPDULength,
            implementationClassUID: configuration.implementation.classUID,
            implementationVersionName: configuration.implementation.versionName,
            maximumOperationsPerformed: configuration.maximumOperationsPerformed,
            authenticate: configuration.authenticate, acceptsCallingAETitle: configuration.acceptsCallingAETitle,
            acceptsAssociation: configuration.acceptsAssociation)
    }

    /// The abstract syntaxes an acceptor offering these services supports, with
    /// their transfer syntaxes and roles: the table `init` negotiates with. A
    /// conformance statement (PS3.2) can be built from it without a listener.
    public static func abstractSyntaxes(
        configuration: DICOMServerConfiguration, offered: DICOMOfferedServices
    ) -> [String: DICOMAbstractSyntaxSupport] {
        var syntaxes: [String: DICOMAbstractSyntaxSupport] = [
            DICOMSOPClass.verification: DICOMAbstractSyntaxSupport(transferSyntaxes: configuration.transferSyntaxes),
        ]
        if offered.storage || offered.retrieve != nil {
            // Storage contexts: received as SCP, or sent as SCU for C-GET.
            for sopClass in configuration.storageSOPClasses {
                syntaxes[sopClass] = DICOMAbstractSyntaxSupport(
                    transferSyntaxes: configuration.storageTransferSyntaxes, scpRole: offered.storage,
                    scuRole: offered.retrieve != nil, prefersProposedOrder: true)
            }
        }
        if let options = offered.query {
            for model in [DICOMSOPClass.patientRootFind, DICOMSOPClass.studyRootFind, DICOMSOPClass.patientStudyOnlyFind]
                where offered.queryModels?.contains(model) ?? true {
                syntaxes[model] = DICOMAbstractSyntaxSupport(transferSyntaxes: configuration.transferSyntaxes,
                    queryRetrieveOptions: options)
            }
        }
        if offered.worklist {
            syntaxes[DICOMSOPClass.modalityWorklistFind] = DICOMAbstractSyntaxSupport(
                transferSyntaxes: configuration.transferSyntaxes)
        }
        if offered.upsQuery {
            syntaxes[DICOMSOPClass.upsQuery] = DICOMAbstractSyntaxSupport(
                transferSyntaxes: configuration.transferSyntaxes)
        }
        if offered.relevantPatientInformation {
            for model in DICOMRelevantPatientInformationService.models {
                syntaxes[model] = DICOMAbstractSyntaxSupport(transferSyntaxes: configuration.transferSyntaxes)
            }
        }
        if let options = offered.retrieve {
            for model in [DICOMSOPClass.patientRootMove, DICOMSOPClass.studyRootMove, DICOMSOPClass.patientStudyOnlyMove,
                          DICOMSOPClass.compositeInstanceRootMove, DICOMSOPClass.patientRootGet,
                          DICOMSOPClass.studyRootGet, DICOMSOPClass.patientStudyOnlyGet,
                          DICOMSOPClass.compositeInstanceRootGet, DICOMSOPClass.compositeInstanceRetrieveWithoutBulkDataGet]
                where offered.retrieveModels?.contains(model) ?? true {
                syntaxes[model] = DICOMAbstractSyntaxSupport(transferSyntaxes: configuration.transferSyntaxes,
                    queryRetrieveOptions: options)
            }
        }
        // DIMSE-N: this side performs operations, and receives notifications
        // from requestors granted the SCP role.
        for sopClass in offered.normalized where sopClass != DICOMSOPClass.storageCommitmentPushModel {
            syntaxes[sopClass] = DICOMAbstractSyntaxSupport(
                transferSyntaxes: configuration.transferSyntaxes, scpRole: true, scuRole: true)
        }
        let commitmentReceiver = offered.storageCommitmentReceiver
            || offered.normalized.contains(DICOMSOPClass.storageCommitmentPushModel)
        if offered.storageCommitment || commitmentReceiver {
            // A receiver also accepts SCPs that send results without
            // proposing their role (PS3.4 J.3.3.2 requires it).
            syntaxes[DICOMSOPClass.storageCommitmentPushModel] = DICOMAbstractSyntaxSupport(
                transferSyntaxes: configuration.transferSyntaxes, scpRole: true,
                scuRole: commitmentReceiver)
        }
        return syntaxes
    }

    /// The abstract syntaxes this acceptor negotiates, by UID.
    public var supportedAbstractSyntaxes: [String: DICOMAbstractSyntaxSupport] { policy.abstractSyntaxes }

    /// The number of associations being served.
    public var activeAssociations: Int { active.withLockedValue { $0 } }

    /// Stops accepting connections and frees the port, without touching the
    /// associations in progress: `run` returns once they have all ended.
    /// Cancelling the task of `run` still ends them at once.
    public func stopAccepting() async {
        guard let channel = listening.withLockedValue({ $0 }) else { return }
        try? await channel.close()
    }

    /// Binds and serves until the task is cancelled. `onBound` receives the
    /// bound port once connections are accepted.
    public func run(onBound: (@Sendable (Int) -> Void)? = nil) async throws {
        if let outbox = dispatcher.commitmentOutbox, let client = dispatcher.outgoingClient,
           let service = dispatcher.storageCommitment {
            await outbox.attach(client: client, service: service)
        }
        let configuration = self.configuration
        let sslContext = self.sslContext
        let server = try await ServerBootstrap(group: group)
            // Errors raised while accepting one connection (reset by the peer before it is
            // accepted: NIOFcntlFailedError on Darwin, ECONNABORTED on Linux) would end the
            // accept loop, and with it the whole server: they are logged and dropped here.
            .serverChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(AcceptErrorFilter(logger: configuration.logger))
                }
            }
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .bind(host: configuration.host, port: configuration.port) { channel in
                // A connection closed or reset before it is set up (port probe, client giving up)
                // makes the setup throw. Thrown here, the error would end the accept loop and stop
                // the whole server: the connection is dropped instead.
                channel.eventLoop.makeCompletedFuture { () -> DICOMChannel.Async? in
                    do {
                        // Set here rather than as bootstrap child options: on a connection already
                        // reset they fail (EINVAL), which must drop that connection only.
                        try channel.syncOptions?.setOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)
                        try channel.syncOptions?.setOption(ChannelOptions.socketOption(.so_keepalive), value: 1)
                        return try DICOMChannel.configure(
                            channel, tls: sslContext, serverHostname: nil, isServer: true,
                            limits: configuration.limits, timeouts: configuration.timeouts)
                    } catch {
                        configuration.logger.debug("connection dropped during setup: \(error)")
                        channel.close(promise: nil)
                        return nil
                    }
                }
            }
        let port = server.channel.localAddress?.port ?? configuration.port
        listening.withLockedValue { $0 = server.channel }
        defer { listening.withLockedValue { $0 = nil } }
        configuration.logger.info("\(configuration.aeTitle) listening on \(configuration.host):\(port)")
        onBound?(port)

        try await server.executeThenClose { connections in
            if #available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *) {
                try await withThrowingDiscardingTaskGroup { group in
                    for try await connection in connections {
                        guard let connection else { continue }
                        group.addTask { await self.serve(connection) }
                    }
                }
            } else {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    // Finished tasks are collected as connections arrive, so
                    // that a long-running server does not accumulate them.
                    var spawned = 0
                    for try await connection in connections {
                        guard let connection else { continue }
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
        // A rejected association gives its place back at once, not when its
        // connection closes.
        let slot = NIOLockedValueBox(true)
        let release: @Sendable () -> Void = { [active] in
            if slot.withLockedValue({ held in defer { held = false }; return held }) {
                active.withLockedValue { $0 -= 1 }
            }
        }
        defer { release() }
        do {
            try await connection.executeThenClose { inbound, outbound in
                try await self.associate(
                    inbound: inbound, outbound: outbound, channel: connection.channel, admitted: admitted,
                    release: release)
            }
        } catch {
            logger.debug("connection from \(peer) ended: \(error)")
        }
    }

    private func associate(
        inbound: NIOAsyncChannelInboundStream<DICOMPDU>, outbound: NIOAsyncChannelOutboundWriter<DICOMPDU>,
        channel: Channel, admitted: Bool, release: @Sendable () -> Void
    ) async throws {
        let configuration = self.configuration
        var logger = configuration.logger
        logger[metadataKey: "association_id"] = .string(UUID().uuidString.lowercased())
        logger[metadataKey: "remote_ip"] = .string(channel.remoteAddress?.ipAddress ?? "unknown")
        logger[metadataKey: "remote_port"] = .string(String(channel.remoteAddress?.port ?? 0))
        logger[metadataKey: "local_ip"] = .string(channel.localAddress?.ipAddress ?? "unknown")
        logger[metadataKey: "local_port"] = .string(String(channel.localAddress?.port ?? 0))
        logger[metadataKey: "tls"] = .string(String(configuration.tls != nil))
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

        logger[metadataKey: "calling_ae"] = .string(request.callingAETitle)
        logger[metadataKey: "called_ae"] = .string(request.calledAETitle)
        let answer: Result<(DICOMAssociateAccept, DICOMNegotiatedAssociation), DICOMAssociateReject> = admitted
            ? DICOMAssociationNegotiator.respond(
                to: request, policy: policy, remoteAddress: channel.remoteAddress?.ipAddress)
            : .failure(DICOMAssociateReject(result: .transient, reason: .localLimitExceeded))
        switch answer {
        case .failure(let reject):
            release()
            logger.info("Association refused", metadata: ["event": "association.refused", "reason": .string(String(describing: reject.reason))])
            if let audit = configuration.audit {
                let host = DICOMAuditMessage.host(of: channel.remoteAddress?.description)
                let source = configuration.auditSource ?? DICOMAuditSource(id: configuration.aeTitle)
                await audit.record(.securityAlert(
                    type: .dcm("110126"),
                    reporters: [.application(aeTitles: [configuration.aeTitle], isRequestor: false)],
                    performers: [.node(aeTitle: request.callingAETitle, host: host, isRequestor: true)],
                    subjects: [(id: host ?? request.callingAETitle, isURI: false,
                                description: "Association from \(request.callingAETitle) to \(request.calledAETitle) rejected: \(reject.reason)")],
                    source: source))
            }
            for case .send(let pdu) in machine.handle(.associateRejectPrimitive(reject)) { try? await outbound.write(pdu) }
            await Self.awaitClose(&iterator, channel: channel, artim: configuration.timeouts.artim)
        case .success(let (accept, negotiated)):
            for case .send(let pdu) in machine.handle(.associateAcceptPrimitive(accept)) { try await outbound.write(pdu) }
            logger.info("Association accepted", metadata: ["event": "association.accepted",
                "accepted_contexts": .string(String(negotiated.presentationContexts.count)),
                "proposed_contexts": .string(String(request.presentationContexts.count)),
                "requestor_max_pdu": .string(String(negotiated.requestorMaximumLength)),
                "acceptor_max_pdu": .string(String(negotiated.acceptorMaximumLength)),
                "async_invoked": .string(String(negotiated.asynchronousOperationsWindow.maximumInvoked)),
                "async_performed": .string(String(negotiated.asynchronousOperationsWindow.maximumPerformed)),
                "implementation_class": .string(negotiated.requestorImplementationClassUID ?? ""),
                "implementation_version": .string(negotiated.requestorImplementationVersionName ?? "")])
            for context in request.presentationContexts {
                if let accepted = negotiated.presentationContexts[context.id] {
                    logger.info("Presentation context accepted", metadata: ["event": "association.context.accepted",
                        "context_id": .string(String(accepted.id)), "sop_class": .string(accepted.abstractSyntax),
                        "transfer_syntax": .string(accepted.transferSyntax),
                        "requestor_scu": .string(String(accepted.requestorIsSCU)), "requestor_scp": .string(String(accepted.requestorIsSCP))])
                } else {
                    logger.info("Presentation context refused", metadata: ["event": "association.context.refused",
                        "context_id": .string(String(context.id)), "sop_class": .string(context.abstractSyntax),
                        "reason": .string(accept.presentationContexts.first(where: { $0.id == context.id }).map { String(describing: $0.result) } ?? "not_negotiated")])
                }
            }
            if let audit = configuration.audit, let identity = negotiated.userIdentity {
                let host = DICOMAuditMessage.host(of: channel.remoteAddress?.description)
                await audit.record(.userAuthentication(
                    login: true,
                    user: DICOMAuditMessage.ActiveParticipant(
                        userID: identity.primaryFieldDescription, alternativeUserID: "AETITLES=\(request.callingAETitle)",
                        isRequestor: true, networkAccessPointID: host ?? "unknown",
                        networkAccessPointType: host.map(DICOMAuditMessage.NetworkAccessPointType.of) ?? .machineName),
                    authenticator: .application(aeTitles: [configuration.aeTitle], isRequestor: false),
                    source: configuration.auditSource ?? DICOMAuditSource(id: configuration.aeTitle)))
            }
            let runtime = DICOMAssociationRuntime(
                machine: machine, negotiated: negotiated, outbound: outbound, channel: channel,
                limits: configuration.limits, timeouts: configuration.timeouts, logger: logger,
                peerCertificate: await DICOMChannel.peerCertificate(of: channel))
            await DICOMAssociationRuntime.serve(
                runtime: runtime, association: DICOMAssociation(runtime: runtime), iterator: &iterator,
                dispatcher: dispatcher)
            logger.debug("Association handler ended", metadata: ["event": "association.closed"])
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

/// Keeps the listening channel alive when accepting one connection fails: the error concerns
/// that connection only (already reset or aborted by the peer), not the server.
final class AcceptErrorFilter: ChannelInboundHandler, Sendable {
    typealias InboundIn = Channel
    typealias InboundOut = Channel
    let logger: Logging.Logger
    init(logger: Logging.Logger) { self.logger = logger }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.debug("connection dropped while being accepted: \(error)")
    }
}
