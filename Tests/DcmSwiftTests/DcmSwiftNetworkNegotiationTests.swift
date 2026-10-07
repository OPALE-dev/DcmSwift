import XCTest
@testable import DcmSwift

/// Association negotiation (PS3.8 7.1, PS3.7 D.3.3).
final class DcmSwiftNetworkNegotiationTests: XCTestCase {
    private let ct = "1.2.840.10008.5.1.4.1.1.2"
    private let echo = "1.2.840.10008.1.1"
    private let implicit = "1.2.840.10008.1.2"
    private let explicit = "1.2.840.10008.1.2.1"
    private let jpegLS = "1.2.840.10008.1.2.4.80"

    private var policy: DICOMAcceptorPolicy {
        DICOMAcceptorPolicy(aeTitle: "SCP", abstractSyntaxes: [
            echo: DICOMAbstractSyntaxSupport(transferSyntaxes: [implicit]),
            ct: DICOMAbstractSyntaxSupport(transferSyntaxes: [jpegLS, explicit, implicit], scpRole: true, scuRole: true),
        ], maximumLength: 32768)
    }

    private func request(_ contexts: [DICOMPresentationContextProposal], roles: [DICOMRoleSelection] = [],
                         window: DICOMAsynchronousOperationsWindow? = nil) -> DICOMAssociateRequest {
        DICOMAssociateRequest(
            calledAETitle: "SCP", callingAETitle: "SCU", presentationContexts: contexts,
            userInformation: DICOMUserInformation(
                maximumLength: 16384, implementationClassUID: "1.2.3", asynchronousOperationsWindow: window,
                roleSelections: roles))
    }

    func testPresentationContextsAreAcceptedWithThePreferredTransferSyntax() throws {
        let rq = request([
            DICOMPresentationContextProposal(id: 1, abstractSyntax: echo, transferSyntaxes: [explicit, implicit]),
            DICOMPresentationContextProposal(id: 3, abstractSyntax: ct, transferSyntaxes: [implicit, explicit, jpegLS]),
            DICOMPresentationContextProposal(id: 5, abstractSyntax: "1.2.840.10008.5.1.4.1.1.4", transferSyntaxes: [implicit]),
            DICOMPresentationContextProposal(id: 7, abstractSyntax: echo, transferSyntaxes: ["1.2.840.10008.1.2.4.50"]),
            DICOMPresentationContextProposal(id: 8, abstractSyntax: echo, transferSyntaxes: [implicit]),
            DICOMPresentationContextProposal(id: 3, abstractSyntax: echo, transferSyntaxes: [implicit]),
        ])
        let (accept, negotiated) = try DICOMAssociationNegotiator.respond(to: rq, policy: policy).get()
        XCTAssertEqual(accept.presentationContexts.map(\.result),
                       [.acceptance, .acceptance, .abstractSyntaxNotSupported, .transferSyntaxesNotSupported,
                        .noReason, .noReason])
        XCTAssertEqual(accept.presentationContexts[0].transferSyntax, implicit)
        XCTAssertEqual(accept.presentationContexts[1].transferSyntax, jpegLS, "the acceptor's preference")
        XCTAssertEqual(accept.userInformation.maximumLength, 32768)
        XCTAssertEqual(accept.userInformation.implementationClassUID, DICOMImplementation.classUID)
        XCTAssertEqual(Set(negotiated.presentationContexts.keys), [1, 3])
        XCTAssertEqual(negotiated.requestorMaximumLength, 16384)

        // The requestor sees the same agreement.
        let requestorView = try DICOMAssociationNegotiator.negotiated(request: rq, accept: accept)
        XCTAssertEqual(requestorView.presentationContexts, negotiated.presentationContexts)
        XCTAssertEqual(requestorView.contexts(for: ct).map(\.transferSyntax), [jpegLS])
    }

    func testAssociationRejections() {
        func reason(_ rq: DICOMAssociateRequest, _ policy: DICOMAcceptorPolicy) -> DICOMAssociateReject.Reason? {
            if case .failure(let reject) = DICOMAssociationNegotiator.respond(to: rq, policy: policy) { return reject.reason }
            return nil
        }
        let contexts = [DICOMPresentationContextProposal(id: 1, abstractSyntax: echo, transferSyntaxes: [implicit])]
        var rq = request(contexts)
        rq.calledAETitle = "OTHER"
        XCTAssertEqual(reason(rq, policy), .calledAETitleNotRecognized)
        var open = policy
        open.acceptsAnyCalledAETitle = true
        XCTAssertNil(reason(rq, open))

        rq = request(contexts)
        var restricted = policy
        restricted.allowedCallingAETitles = ["TRUSTED"]
        XCTAssertEqual(reason(rq, restricted), .callingAETitleNotRecognized)
        rq.applicationContextName = "1.2.3"
        XCTAssertEqual(reason(rq, policy), .applicationContextNameNotSupported)
        rq = request(contexts)
        rq.protocolVersion = 2
        XCTAssertEqual(reason(rq, policy), .protocolVersionNotSupported)

        var authenticated = policy
        authenticated.authenticate = { identity in
            identity == .username("alice", passcode: "secret", positiveResponseRequested: true) ? Array("ok".utf8) : nil
        }
        rq = request(contexts)
        XCTAssertEqual(reason(rq, authenticated), .noReasonGiven)
        rq.userInformation.userIdentity = .username("alice", passcode: "secret", positiveResponseRequested: true)
        guard case .success(let (accept, negotiated)) = DICOMAssociationNegotiator.respond(to: rq, policy: authenticated) else {
            return XCTFail("refused")
        }
        XCTAssertEqual(accept.userInformation.userIdentityServerResponse, Array("ok".utf8))
        XCTAssertEqual(negotiated.userIdentity?.primaryField, Array("alice".utf8))
    }

    func testRoleSelectionAndAsynchronousWindow() throws {
        let rq = request(
            [DICOMPresentationContextProposal(id: 1, abstractSyntax: ct, transferSyntaxes: [implicit]),
             DICOMPresentationContextProposal(id: 3, abstractSyntax: echo, transferSyntaxes: [implicit])],
            roles: [DICOMRoleSelection(sopClassUID: ct, scuRole: false, scpRole: true),
                    DICOMRoleSelection(sopClassUID: echo, scuRole: true, scpRole: true)],
            window: DICOMAsynchronousOperationsWindow(maximumInvoked: 5, maximumPerformed: 0))
        var asynchronous = policy
        asynchronous.maximumOperationsPerformed = 3
        let (accept, negotiated) = try DICOMAssociationNegotiator.respond(to: rq, policy: asynchronous).get()
        // CT: the requestor acts as SCP only (a C-GET retrieval); echo:
        // the acceptor does not act as SCU for it.
        XCTAssertEqual(accept.userInformation.roleSelections, [
            DICOMRoleSelection(sopClassUID: ct, scuRole: false, scpRole: true),
            DICOMRoleSelection(sopClassUID: echo, scuRole: true, scpRole: false),
        ])
        XCTAssertEqual(negotiated.presentationContexts[1]?.requestorIsSCP, true)
        XCTAssertEqual(negotiated.presentationContexts[1]?.requestorIsSCU, false)
        XCTAssertEqual(accept.userInformation.asynchronousOperationsWindow,
                       DICOMAsynchronousOperationsWindow(maximumInvoked: 3, maximumPerformed: 3))
        let requestorView = try DICOMAssociationNegotiator.negotiated(request: rq, accept: accept)
        XCTAssertEqual(requestorView.presentationContexts, negotiated.presentationContexts)
        XCTAssertEqual(requestorView.asynchronousOperationsWindow.maximumInvoked, 3)

        // Without asynchronous support the window is omitted (1, 1).
        let (synchronous, _) = try DICOMAssociationNegotiator.respond(to: rq, policy: policy).get()
        XCTAssertNil(synchronous.userInformation.asynchronousOperationsWindow)
    }

    func testInconsistentAcceptsAreProtocolErrors() throws {
        let rq = request([DICOMPresentationContextProposal(id: 1, abstractSyntax: echo, transferSyntaxes: [implicit])])
        var accept = try DICOMAssociationNegotiator.respond(to: rq, policy: policy).get().0
        accept.presentationContexts[0].transferSyntax = explicit
        XCTAssertThrowsError(try DICOMAssociationNegotiator.negotiated(request: rq, accept: accept))
        accept.presentationContexts[0] = DICOMPresentationContextResult(id: 9, result: .acceptance, transferSyntax: implicit)
        XCTAssertThrowsError(try DICOMAssociationNegotiator.negotiated(request: rq, accept: accept))
    }
}
