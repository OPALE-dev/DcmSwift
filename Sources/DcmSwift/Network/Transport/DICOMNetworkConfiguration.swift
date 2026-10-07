import Foundation
import NIOCore
import NIOSSL

/// A failure of the DICOM network layer.
public enum DICOMNetworkError: Error, Equatable, CustomStringConvertible {
    /// The peer rejected the association (A-ASSOCIATE-RJ).
    case associationRejected(DICOMAssociateReject)
    /// The peer aborted the association (A-ABORT).
    case associationAborted(DICOMAbort)
    /// The peer broke the protocol; the association was aborted.
    case protocolViolation(String)
    /// A timer expired; the association was aborted or closed.
    case timeout(String)
    /// The connection closed before the association ended normally.
    case connectionClosed
    /// No accepted presentation context fits the operation.
    case noPresentationContext(abstractSyntax: String)
    /// The operation is not possible in the association's current state.
    case invalidState(String)

    public var description: String {
        switch self {
        case .associationRejected(let reject): return "association rejected: \(reject.result), \(reject.reason)"
        case .associationAborted(let abort): return "association aborted by the \(abort.source): \(abort.reason)"
        case .protocolViolation(let message): return "protocol violation: \(message)"
        case .timeout(let message): return "timeout: \(message)"
        case .connectionClosed: return "connection closed"
        case .noPresentationContext(let uid): return "no accepted presentation context for \(uid)"
        case .invalidState(let message): return "invalid association state: \(message)"
        }
    }
}

/// Timers of an association. A nil interval disables the timer.
public struct DICOMNetworkTimeouts: Sendable {
    /// Establishing the TCP (and TLS) connection.
    public var connect: TimeAmount
    /// ARTIM (PS3.8 9.1.5): waiting for an A-ASSOCIATE-RQ or AC, or for the
    /// transport to close after release, rejection, or abort.
    public var artim: TimeAmount
    /// No data received for this long aborts the association; it bounds the
    /// wait for any DIMSE response.
    public var idle: TimeAmount?

    public init(connect: TimeAmount = .seconds(30), artim: TimeAmount = .seconds(30), idle: TimeAmount? = .seconds(120)) {
        self.connect = connect
        self.artim = artim
        self.idle = idle
    }
}

/// Resource bounds of an association.
public struct DICOMNetworkLimits: Sendable {
    /// The Maximum Length Received this side announces (PS3.8 D.1); also the
    /// largest P-DATA-TF accepted.
    public var maximumPDULength: UInt32
    /// The largest A-ASSOCIATE-RQ or AC accepted.
    public var maximumAssociatePDULength: Int
    /// The largest command set accepted.
    public var maximumCommandLength: Int
    /// Received data sets larger than this are kept in a temporary file.
    public var dataSetMemoryLimit: Int
    /// The largest data set accepted.
    public var maximumDataSetLength: Int
    /// Where large received data sets are spilled.
    public var temporaryDirectory: URL

    public init(
        maximumPDULength: UInt32 = 1 << 16, maximumAssociatePDULength: Int = 1 << 20,
        maximumCommandLength: Int = 1 << 16, dataSetMemoryLimit: Int = 16 << 20,
        maximumDataSetLength: Int = 4 << 30, temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.maximumPDULength = maximumPDULength
        self.maximumAssociatePDULength = maximumAssociatePDULength
        self.maximumCommandLength = maximumCommandLength
        self.dataSetMemoryLimit = dataSetMemoryLimit
        self.maximumDataSetLength = maximumDataSetLength
        self.temporaryDirectory = temporaryDirectory
    }

    func makeAssembler() -> DICOMMessageAssembler {
        DICOMMessageAssembler(
            maximumCommandLength: maximumCommandLength, memoryLimit: dataSetMemoryLimit,
            maximumDataSetLength: maximumDataSetLength, temporaryDirectory: temporaryDirectory)
    }
}

/// TLS for DICOM connections, following the BCP 195 TLS Secure Transport
/// Connection Profile of PS3.15 B.9: TLS 1.2 or later, certificate and host
/// name verification unless explicitly relaxed.
public struct DICOMTLSConfiguration: Sendable {
    /// The NIOSSL configuration, which callers may adjust.
    public var configuration: TLSConfiguration

    public init(configuration: TLSConfiguration) {
        self.configuration = configuration
    }

    /// A client: verifies the server against `trustRoots` (the system's by
    /// default) and its host name; presents a certificate when given one.
    public static func client(
        trustRoots: NIOSSLTrustRoots = .default,
        certificateChain: [NIOSSLCertificate] = [], privateKey: NIOSSLPrivateKey? = nil,
        verification: CertificateVerification = .fullVerification
    ) -> DICOMTLSConfiguration {
        var configuration = TLSConfiguration.makeClientConfiguration()
        configuration.minimumTLSVersion = .tlsv12
        configuration.trustRoots = trustRoots
        configuration.certificateVerification = verification
        configuration.certificateChain = certificateChain.map { .certificate($0) }
        configuration.privateKey = privateKey.map { .privateKey($0) }
        return DICOMTLSConfiguration(configuration: configuration)
    }

    /// A server presenting `certificateChain`; with `clientTrustRoots`, it
    /// requires and verifies client certificates (mutual authentication).
    public static func server(
        certificateChain: [NIOSSLCertificate], privateKey: NIOSSLPrivateKey,
        clientTrustRoots: NIOSSLTrustRoots? = nil
    ) -> DICOMTLSConfiguration {
        var configuration = TLSConfiguration.makeServerConfiguration(
            certificateChain: certificateChain.map { .certificate($0) }, privateKey: .privateKey(privateKey))
        configuration.minimumTLSVersion = .tlsv12
        if let clientTrustRoots {
            configuration.trustRoots = clientTrustRoots
            configuration.certificateVerification = .noHostnameVerification
        }
        return DICOMTLSConfiguration(configuration: configuration)
    }
}

/// A remote application entity.
public struct DICOMRemoteNode: Hashable, Sendable {
    public var aeTitle: String
    public var host: String
    public var port: Int
    /// TLS to use, or nil for a plain TCP connection.
    public var useTLS: Bool

    public init(aeTitle: String, host: String, port: Int, useTLS: Bool = false) {
        self.aeTitle = aeTitle
        self.host = host
        self.port = port
        self.useTLS = useTLS
    }
}
