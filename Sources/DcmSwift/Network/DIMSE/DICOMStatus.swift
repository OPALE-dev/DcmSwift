/// A DIMSE status (PS3.7 Annex C) and its category.
public struct DICOMStatus: Hashable, Sendable, CustomStringConvertible {
    public enum Category: Sendable {
        case success
        case pending
        case cancel
        case warning
        case failure
    }

    public let code: UInt16

    public init(code: UInt16) { self.code = code }

    /// The category (PS3.7 C.1 to C.4 and the service-specific annexes).
    public var category: Category {
        switch code {
        case 0x0000: return .success
        case 0xFF00, 0xFF01: return .pending
        case 0xFE00: return .cancel
        case 0x0001, 0x0107, 0x0116, 0xB000...0xBFFF: return .warning
        default: return .failure
        }
    }

    public var isSuccess: Bool { category == .success }
    public var isPending: Bool { category == .pending }

    // General (PS3.7 C.4).
    public static let success = DICOMStatus(code: 0x0000)
    public static let pending = DICOMStatus(code: 0xFF00)
    /// Pending: one or more optional keys were not supported (C-FIND).
    public static let pendingWithWarnings = DICOMStatus(code: 0xFF01)
    public static let cancel = DICOMStatus(code: 0xFE00)
    public static let attributeListError = DICOMStatus(code: 0x0107)
    public static let attributeValueOutOfRange = DICOMStatus(code: 0x0116)
    public static let sopClassNotSupported = DICOMStatus(code: 0x0122)
    public static let classInstanceConflict = DICOMStatus(code: 0x0119)
    public static let duplicateSOPInstance = DICOMStatus(code: 0x0111)
    public static let duplicateInvocation = DICOMStatus(code: 0x0210)
    public static let invalidArgumentValue = DICOMStatus(code: 0x0115)
    public static let invalidAttributeValue = DICOMStatus(code: 0x0106)
    public static let invalidObjectInstance = DICOMStatus(code: 0x0117)
    public static let missingAttribute = DICOMStatus(code: 0x0120)
    public static let missingAttributeValue = DICOMStatus(code: 0x0121)
    public static let mistypedArgument = DICOMStatus(code: 0x0212)
    public static let noSuchArgument = DICOMStatus(code: 0x0114)
    public static let noSuchAttribute = DICOMStatus(code: 0x0105)
    public static let noSuchEventType = DICOMStatus(code: 0x0113)
    public static let noSuchActionType = DICOMStatus(code: 0x0123)
    public static let noSuchObjectInstance = DICOMStatus(code: 0x0112)
    public static let noSuchSOPClass = DICOMStatus(code: 0x0118)
    public static let processingFailure = DICOMStatus(code: 0x0110)
    public static let resourceLimitation = DICOMStatus(code: 0x0213)
    public static let unrecognizedOperation = DICOMStatus(code: 0x0211)
    public static let notAuthorized = DICOMStatus(code: 0x0124)

    // Storage (PS3.4 B.2.3).
    public static let storageOutOfResources = DICOMStatus(code: 0xA700)
    public static let storageDataSetDoesNotMatchSOPClass = DICOMStatus(code: 0xA900)
    public static let storageCannotUnderstand = DICOMStatus(code: 0xC000)
    public static let storageCoercionOfDataElements = DICOMStatus(code: 0xB000)
    public static let storageDataSetDoesNotMatchSOPClassWarning = DICOMStatus(code: 0xB007)
    public static let storageElementsDiscarded = DICOMStatus(code: 0xB006)

    // Query/Retrieve (PS3.4 C.4).
    public static let queryOutOfResources = DICOMStatus(code: 0xA700)
    public static let identifierDoesNotMatchSOPClass = DICOMStatus(code: 0xA900)
    public static let unableToProcess = DICOMStatus(code: 0xC000)
    public static let retrieveOutOfResourcesForMatches = DICOMStatus(code: 0xA701)
    public static let retrieveOutOfResourcesForSuboperations = DICOMStatus(code: 0xA702)
    public static let moveDestinationUnknown = DICOMStatus(code: 0xA801)
    public static let suboperationsCompleteWithFailures = DICOMStatus(code: 0xB000)

    public var description: String { String(format: "0x%04X", code) }
}
