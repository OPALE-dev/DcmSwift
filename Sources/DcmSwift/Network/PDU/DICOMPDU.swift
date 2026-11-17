import NIOCore

/// A DICOM Upper Layer Protocol Data Unit (PS3.8 9.3).
public enum DICOMPDU: Equatable, Sendable {
    case associateRequest(DICOMAssociateRequest)
    case associateAccept(DICOMAssociateAccept)
    case associateReject(DICOMAssociateReject)
    case data([DICOMPresentationDataValue])
    case releaseRequest
    case releaseResponse
    case abort(DICOMAbort)

    /// The PDU type (PS3.8 Table 9-11 and following).
    public var type: UInt8 {
        switch self {
        case .associateRequest: return 0x01
        case .associateAccept: return 0x02
        case .associateReject: return 0x03
        case .data: return 0x04
        case .releaseRequest: return 0x05
        case .releaseResponse: return 0x06
        case .abort: return 0x07
        }
    }
}

/// The DICOM Application Context Name (PS3.7 Annex A.2.1).
public let dicomApplicationContextName = "1.2.840.10008.3.1.1.1"

/// A-ASSOCIATE-RQ PDU (PS3.8 9.3.2).
public struct DICOMAssociateRequest: Equatable, Sendable {
    /// Protocol version: bit 0 set for version 1.
    public var protocolVersion: UInt16
    public var calledAETitle: String
    public var callingAETitle: String
    public var applicationContextName: String
    public var presentationContexts: [DICOMPresentationContextProposal]
    public var userInformation: DICOMUserInformation

    public init(
        calledAETitle: String, callingAETitle: String,
        presentationContexts: [DICOMPresentationContextProposal], userInformation: DICOMUserInformation,
        applicationContextName: String = dicomApplicationContextName, protocolVersion: UInt16 = 1
    ) {
        self.protocolVersion = protocolVersion
        self.calledAETitle = calledAETitle
        self.callingAETitle = callingAETitle
        self.applicationContextName = applicationContextName
        self.presentationContexts = presentationContexts
        self.userInformation = userInformation
    }
}

/// A-ASSOCIATE-AC PDU (PS3.8 9.3.3). The AE titles are those of the request,
/// returned unchanged.
public struct DICOMAssociateAccept: Equatable, Sendable {
    public var protocolVersion: UInt16
    public var calledAETitle: String
    public var callingAETitle: String
    public var applicationContextName: String
    public var presentationContexts: [DICOMPresentationContextResult]
    public var userInformation: DICOMUserInformation

    public init(
        calledAETitle: String, callingAETitle: String,
        presentationContexts: [DICOMPresentationContextResult], userInformation: DICOMUserInformation,
        applicationContextName: String = dicomApplicationContextName, protocolVersion: UInt16 = 1
    ) {
        self.protocolVersion = protocolVersion
        self.calledAETitle = calledAETitle
        self.callingAETitle = callingAETitle
        self.applicationContextName = applicationContextName
        self.presentationContexts = presentationContexts
        self.userInformation = userInformation
    }
}

/// A-ASSOCIATE-RJ PDU (PS3.8 9.3.4, Table 9-21).
public struct DICOMAssociateReject: Equatable, Sendable, Error {
    public enum Result: UInt8, Sendable {
        case permanent = 1
        case transient = 2
    }

    /// The rejecting party and its reason.
    public enum Reason: Equatable, Sendable {
        /// DICOM UL service-user (source 1).
        case noReasonGiven
        case applicationContextNameNotSupported
        case callingAETitleNotRecognized
        case calledAETitleNotRecognized
        /// DICOM UL service-provider, ACSE related (source 2).
        case acseNoReasonGiven
        case protocolVersionNotSupported
        /// DICOM UL service-provider, presentation related (source 3).
        case temporaryCongestion
        case localLimitExceeded
        /// A source and reason pair this list does not name.
        case other(source: UInt8, reason: UInt8)

        public init(source: UInt8, reason: UInt8) {
            switch (source, reason) {
            case (1, 1): self = .noReasonGiven
            case (1, 2): self = .applicationContextNameNotSupported
            case (1, 3): self = .callingAETitleNotRecognized
            case (1, 7): self = .calledAETitleNotRecognized
            case (2, 1): self = .acseNoReasonGiven
            case (2, 2): self = .protocolVersionNotSupported
            case (3, 2): self = .temporaryCongestion
            case (3, 3): self = .localLimitExceeded
            default: self = .other(source: source, reason: reason)
            }
        }

        public var source: UInt8 {
            switch self {
            case .noReasonGiven, .applicationContextNameNotSupported, .callingAETitleNotRecognized,
                 .calledAETitleNotRecognized: return 1
            case .acseNoReasonGiven, .protocolVersionNotSupported: return 2
            case .temporaryCongestion, .localLimitExceeded: return 3
            case .other(let source, _): return source
            }
        }

        public var reason: UInt8 {
            switch self {
            case .noReasonGiven, .acseNoReasonGiven: return 1
            case .applicationContextNameNotSupported, .protocolVersionNotSupported, .temporaryCongestion: return 2
            case .callingAETitleNotRecognized, .localLimitExceeded: return 3
            case .calledAETitleNotRecognized: return 7
            case .other(_, let reason): return reason
            }
        }
    }

    public var result: Result
    public var reason: Reason

    public init(result: Result, reason: Reason) {
        self.result = result
        self.reason = reason
    }
}

/// A-ABORT PDU (PS3.8 9.3.8, Table 9-26).
public struct DICOMAbort: Equatable, Sendable, Error {
    public enum Source: UInt8, Sendable {
        case serviceUser = 0
        case reserved = 1
        case serviceProvider = 2
    }

    public enum Reason: UInt8, Sendable {
        case notSpecified = 0
        case unrecognizedPDU = 1
        case unexpectedPDU = 2
        case reserved = 3
        case unrecognizedPDUParameter = 4
        case unexpectedPDUParameter = 5
        case invalidPDUParameterValue = 6
    }

    public var source: Source
    /// Significant only when the source is the service provider.
    public var reason: Reason

    public init(source: Source, reason: Reason = .notSpecified) {
        self.source = source
        self.reason = reason
    }
}

/// A presentation context of an A-ASSOCIATE-RQ (PS3.8 9.3.2.2).
public struct DICOMPresentationContextProposal: Equatable, Sendable {
    /// Odd, from 1 to 255.
    public var id: UInt8
    public var abstractSyntax: String
    public var transferSyntaxes: [String]

    public init(id: UInt8, abstractSyntax: String, transferSyntaxes: [String]) {
        self.id = id
        self.abstractSyntax = abstractSyntax
        self.transferSyntaxes = transferSyntaxes
    }
}

/// A presentation context of an A-ASSOCIATE-AC (PS3.8 9.3.3.2, Table 9-18).
public struct DICOMPresentationContextResult: Equatable, Sendable {
    public enum Result: UInt8, Sendable {
        case acceptance = 0
        case userRejection = 1
        case noReason = 2
        case abstractSyntaxNotSupported = 3
        case transferSyntaxesNotSupported = 4
    }

    public var id: UInt8
    public var result: Result
    /// The accepted Transfer Syntax; not significant when rejected.
    public var transferSyntax: String

    public init(id: UInt8, result: Result, transferSyntax: String) {
        self.id = id
        self.result = result
        self.transferSyntax = transferSyntax
    }
}

/// A Presentation Data Value of a P-DATA-TF PDU (PS3.8 9.3.5.1, Annex E.2).
public struct DICOMPresentationDataValue: Equatable, Sendable {
    public var presentationContextID: UInt8
    /// A command fragment rather than a data set fragment.
    public var isCommand: Bool
    /// The last fragment of the command or data set.
    public var isLast: Bool
    public var data: ByteBuffer

    public init(presentationContextID: UInt8, isCommand: Bool, isLast: Bool, data: ByteBuffer) {
        self.presentationContextID = presentationContextID
        self.isCommand = isCommand
        self.isLast = isLast
        self.data = data
    }
}

/// The User Information item and its sub-items (PS3.8 9.3.2.3, PS3.7
/// Annex D.3.3).
public struct DICOMUserInformation: Equatable, Sendable {
    /// Maximum Length Received (D.1); 0 means no limit.
    public var maximumLength: UInt32?
    public var implementationClassUID: String?
    public var implementationVersionName: String?
    public var asynchronousOperationsWindow: DICOMAsynchronousOperationsWindow?
    public var roleSelections: [DICOMRoleSelection]
    public var extendedNegotiations: [DICOMExtendedNegotiation]
    public var commonExtendedNegotiations: [DICOMCommonExtendedNegotiation]
    /// User Identity Negotiation request (D.3.3.7.1).
    public var userIdentity: DICOMUserIdentity?
    /// User Identity Negotiation server response (D.3.3.7.2).
    public var userIdentityServerResponse: [UInt8]?
    /// Sub-items of other types, kept as received.
    public var unknownSubItems: [DICOMUnknownItem]

    public init(
        maximumLength: UInt32? = nil, implementationClassUID: String? = nil,
        implementationVersionName: String? = nil,
        asynchronousOperationsWindow: DICOMAsynchronousOperationsWindow? = nil,
        roleSelections: [DICOMRoleSelection] = [], extendedNegotiations: [DICOMExtendedNegotiation] = [],
        commonExtendedNegotiations: [DICOMCommonExtendedNegotiation] = [],
        userIdentity: DICOMUserIdentity? = nil, userIdentityServerResponse: [UInt8]? = nil,
        unknownSubItems: [DICOMUnknownItem] = []
    ) {
        self.maximumLength = maximumLength
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.asynchronousOperationsWindow = asynchronousOperationsWindow
        self.roleSelections = roleSelections
        self.extendedNegotiations = extendedNegotiations
        self.commonExtendedNegotiations = commonExtendedNegotiations
        self.userIdentity = userIdentity
        self.userIdentityServerResponse = userIdentityServerResponse
        self.unknownSubItems = unknownSubItems
    }
}

/// Asynchronous Operations Window (PS3.7 D.3.3.3); 0 means unlimited.
public struct DICOMAsynchronousOperationsWindow: Equatable, Sendable {
    public var maximumInvoked: UInt16
    public var maximumPerformed: UInt16

    public init(maximumInvoked: UInt16, maximumPerformed: UInt16) {
        self.maximumInvoked = maximumInvoked
        self.maximumPerformed = maximumPerformed
    }
}

/// SCP/SCU Role Selection (PS3.7 D.3.3.4).
public struct DICOMRoleSelection: Equatable, Sendable {
    public var sopClassUID: String
    public var scuRole: Bool
    public var scpRole: Bool

    public init(sopClassUID: String, scuRole: Bool, scpRole: Bool) {
        self.sopClassUID = sopClassUID
        self.scuRole = scuRole
        self.scpRole = scpRole
    }
}

/// SOP Class Extended Negotiation (PS3.7 D.3.3.5).
public struct DICOMExtendedNegotiation: Equatable, Sendable {
    public var sopClassUID: String
    public var applicationInformation: [UInt8]

    public init(sopClassUID: String, applicationInformation: [UInt8]) {
        self.sopClassUID = sopClassUID
        self.applicationInformation = applicationInformation
    }
}

/// SOP Class Common Extended Negotiation (PS3.7 D.3.3.6).
public struct DICOMCommonExtendedNegotiation: Equatable, Sendable {
    public var sopClassUID: String
    public var serviceClassUID: String
    public var relatedGeneralSOPClassUIDs: [String]

    public init(sopClassUID: String, serviceClassUID: String, relatedGeneralSOPClassUIDs: [String] = []) {
        self.sopClassUID = sopClassUID
        self.serviceClassUID = serviceClassUID
        self.relatedGeneralSOPClassUIDs = relatedGeneralSOPClassUIDs
    }
}

/// User Identity Negotiation request (PS3.7 D.3.3.7.1, Table D.3-14).
public struct DICOMUserIdentity: Equatable, Sendable {
    public enum Kind: UInt8, Sendable {
        case username = 1
        case usernameAndPasscode = 2
        case kerberos = 3
        case saml = 4
        case jwt = 5
    }

    public var kind: Kind
    public var positiveResponseRequested: Bool
    public var primaryField: [UInt8]
    /// The passcode, for `.usernameAndPasscode` only.
    public var secondaryField: [UInt8]

    public init(kind: Kind, positiveResponseRequested: Bool, primaryField: [UInt8], secondaryField: [UInt8] = []) {
        self.kind = kind
        self.positiveResponseRequested = positiveResponseRequested
        self.primaryField = primaryField
        self.secondaryField = secondaryField
    }

    public static func username(_ name: String, passcode: String? = nil, positiveResponseRequested: Bool = false) -> Self {
        DICOMUserIdentity(
            kind: passcode == nil ? .username : .usernameAndPasscode,
            positiveResponseRequested: positiveResponseRequested,
            primaryField: Array(name.utf8), secondaryField: Array((passcode ?? "").utf8))
    }
}

/// An item or sub-item of a type that PS3.8 does not define here.
public struct DICOMUnknownItem: Equatable, Sendable {
    public var type: UInt8
    public var value: [UInt8]

    public init(type: UInt8, value: [UInt8]) {
        self.type = type
        self.value = value
    }
}
