/// The DICOM Upper Layer state machine (PS3.8 9.2, Table 9-10), free of I/O:
/// each event returns the actions the transport and the service user must
/// carry out, in order.
public struct DICOMAssociationStateMachine: Sendable {
    /// Sta1 to Sta13 (PS3.8 Table 9-1).
    public enum State: Int, Sendable {
        case idle = 1
        case awaitingAssociateRequest = 2
        case awaitingLocalAssociateResponse = 3
        case awaitingTransportOpen = 4
        case awaitingAssociateResponse = 5
        case established = 6
        case awaitingReleaseResponse = 7
        case awaitingLocalReleaseResponse = 8
        case releaseCollisionRequestorAwaitingLocalResponse = 9
        case releaseCollisionAcceptorAwaitingReleaseResponse = 10
        case releaseCollisionRequestorAwaitingReleaseResponse = 11
        case releaseCollisionAcceptorAwaitingLocalResponse = 12
        case awaitingTransportClose = 13
    }

    public enum Role: Sendable {
        case requestor
        case acceptor
    }

    /// Evt1 to Evt19 (PS3.8 Table 9-2).
    public enum Event: Equatable, Sendable {
        case associateRequestPrimitive(DICOMAssociateRequest)
        case transportConnectConfirm
        case associateAcceptPDU(DICOMAssociateAccept)
        case associateRejectPDU(DICOMAssociateReject)
        case transportConnectIndication
        case associateRequestPDU(DICOMAssociateRequest)
        case associateAcceptPrimitive(DICOMAssociateAccept)
        case associateRejectPrimitive(DICOMAssociateReject)
        case dataPrimitive([DICOMPresentationDataValue])
        case dataPDU([DICOMPresentationDataValue])
        case releaseRequestPrimitive
        case releaseRequestPDU
        case releaseResponsePDU
        case releaseResponsePrimitive
        case abortRequestPrimitive
        case abortPDU(DICOMAbort)
        case transportClosed
        case artimExpired
        case invalidPDU(DICOMAbort.Reason)

        /// The event a received PDU raises.
        public init(received pdu: DICOMPDU) {
            switch pdu {
            case .associateRequest(let request): self = .associateRequestPDU(request)
            case .associateAccept(let accept): self = .associateAcceptPDU(accept)
            case .associateReject(let reject): self = .associateRejectPDU(reject)
            case .data(let values): self = .dataPDU(values)
            case .releaseRequest: self = .releaseRequestPDU
            case .releaseResponse: self = .releaseResponsePDU
            case .abort(let abort): self = .abortPDU(abort)
            }
        }
    }

    /// What the service user learns (the indication and confirmation
    /// primitives of PS3.8 7).
    public enum Indication: Equatable, Sendable {
        case associateRequested(DICOMAssociateRequest)
        case associateAccepted(DICOMAssociateAccept)
        case associateRejected(DICOMAssociateReject)
        case data([DICOMPresentationDataValue])
        case releaseRequested
        case releaseConfirmed
        /// A-ABORT from the peer service user.
        case aborted
        /// A-P-ABORT: the provider aborted the association.
        case providerAborted(DICOMAbort.Reason)
    }

    public enum Action: Equatable, Sendable {
        case openTransport
        case send(DICOMPDU)
        case indicate(Indication)
        case startARTIM
        case stopARTIM
        case closeTransport
    }

    public let role: Role
    public private(set) var state: State = .idle

    public init(role: Role) {
        self.role = role
    }

    /// A machine already in `state`, for tests.
    init(role: Role, state: State) {
        self.role = role
        self.state = state
    }

    /// Handles an event and returns the actions to perform. A local
    /// primitive that the current state does not allow returns no action.
    public mutating func handle(_ event: Event) -> [Action] {
        let s = state
        func abortAsProvider(_ reason: DICOMAbort.Reason) -> [Action] {
            // AA-8.
            state = .awaitingTransportClose
            return [.send(.abort(DICOMAbort(source: .serviceProvider, reason: reason))),
                    .indicate(.providerAborted(reason)), .startARTIM]
        }
        func abortAsUser() -> [Action] {
            // AA-1.
            state = .awaitingTransportClose
            return [.send(.abort(DICOMAbort(source: .serviceUser))), .startARTIM]
        }
        /// The response to an unexpected PDU in states 2 to 13.
        func unexpected(_ reason: DICOMAbort.Reason = .unexpectedPDU) -> [Action] {
            switch s {
            case .awaitingAssociateRequest: return abortAsUser()
            case .awaitingTransportClose: return []  // AA-6: ignore.
            case .idle, .awaitingTransportOpen: return []
            default: return abortAsProvider(reason)
            }
        }

        switch event {
        case .associateRequestPrimitive(let request):
            guard s == .idle, role == .requestor else { return [] }
            // AE-1; the request is sent once the transport is open (AE-2).
            pendingRequest = request
            state = .awaitingTransportOpen
            return [.openTransport]

        case .transportConnectConfirm:
            guard s == .awaitingTransportOpen, let request = pendingRequest else { return [] }
            pendingRequest = nil
            state = .awaitingAssociateResponse
            return [.send(.associateRequest(request))]

        case .associateAcceptPDU(let accept):
            guard s == .awaitingAssociateResponse else { return unexpected() }
            state = .established
            return [.indicate(.associateAccepted(accept))]

        case .associateRejectPDU(let reject):
            guard s == .awaitingAssociateResponse else { return unexpected() }
            state = .idle
            return [.indicate(.associateRejected(reject)), .closeTransport]

        case .transportConnectIndication:
            guard s == .idle, role == .acceptor else { return [] }
            state = .awaitingAssociateRequest
            return [.startARTIM]

        case .associateRequestPDU(let request):
            switch s {
            case .awaitingAssociateRequest:
                state = .awaitingLocalAssociateResponse
                return [.stopARTIM, .indicate(.associateRequested(request))]
            case .awaitingTransportClose:
                // AA-7.
                return [.send(.abort(DICOMAbort(source: .serviceProvider, reason: .unexpectedPDU)))]
            default:
                return unexpected()
            }

        case .associateAcceptPrimitive(let accept):
            guard s == .awaitingLocalAssociateResponse else { return [] }
            state = .established
            return [.send(.associateAccept(accept))]

        case .associateRejectPrimitive(let reject):
            guard s == .awaitingLocalAssociateResponse else { return [] }
            state = .awaitingTransportClose
            return [.send(.associateReject(reject)), .startARTIM]

        case .dataPrimitive(let values):
            switch s {
            case .established, .awaitingLocalReleaseResponse:
                return [.send(.data(values))]
            default:
                return []
            }

        case .dataPDU(let values):
            switch s {
            case .established, .awaitingReleaseResponse:
                return [.indicate(.data(values))]
            default:
                return unexpected()
            }

        case .releaseRequestPrimitive:
            guard s == .established else { return [] }
            state = .awaitingReleaseResponse
            return [.send(.releaseRequest)]

        case .releaseRequestPDU:
            switch s {
            case .established:
                state = .awaitingLocalReleaseResponse
                return [.indicate(.releaseRequested)]
            case .awaitingReleaseResponse:
                // AR-8: release collision.
                state = role == .requestor
                    ? .releaseCollisionRequestorAwaitingLocalResponse : .releaseCollisionAcceptorAwaitingReleaseResponse
                return [.indicate(.releaseRequested)]
            default:
                return unexpected()
            }

        case .releaseResponsePDU:
            switch s {
            case .awaitingReleaseResponse, .releaseCollisionRequestorAwaitingReleaseResponse:
                // AR-3.
                state = .idle
                return [.indicate(.releaseConfirmed), .closeTransport]
            case .releaseCollisionAcceptorAwaitingReleaseResponse:
                // AR-10.
                state = .releaseCollisionAcceptorAwaitingLocalResponse
                return [.indicate(.releaseConfirmed)]
            default:
                return unexpected()
            }

        case .releaseResponsePrimitive:
            switch s {
            case .awaitingLocalReleaseResponse, .releaseCollisionAcceptorAwaitingLocalResponse:
                // AR-4.
                state = .awaitingTransportClose
                return [.send(.releaseResponse), .startARTIM]
            case .releaseCollisionRequestorAwaitingLocalResponse:
                // AR-9.
                state = .releaseCollisionRequestorAwaitingReleaseResponse
                return [.send(.releaseResponse)]
            default:
                return []
            }

        case .abortRequestPrimitive:
            switch s {
            case .idle, .awaitingAssociateRequest, .awaitingTransportClose:
                return []
            case .awaitingTransportOpen:
                // AA-2.
                state = .idle
                pendingRequest = nil
                return [.closeTransport]
            default:
                return abortAsUser()
            }

        case .abortPDU(let abort):
            switch s {
            case .idle, .awaitingTransportOpen:
                return []
            case .awaitingAssociateRequest, .awaitingTransportClose:
                // AA-2.
                state = .idle
                return [.stopARTIM, .closeTransport]
            default:
                // AA-3.
                state = .idle
                return [.indicate(abort.source == .serviceProvider ? .providerAborted(abort.reason) : .aborted),
                        .closeTransport]
            }

        case .transportClosed:
            switch s {
            case .idle:
                return []
            case .awaitingAssociateRequest:
                // AA-5.
                state = .idle
                return [.stopARTIM]
            case .awaitingTransportClose:
                // AR-5.
                state = .idle
                return [.stopARTIM]
            default:
                // AA-4.
                state = .idle
                pendingRequest = nil
                return [.indicate(.providerAborted(.notSpecified))]
            }

        case .artimExpired:
            switch s {
            case .awaitingAssociateRequest, .awaitingTransportClose:
                // AA-2.
                state = .idle
                return [.closeTransport]
            default:
                return []
            }

        case .invalidPDU(let reason):
            switch s {
            case .awaitingTransportClose:
                // AA-7.
                return [.send(.abort(DICOMAbort(source: .serviceProvider, reason: reason)))]
            default:
                return unexpected(reason)
            }
        }
    }

    private var pendingRequest: DICOMAssociateRequest?
}
