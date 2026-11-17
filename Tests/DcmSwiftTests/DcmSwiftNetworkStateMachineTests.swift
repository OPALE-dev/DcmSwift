import XCTest
import NIOCore
@testable import DcmSwift

/// The PS3.8 Table 9-10 state transitions, checked cell by cell.
final class DcmSwiftNetworkStateMachineTests: XCTestCase {
    typealias Machine = DICOMAssociationStateMachine

    private let request = DICOMAssociateRequest(
        calledAETitle: "SCP", callingAETitle: "SCU",
        presentationContexts: [DICOMPresentationContextProposal(
            id: 1, abstractSyntax: "1.2.840.10008.1.1", transferSyntaxes: ["1.2.840.10008.1.2"])],
        userInformation: DICOMUserInformation(maximumLength: 16384))
    private var accept: DICOMAssociateAccept {
        DICOMAssociateAccept(
            calledAETitle: "SCP", callingAETitle: "SCU",
            presentationContexts: [DICOMPresentationContextResult(id: 1, result: .acceptance, transferSyntax: "1.2.840.10008.1.2")],
            userInformation: DICOMUserInformation(maximumLength: 16384))
    }
    private let reject = DICOMAssociateReject(result: .permanent, reason: .calledAETitleNotRecognized)
    private let values = [DICOMPresentationDataValue(
        presentationContextID: 1, isCommand: true, isLast: true, data: ByteBufferAllocator().buffer(bytes: [1]))]

    /// The table's action codes, as the actions this implementation emits.
    private func actions(_ code: String, event: Machine.Event) -> [Machine.Action] {
        let providerAbort: DICOMAbort.Reason
        if case .invalidPDU(let reason) = event { providerAbort = reason } else { providerAbort = .unexpectedPDU }
        switch code {
        case "AE-1": return [.openTransport]
        case "AE-2": return [.send(.associateRequest(request))]
        case "AE-3": return [.indicate(.associateAccepted(accept))]
        case "AE-4": return [.indicate(.associateRejected(reject)), .closeTransport]
        case "AE-5": return [.startARTIM]
        case "AE-6": return [.stopARTIM, .indicate(.associateRequested(request))]
        case "AE-7": return [.send(.associateAccept(accept))]
        case "AE-8": return [.send(.associateReject(reject)), .startARTIM]
        case "DT-1", "AR-7": return [.send(.data(values))]
        case "DT-2", "AR-6": return [.indicate(.data(values))]
        case "AR-1": return [.send(.releaseRequest)]
        case "AR-2", "AR-8": return [.indicate(.releaseRequested)]
        case "AR-3": return [.indicate(.releaseConfirmed), .closeTransport]
        case "AR-4": return [.send(.releaseResponse), .startARTIM]
        case "AR-5", "AA-5": return [.stopARTIM]
        case "AR-9": return [.send(.releaseResponse)]
        case "AR-10": return [.indicate(.releaseConfirmed)]
        case "AA-1": return [.send(.abort(DICOMAbort(source: .serviceUser))), .startARTIM]
        case "AA-2":
            if case .abortPDU = event { return [.stopARTIM, .closeTransport] }
            return [.closeTransport]
        case "AA-3": return [.indicate(.aborted), .closeTransport]
        case "AA-4": return [.indicate(.providerAborted(.notSpecified))]
        case "AA-6": return []
        case "AA-7": return [.send(.abort(DICOMAbort(source: .serviceProvider, reason: providerAbort)))]
        case "AA-8":
            return [.send(.abort(DICOMAbort(source: .serviceProvider, reason: providerAbort))),
                    .indicate(.providerAborted(providerAbort)), .startARTIM]
        default: fatalError(code)
        }
    }

    func testEveryCellOfTable9_10() {
        let events: [(String, Machine.Event)] = [
            ("Evt1", .associateRequestPrimitive(request)), ("Evt2", .transportConnectConfirm),
            ("Evt3", .associateAcceptPDU(accept)), ("Evt4", .associateRejectPDU(reject)),
            ("Evt5", .transportConnectIndication), ("Evt6", .associateRequestPDU(request)),
            ("Evt7", .associateAcceptPrimitive(accept)), ("Evt8", .associateRejectPrimitive(reject)),
            ("Evt9", .dataPrimitive(values)), ("Evt10", .dataPDU(values)), ("Evt11", .releaseRequestPrimitive),
            ("Evt12", .releaseRequestPDU), ("Evt13", .releaseResponsePDU), ("Evt14", .releaseResponsePrimitive),
            ("Evt15", .abortRequestPrimitive), ("Evt16", .abortPDU(DICOMAbort(source: .serviceUser))),
            ("Evt17", .transportClosed), ("Evt18", .artimExpired), ("Evt19", .invalidPDU(.invalidPDUParameterValue)),
        ]
        // Table 9-10 as published: event -> state -> (action, next state).
        let aa8: [Int: (String, Int)] = Dictionary(uniqueKeysWithValues: [3, 5, 6, 7, 8, 9, 10, 11, 12].map { ($0, ("AA-8", 13)) })
        func pduRow(_ special: [Int: (String, Int)]) -> [Int: (String, Int)] {
            var row = aa8
            row[2] = ("AA-1", 13)
            row[13] = ("AA-6", 13)
            special.forEach { row[$0.key] = $0.value }
            return row
        }
        let table: [String: [Int: (String, Int)]] = [
            "Evt1": [1: ("AE-1", 4)],
            "Evt2": [4: ("AE-2", 5)],
            "Evt3": pduRow([5: ("AE-3", 6)]),
            "Evt4": pduRow([5: ("AE-4", 1)]),
            "Evt5": [1: ("AE-5", 2)],
            "Evt6": pduRow([2: ("AE-6", 3), 13: ("AA-7", 13)]),
            "Evt7": [3: ("AE-7", 6)],
            "Evt8": [3: ("AE-8", 13)],
            "Evt9": [6: ("DT-1", 6), 8: ("AR-7", 8)],
            "Evt10": pduRow([6: ("DT-2", 6), 7: ("AR-6", 7)]),
            "Evt11": [6: ("AR-1", 7)],
            "Evt12": pduRow([6: ("AR-2", 8)]),
            "Evt13": pduRow([7: ("AR-3", 1), 10: ("AR-10", 12), 11: ("AR-3", 1)]),
            "Evt14": [8: ("AR-4", 13), 9: ("AR-9", 11), 12: ("AR-4", 13)],
            "Evt15": Dictionary(uniqueKeysWithValues: [3, 5, 6, 7, 8, 9, 10, 11, 12].map { ($0, ("AA-1", 13)) })
                .merging([4: ("AA-2", 1)]) { $1 },
            "Evt16": Dictionary(uniqueKeysWithValues: [3, 5, 6, 7, 8, 9, 10, 11, 12].map { ($0, ("AA-3", 1)) })
                .merging([2: ("AA-2", 1), 13: ("AA-2", 1)]) { $1 },
            "Evt17": Dictionary(uniqueKeysWithValues: (3...12).map { ($0, ("AA-4", 1)) })
                .merging([2: ("AA-5", 1), 13: ("AR-5", 1)]) { $1 },
            "Evt18": [2: ("AA-2", 1), 13: ("AA-2", 1)],
            "Evt19": pduRow([13: ("AA-7", 13)]),
        ]

        for (name, event) in events {
            for stateNumber in 1...13 {
                let state = Machine.State(rawValue: stateNumber)!
                for role in [Machine.Role.requestor, .acceptor] {
                    var machine = Machine(role: role, state: state)
                    if case .transportConnectConfirm = event {
                        // AE-2 sends the request kept by AE-1.
                        machine = Machine(role: .requestor)
                        _ = machine.handle(.associateRequestPrimitive(request))
                        guard stateNumber == 4 else { continue }
                    }
                    let produced = machine.handle(event)
                    let label = "\(name) in Sta\(stateNumber) as \(role)"
                    var cell = table[name]![stateNumber]
                    // AR-8 depends on the role (Sta9 for the requestor).
                    if name == "Evt12", stateNumber == 7 { cell = ("AR-8", role == .requestor ? 9 : 10) }
                    // Evt1 and Evt5 are local to one role.
                    if (name == "Evt1" && role == .acceptor) || (name == "Evt5" && role == .requestor) { cell = nil }
                    guard let (code, next) = cell else {
                        XCTAssertEqual(produced, [], label)
                        XCTAssertEqual(machine.state, state, label)
                        continue
                    }
                    XCTAssertEqual(produced, actions(code, event: event), label)
                    XCTAssertEqual(machine.state.rawValue, next, label)
                }
            }
        }
    }

    func testRequestorAndAcceptorConversation() {
        var requestor = Machine(role: .requestor)
        var acceptor = Machine(role: .acceptor)
        XCTAssertEqual(requestor.handle(.associateRequestPrimitive(request)), [.openTransport])
        XCTAssertEqual(acceptor.handle(.transportConnectIndication), [.startARTIM])
        XCTAssertEqual(requestor.handle(.transportConnectConfirm), [.send(.associateRequest(request))])
        XCTAssertEqual(acceptor.handle(.init(received: .associateRequest(request))),
                       [.stopARTIM, .indicate(.associateRequested(request))])
        XCTAssertEqual(acceptor.handle(.associateAcceptPrimitive(accept)), [.send(.associateAccept(accept))])
        XCTAssertEqual(requestor.handle(.init(received: .associateAccept(accept))), [.indicate(.associateAccepted(accept))])
        XCTAssertEqual(requestor.handle(.dataPrimitive(values)), [.send(.data(values))])
        XCTAssertEqual(acceptor.handle(.init(received: .data(values))), [.indicate(.data(values))])
        XCTAssertEqual(requestor.handle(.releaseRequestPrimitive), [.send(.releaseRequest)])
        XCTAssertEqual(acceptor.handle(.init(received: .releaseRequest)), [.indicate(.releaseRequested)])
        XCTAssertEqual(acceptor.handle(.releaseResponsePrimitive), [.send(.releaseResponse), .startARTIM])
        XCTAssertEqual(requestor.handle(.init(received: .releaseResponse)), [.indicate(.releaseConfirmed), .closeTransport])
        XCTAssertEqual(requestor.state, .idle)
        XCTAssertEqual(acceptor.handle(.transportClosed), [.stopARTIM])
        XCTAssertEqual(acceptor.state, .idle)
    }

    func testReleaseCollision() {
        // Both sides request release at once (PS3.8 Figure 9-2... collision).
        var requestor = Machine(role: .requestor, state: .established)
        var acceptor = Machine(role: .acceptor, state: .established)
        _ = requestor.handle(.releaseRequestPrimitive)
        _ = acceptor.handle(.releaseRequestPrimitive)
        XCTAssertEqual(requestor.handle(.releaseRequestPDU), [.indicate(.releaseRequested)])
        XCTAssertEqual(acceptor.handle(.releaseRequestPDU), [.indicate(.releaseRequested)])
        XCTAssertEqual(requestor.state, .releaseCollisionRequestorAwaitingLocalResponse)
        XCTAssertEqual(acceptor.state, .releaseCollisionAcceptorAwaitingReleaseResponse)
        // The requestor answers first.
        XCTAssertEqual(requestor.handle(.releaseResponsePrimitive), [.send(.releaseResponse)])
        XCTAssertEqual(acceptor.handle(.releaseResponsePDU), [.indicate(.releaseConfirmed)])
        XCTAssertEqual(acceptor.handle(.releaseResponsePrimitive), [.send(.releaseResponse), .startARTIM])
        XCTAssertEqual(requestor.handle(.releaseResponsePDU), [.indicate(.releaseConfirmed), .closeTransport])
        XCTAssertEqual(requestor.state, .idle)
        XCTAssertEqual(acceptor.state, .awaitingTransportClose)
    }
}
