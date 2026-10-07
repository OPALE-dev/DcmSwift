/// A presentation context both sides agreed on (PS3.8 7.1.1.13).
public struct DICOMAcceptedPresentationContext: Equatable, Sendable {
    public var id: UInt8
    public var abstractSyntax: String
    public var transferSyntax: String
    /// The association requestor may act as SCU (PS3.7 D.3.3.4).
    public var requestorIsSCU: Bool
    /// The association requestor may act as SCP.
    public var requestorIsSCP: Bool

    public init(id: UInt8, abstractSyntax: String, transferSyntax: String, requestorIsSCU: Bool = true,
                requestorIsSCP: Bool = false) {
        self.id = id
        self.abstractSyntax = abstractSyntax
        self.transferSyntax = transferSyntax
        self.requestorIsSCU = requestorIsSCU
        self.requestorIsSCP = requestorIsSCP
    }
}

/// The outcome of association negotiation, as seen by either side.
public struct DICOMNegotiatedAssociation: Equatable, Sendable {
    public var callingAETitle: String
    public var calledAETitle: String
    /// Accepted presentation contexts, by ID.
    public var presentationContexts: [UInt8: DICOMAcceptedPresentationContext]
    /// The largest P-DATA-TF variable field the requestor accepts; 0 means
    /// no limit.
    public var requestorMaximumLength: UInt32
    /// The largest P-DATA-TF variable field the acceptor accepts.
    public var acceptorMaximumLength: UInt32
    public var asynchronousOperationsWindow: DICOMAsynchronousOperationsWindow
    public var requestorImplementationClassUID: String?
    public var requestorImplementationVersionName: String?
    public var acceptorImplementationClassUID: String?
    public var acceptorImplementationVersionName: String?
    public var userIdentity: DICOMUserIdentity?
    public var extendedNegotiations: [DICOMExtendedNegotiation]

    /// The accepted contexts for an abstract syntax, in ID order.
    public func contexts(for abstractSyntax: String) -> [DICOMAcceptedPresentationContext] {
        presentationContexts.values.filter { $0.abstractSyntax == abstractSyntax }.sorted { $0.id < $1.id }
    }
}

/// What an acceptor supports for one abstract syntax.
public struct DICOMAbstractSyntaxSupport: Sendable {
    /// Transfer syntaxes in order of preference.
    public var transferSyntaxes: [String]
    /// This side may act as SCP (the usual acceptor role).
    public var scpRole: Bool
    /// This side may act as SCU when the requestor proposes the SCP role
    /// (for example C-STORE sub-operations of C-GET).
    public var scuRole: Bool
    /// Choose the first proposed transfer syntax that is supported, rather
    /// than this side's preference: a storage SCP then keeps instances as
    /// the requestor encoded them.
    public var prefersProposedOrder: Bool

    public init(transferSyntaxes: [String], scpRole: Bool = true, scuRole: Bool = false, prefersProposedOrder: Bool = false) {
        self.transferSyntaxes = transferSyntaxes
        self.scpRole = scpRole
        self.scuRole = scuRole
        self.prefersProposedOrder = prefersProposedOrder
    }
}

/// The acceptor's policy for A-ASSOCIATE-RQ (PS3.8 7.1, PS3.7 D.3.3).
public struct DICOMAcceptorPolicy: Sendable {
    public var aeTitle: String
    /// Also accept requests addressed to another called AE title.
    public var acceptsAnyCalledAETitle: Bool
    /// Calling AE titles allowed; nil accepts any.
    public var allowedCallingAETitles: Set<String>?
    /// Supported abstract syntaxes, by UID.
    public var abstractSyntaxes: [String: DICOMAbstractSyntaxSupport]
    /// The Maximum Length Received announced; 0 means no limit.
    public var maximumLength: UInt32
    public var implementationClassUID: String
    public var implementationVersionName: String?
    /// Operations performed asynchronously; 1 disables asynchronous
    /// operations.
    public var maximumOperationsPerformed: UInt16
    /// Decides on the user identity: return nil to refuse the association,
    /// or the server response to send (empty when none was requested).
    public var authenticate: (@Sendable (DICOMUserIdentity?) -> [UInt8]?)?

    public init(
        aeTitle: String, abstractSyntaxes: [String: DICOMAbstractSyntaxSupport],
        acceptsAnyCalledAETitle: Bool = false, allowedCallingAETitles: Set<String>? = nil,
        maximumLength: UInt32 = 1 << 16, implementationClassUID: String = DICOMImplementation.classUID,
        implementationVersionName: String? = DICOMImplementation.versionName, maximumOperationsPerformed: UInt16 = 1,
        authenticate: (@Sendable (DICOMUserIdentity?) -> [UInt8]?)? = nil
    ) {
        self.aeTitle = aeTitle
        self.abstractSyntaxes = abstractSyntaxes
        self.acceptsAnyCalledAETitle = acceptsAnyCalledAETitle
        self.allowedCallingAETitles = allowedCallingAETitles
        self.maximumLength = maximumLength
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.maximumOperationsPerformed = maximumOperationsPerformed
        self.authenticate = authenticate
    }
}

/// This implementation's identification (PS3.7 D.3.3.2).
public enum DICOMImplementation {
    /// A UUID-derived UID (PS3.5 B.2), fixed for this implementation.
    public static let classUID = "2.25.104230404413607029071322826525038420589"
    public static let versionName = "DCMSWIFT_2.0"
}

/// Association negotiation, on both sides (PS3.8 7.1, PS3.7 Annex D.3.3).
public enum DICOMAssociationNegotiator {
    /// The acceptor's answer to a request: an A-ASSOCIATE-AC and the
    /// negotiated association, or an A-ASSOCIATE-RJ.
    public static func respond(
        to request: DICOMAssociateRequest, policy: DICOMAcceptorPolicy
    ) -> Result<(DICOMAssociateAccept, DICOMNegotiatedAssociation), DICOMAssociateReject> {
        guard request.protocolVersion & 1 == 1 else {
            return .failure(DICOMAssociateReject(result: .permanent, reason: .protocolVersionNotSupported))
        }
        guard request.applicationContextName == dicomApplicationContextName else {
            return .failure(DICOMAssociateReject(result: .permanent, reason: .applicationContextNameNotSupported))
        }
        guard policy.acceptsAnyCalledAETitle || request.calledAETitle == policy.aeTitle else {
            return .failure(DICOMAssociateReject(result: .permanent, reason: .calledAETitleNotRecognized))
        }
        if let allowed = policy.allowedCallingAETitles, !allowed.contains(request.callingAETitle) {
            return .failure(DICOMAssociateReject(result: .permanent, reason: .callingAETitleNotRecognized))
        }
        var serverResponse: [UInt8] = []
        if let authenticate = policy.authenticate {
            guard let response = authenticate(request.userInformation.userIdentity) else {
                return .failure(DICOMAssociateReject(result: .permanent, reason: .noReasonGiven))
            }
            serverResponse = response
        }

        let proposedRoles = Dictionary(
            request.userInformation.roleSelections.map { ($0.sopClassUID, $0) }, uniquingKeysWith: { first, _ in first })
        var results: [DICOMPresentationContextResult] = []
        var accepted: [UInt8: DICOMAcceptedPresentationContext] = [:]
        var roleReplies: [String: DICOMRoleSelection] = [:]
        var seen = Set<UInt8>()
        for proposal in request.presentationContexts {
            // IDs are odd and unique (PS3.8 9.3.2.2).
            guard proposal.id % 2 == 1, seen.insert(proposal.id).inserted else {
                results.append(DICOMPresentationContextResult(id: proposal.id, result: .noReason, transferSyntax: ""))
                continue
            }
            guard let support = policy.abstractSyntaxes[proposal.abstractSyntax] else {
                results.append(DICOMPresentationContextResult(
                    id: proposal.id, result: .abstractSyntaxNotSupported, transferSyntax: ""))
                continue
            }
            let chosen = support.prefersProposedOrder
                ? proposal.transferSyntaxes.first(where: support.transferSyntaxes.contains)
                : support.transferSyntaxes.first(where: proposal.transferSyntaxes.contains)
            guard let syntax = chosen else {
                results.append(DICOMPresentationContextResult(
                    id: proposal.id, result: .transferSyntaxesNotSupported, transferSyntax: ""))
                continue
            }
            // Roles: the requestor is SCU and the acceptor SCP unless role
            // selection proposes otherwise; each role is granted only if
            // proposed and supported (D.3.3.4).
            var requestorIsSCU = true, requestorIsSCP = false
            if let proposed = proposedRoles[proposal.abstractSyntax] {
                requestorIsSCU = proposed.scuRole && support.scpRole
                requestorIsSCP = proposed.scpRole && support.scuRole
                roleReplies[proposal.abstractSyntax] = DICOMRoleSelection(
                    sopClassUID: proposal.abstractSyntax, scuRole: requestorIsSCU, scpRole: requestorIsSCP)
            } else if !support.scpRole {
                results.append(DICOMPresentationContextResult(id: proposal.id, result: .userRejection, transferSyntax: ""))
                continue
            }
            guard requestorIsSCU || requestorIsSCP else {
                results.append(DICOMPresentationContextResult(id: proposal.id, result: .userRejection, transferSyntax: ""))
                continue
            }
            results.append(DICOMPresentationContextResult(id: proposal.id, result: .acceptance, transferSyntax: syntax))
            accepted[proposal.id] = DICOMAcceptedPresentationContext(
                id: proposal.id, abstractSyntax: proposal.abstractSyntax, transferSyntax: syntax,
                requestorIsSCU: requestorIsSCU, requestorIsSCP: requestorIsSCP)
        }

        // Asynchronous operations (D.3.3.3): never more than proposed.
        var window = DICOMAsynchronousOperationsWindow(maximumInvoked: 1, maximumPerformed: 1)
        var windowReply: DICOMAsynchronousOperationsWindow?
        if let proposed = request.userInformation.asynchronousOperationsWindow, policy.maximumOperationsPerformed != 1 {
            func limit(_ value: UInt16, _ local: UInt16) -> UInt16 {
                value == 0 ? local : (local == 0 ? value : min(value, local))
            }
            window = DICOMAsynchronousOperationsWindow(
                maximumInvoked: limit(proposed.maximumInvoked, policy.maximumOperationsPerformed),
                maximumPerformed: limit(proposed.maximumPerformed, policy.maximumOperationsPerformed))
            windowReply = window
        }

        let identity = request.userInformation.userIdentity
        let userInformation = DICOMUserInformation(
            maximumLength: policy.maximumLength, implementationClassUID: policy.implementationClassUID,
            implementationVersionName: policy.implementationVersionName, asynchronousOperationsWindow: windowReply,
            roleSelections: request.userInformation.roleSelections.compactMap { roleReplies[$0.sopClassUID] },
            userIdentityServerResponse: identity?.positiveResponseRequested == true ? serverResponse : nil)
        let accept = DICOMAssociateAccept(
            calledAETitle: request.calledAETitle, callingAETitle: request.callingAETitle,
            presentationContexts: results, userInformation: userInformation)
        let negotiated = DICOMNegotiatedAssociation(
            callingAETitle: request.callingAETitle, calledAETitle: request.calledAETitle,
            presentationContexts: accepted,
            requestorMaximumLength: request.userInformation.maximumLength ?? 0,
            acceptorMaximumLength: policy.maximumLength, asynchronousOperationsWindow: window,
            requestorImplementationClassUID: request.userInformation.implementationClassUID,
            requestorImplementationVersionName: request.userInformation.implementationVersionName,
            acceptorImplementationClassUID: policy.implementationClassUID,
            acceptorImplementationVersionName: policy.implementationVersionName,
            userIdentity: identity, extendedNegotiations: request.userInformation.extendedNegotiations)
        return .success((accept, negotiated))
    }

    /// The requestor's view of an accepted association; an answer that does
    /// not match the request is a protocol error.
    public static func negotiated(
        request: DICOMAssociateRequest, accept: DICOMAssociateAccept
    ) throws -> DICOMNegotiatedAssociation {
        let proposals = Dictionary(request.presentationContexts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let roleReplies = Dictionary(
            accept.userInformation.roleSelections.map { ($0.sopClassUID, $0) }, uniquingKeysWith: { first, _ in first })
        let proposedRoles = Set(request.userInformation.roleSelections.map(\.sopClassUID))
        var accepted: [UInt8: DICOMAcceptedPresentationContext] = [:]
        for result in accept.presentationContexts where result.result == .acceptance {
            guard let proposal = proposals[result.id], accepted[result.id] == nil else {
                throw DICOMPDUError(.invalidPDUParameterValue, "presentation context \(result.id) was not proposed")
            }
            guard proposal.transferSyntaxes.contains(result.transferSyntax) else {
                throw DICOMPDUError(
                    .invalidPDUParameterValue, "transfer syntax \(result.transferSyntax) was not proposed for \(result.id)")
            }
            var scu = true, scp = false
            if proposedRoles.contains(proposal.abstractSyntax) {
                // Without a reply the default roles apply (D.3.3.4).
                if let reply = roleReplies[proposal.abstractSyntax] {
                    scu = reply.scuRole
                    scp = reply.scpRole
                }
            }
            accepted[result.id] = DICOMAcceptedPresentationContext(
                id: result.id, abstractSyntax: proposal.abstractSyntax, transferSyntax: result.transferSyntax,
                requestorIsSCU: scu, requestorIsSCP: scp)
        }
        var window = DICOMAsynchronousOperationsWindow(maximumInvoked: 1, maximumPerformed: 1)
        if let reply = accept.userInformation.asynchronousOperationsWindow,
           request.userInformation.asynchronousOperationsWindow != nil {
            window = reply
        }
        return DICOMNegotiatedAssociation(
            callingAETitle: request.callingAETitle, calledAETitle: request.calledAETitle,
            presentationContexts: accepted,
            requestorMaximumLength: request.userInformation.maximumLength ?? 0,
            acceptorMaximumLength: accept.userInformation.maximumLength ?? 0, asynchronousOperationsWindow: window,
            requestorImplementationClassUID: request.userInformation.implementationClassUID,
            requestorImplementationVersionName: request.userInformation.implementationVersionName,
            acceptorImplementationClassUID: accept.userInformation.implementationClassUID,
            acceptorImplementationVersionName: accept.userInformation.implementationVersionName,
            userIdentity: request.userInformation.userIdentity,
            extendedNegotiations: accept.userInformation.extendedNegotiations)
    }
}
