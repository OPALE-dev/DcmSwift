import Foundation
import NIOSSL

/// What a DICOMweb service knows about the request it performs.
public struct DICOMwebRequestContext: Sendable {
    /// The user agent's address, when known.
    public let remoteAddress: String?
    /// The request header fields, such as Authorization.
    public let headers: DICOMwebMultipart.Headers
    /// The certificate the user agent presented over TLS.
    public let peerCertificate: NIOSSLCertificate?
    /// The Base URI of the service, used in Retrieve URLs.
    public let baseURI: String

    public init(remoteAddress: String? = nil, headers: DICOMwebMultipart.Headers = .init(),
                peerCertificate: NIOSSLCertificate? = nil, baseURI: String) {
        self.remoteAddress = remoteAddress
        self.headers = headers
        self.peerCertificate = peerCertificate
        self.baseURI = baseURI
    }
}

/// Answers the Search Transaction (QIDO-RS, PS3.18 10.6).
public protocol DICOMwebSearchService: Sendable {
    /// The matches of `identifier`, a C-FIND identifier at `level` holding
    /// the matching keys and the return keys (PS3.4 C.4.1). The origin server
    /// adds Retrieve URLs and applies `offset` and `limit`; matches must come
    /// in a stable order so pages are consistent (PS3.18 8.3.4.4.1).
    func search(
        _ identifier: DataSet, level: DICOMwebSearchLevel, query: DICOMwebSearchQuery, context: DICOMwebRequestContext
    ) async throws -> [DataSet]
}

/// Answers the Retrieve Transaction (WADO-RS, PS3.18 10.4).
public protocol DICOMwebRetrieveService: Sendable {
    /// The instances of a study, of one of its series, or one instance;
    /// empty when the resource does not exist.
    func instances(
        study: String, series: String?, instance: String?, context: DICOMwebRequestContext
    ) async throws -> [DICOMRetrieveItem]
}

/// The outcome of storing one instance (PS3.18 Annex I).
public enum DICOMwebStoreResult: Equatable, Sendable {
    case stored
    /// Stored with a Warning Reason (0008,1196), such as
    /// `DICOMwebStoreResponse.coercionOfDataElements`.
    case storedWithWarning(UInt16)
    /// Not stored, with a Failure Reason (0008,1197).
    case failed(UInt16)
}

/// Answers the Store Transaction (STOW-RS, PS3.18 10.5).
public protocol DICOMwebStoreService: Sendable {
    /// Stores an instance received in a request payload.
    func store(_ instance: DICOMReceivedInstance, context: DICOMwebRequestContext) async throws -> DICOMwebStoreResult
}

/// The Store Instances Response Module (PS3.18 Annex I).
public struct DICOMwebStoreResponse: Equatable, Sendable {
    public struct Reference: Equatable, Sendable {
        public var sopClassUID: String
        public var sopInstanceUID: String
        public var retrieveURL: String?
        /// Warning Reason (0008,1196) of a stored instance, or Failure
        /// Reason (0008,1197) of a failed one.
        public var reason: UInt16?

        public init(sopClassUID: String, sopInstanceUID: String, retrieveURL: String? = nil, reason: UInt16? = nil) {
            self.sopClassUID = sopClassUID
            self.sopInstanceUID = sopInstanceUID
            self.retrieveURL = retrieveURL
            self.reason = reason
        }
    }

    /// Retrieve URL (0008,1190) of the study.
    public var retrieveURL: String?
    /// Referenced SOP Sequence (0008,1199): stored instances.
    public var stored: [Reference] = []
    /// Failed SOP Sequence (0008,1198).
    public var failed: [Reference] = []
    /// Other Failures Sequence (0008,119A): Failure Reasons not tied to an
    /// instance, such as a part that is not a DICOM instance.
    public var otherFailures: [UInt16] = []

    public init(retrieveURL: String? = nil, stored: [Reference] = [], failed: [Reference] = [], otherFailures: [UInt16] = []) {
        self.retrieveURL = retrieveURL
        self.stored = stored
        self.failed = failed
        self.otherFailures = otherFailures
    }

    // Warning Reasons (PS3.18 Table I.2-1).
    public static let coercionOfDataElements: UInt16 = 0xB000
    public static let elementsDiscarded: UInt16 = 0xB006
    public static let dataSetDoesNotMatchSOPClassWarning: UInt16 = 0xB007
    // Failure Reasons (PS3.18 Table I.2-2).
    public static let refusedOutOfResources: UInt16 = 0xA700
    public static let dataSetDoesNotMatchSOPClass: UInt16 = 0xA900
    public static let cannotUnderstand: UInt16 = 0xC000
    public static let transferSyntaxNotSupported: UInt16 = 0xC122
    public static let processingFailure: UInt16 = 0x0110
    public static let sopClassNotSupported: UInt16 = 0x0122
    /// Implementation-specific "cannot understand" reason: the Study
    /// Instance UID differs from the one of the Target Resource.
    public static let studyInstanceUIDMismatch: UInt16 = 0xC409

    /// The HTTP status of the response (PS3.18 Table 10.5.3-1): 200 when
    /// every instance is stored without warning, 202 when some are stored,
    /// and 409 when none is.
    public var httpStatus: Int {
        if stored.isEmpty { return 409 }
        if failed.isEmpty && otherFailures.isEmpty && stored.allSatisfy({ $0.reason == nil }) { return 200 }
        return 202
    }

    /// The module as a data set.
    public var dataSet: DataSet {
        let dataSet = DataSet()
        dataSet.vrMethod = .Explicit
        dataSet.byteOrder = .LittleEndian
        if let retrieveURL { _ = dataSet.set(value: retrieveURL, forTagName: "RetrieveURL") }
        func items(_ references: [Reference], reasonKeyword: String) -> [[String: Any]] {
            references.map { reference in
                var item: [String: Any] = [
                    "00081150": ["vr": "UI", "Value": [reference.sopClassUID]],
                    "00081155": ["vr": "UI", "Value": [reference.sopInstanceUID]],
                ]
                if let url = reference.retrieveURL { item["00081190"] = ["vr": "UR", "Value": [url]] }
                if let reason = reference.reason {
                    item[reasonKeyword == "FailureReason" ? "00081197" : "00081196"] = ["vr": "US", "Value": [Int(reason)]]
                }
                return item
            }
        }
        var object: [String: Any] = [:]
        if !failed.isEmpty { object["00081198"] = ["vr": "SQ", "Value": items(failed, reasonKeyword: "FailureReason")] }
        if !stored.isEmpty { object["00081199"] = ["vr": "SQ", "Value": items(stored, reasonKeyword: "WarningReason")] }
        if !otherFailures.isEmpty {
            object["0008119A"] = ["vr": "SQ", "Value": otherFailures.map { ["00081197": ["vr": "US", "Value": [Int($0)]]] }]
        }
        if let sequences = try? DICOMJSON.dataSet(object) {
            for element in sequences.allElements { dataSet.add(element: element) }
            dataSet.sortElements()
        }
        return dataSet
    }

    /// Reads the module from a data set, such as a decoded response.
    public init(dataSet: DataSet) throws {
        let object = try DICOMJSON.object(dataSet)
        func string(_ attribute: Any?) -> String? {
            ((attribute as? [String: Any])?["Value"] as? [Any])?.first as? String
        }
        func number(_ attribute: Any?) -> UInt16? {
            guard let value = ((attribute as? [String: Any])?["Value"] as? [Any])?.first else { return nil }
            if let number = value as? NSNumber { return UInt16(truncating: number) }
            return (value as? String).flatMap { UInt16($0) }
        }
        func references(_ key: String, reason: String) -> [Reference] {
            let items = ((object[key] as? [String: Any])?["Value"] as? [[String: Any]]) ?? []
            return items.map {
                Reference(sopClassUID: string($0["00081150"]) ?? "", sopInstanceUID: string($0["00081155"]) ?? "",
                          retrieveURL: string($0["00081190"]), reason: number($0[reason]))
            }
        }
        retrieveURL = string(object["00081190"])
        stored = references("00081199", reason: "00081196")
        failed = references("00081198", reason: "00081197")
        otherFailures = (((object["0008119A"] as? [String: Any])?["Value"] as? [[String: Any]]) ?? [])
            .compactMap { number($0["00081197"]) }
    }
}
