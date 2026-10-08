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
    /// The TLS handshake or record layer failed: certificate, host name,
    /// protocol version, cipher suite, or integrity check (PS3.15 B.12).
    case tls(String)

    public var description: String {
        switch self {
        case .associationRejected(let reject): return "association rejected: \(reject.result), \(reject.reason)"
        case .associationAborted(let abort): return "association aborted by the \(abort.source): \(abort.reason)"
        case .protocolViolation(let message): return "protocol violation: \(message)"
        case .timeout(let message): return "timeout: \(message)"
        case .connectionClosed: return "connection closed"
        case .noPresentationContext(let uid): return "no accepted presentation context for \(uid)"
        case .invalidState(let message): return "invalid association state: \(message)"
        case .tls(let message): return "TLS: \(message)"
        }
    }

    /// The network error for a transport failure.
    static func from(_ error: Error) -> DICOMNetworkError {
        if let error = error as? DICOMNetworkError { return error }
        if let error = error as? DICOMPDUError {
            return error == .tlsRecord ? .tls(error.message) : .protocolViolation(error.message)
        }
        if let error = error as? NIOSSLError { return .tls("\(error)") }
        if let error = error as? NIOSSLExtraError { return .tls("\(error)") }
        if let error = error as? BoringSSLError { return .tls("\(error)") }
        return .connectionClosed
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

/// TLS for DICOM connections, following the BCP 195 RFC 8996, 9325 TLS
/// Secure Transport Connection Profile (PS3.15 B.12) and the algorithm
/// restrictions of its Modified variant (B.13): TLS 1.2 or 1.3, 1.3
/// preferred; for TLS 1.2 only ECDHE key exchange with AEAD ciphers (AES-GCM,
/// ChaCha20-Poly1305); certificate and host name verification unless
/// explicitly relaxed. The registered port for DICOM over TLS is 2762.
public struct DICOMTLSConfiguration: Sendable {
    /// The NIOSSL configuration, which callers may adjust.
    public var configuration: TLSConfiguration

    /// A configuration used as given: `client` and `server` apply the
    /// profile, this initializer does not.
    public init(configuration: TLSConfiguration) {
        self.configuration = configuration
    }

    /// The TLS 1.2 cipher suites permitted by PS3.15 B.13 that BoringSSL
    /// implements, strongest first. TLS 1.3 always offers its AEAD suites.
    public static let cipherSuites: [NIOTLSCipher] = [
        .TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384, .TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
        .TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256, .TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256,
        .TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256, .TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
    ]

    /// Applies the profile: TLS 1.2 minimum, 1.3 maximum, and the cipher
    /// suites above.
    public static func applyProfile(to configuration: inout TLSConfiguration) {
        configuration.minimumTLSVersion = .tlsv12
        configuration.maximumTLSVersion = .tlsv13
        configuration.cipherSuiteValues = cipherSuites
    }

    /// A client: verifies the server against `trustRoots` (the system's by
    /// default) and its host name; presents a certificate when given one.
    public static func client(
        trustRoots: NIOSSLTrustRoots = .default,
        certificateChain: [NIOSSLCertificate] = [], privateKey: NIOSSLPrivateKey? = nil,
        verification: CertificateVerification = .fullVerification
    ) -> DICOMTLSConfiguration {
        var configuration = TLSConfiguration.makeClientConfiguration()
        applyProfile(to: &configuration)
        configuration.trustRoots = trustRoots
        configuration.certificateVerification = verification
        configuration.certificateChain = certificateChain.map { .certificate($0) }
        configuration.privateKey = privateKey.map { .privateKey($0) }
        return DICOMTLSConfiguration(configuration: configuration)
    }

    /// A server presenting `certificateChain`; with `clientTrustRoots`, it
    /// requires and verifies client certificates (mutual authentication,
    /// which B.12 requires servers to support).
    public static func server(
        certificateChain: [NIOSSLCertificate], privateKey: NIOSSLPrivateKey,
        clientTrustRoots: NIOSSLTrustRoots? = nil
    ) -> DICOMTLSConfiguration {
        var configuration = TLSConfiguration.makeServerConfiguration(
            certificateChain: certificateChain.map { .certificate($0) }, privateKey: .privateKey(privateKey))
        applyProfile(to: &configuration)
        if let clientTrustRoots {
            configuration.trustRoots = clientTrustRoots
            configuration.certificateVerification = .noHostnameVerification
        }
        return DICOMTLSConfiguration(configuration: configuration)
    }

    /// A client from PEM files: `trustRootsFile` replaces the system's
    /// roots; a certificate chain and its key make it present a client
    /// certificate.
    public static func client(
        pemTrustRootsFile: String?, pemCertificateChainFile: String? = nil, pemPrivateKeyFile: String? = nil,
        verification: CertificateVerification = .fullVerification
    ) throws -> DICOMTLSConfiguration {
        let (chain, key) = try identity(pemCertificateChainFile, pemPrivateKeyFile, required: false)
        return client(
            trustRoots: try pemTrustRootsFile.map { .certificates(try NIOSSLCertificate.fromPEMFile($0)) } ?? .default,
            certificateChain: chain, privateKey: key, verification: verification)
    }

    /// A server from PEM files; `clientTrustRootsFile` requires client
    /// certificates issued by those roots.
    public static func server(
        pemCertificateChainFile: String, pemPrivateKeyFile: String, pemClientTrustRootsFile: String? = nil
    ) throws -> DICOMTLSConfiguration {
        let (chain, key) = try identity(pemCertificateChainFile, pemPrivateKeyFile, required: true)
        return server(
            certificateChain: chain, privateKey: key!,
            clientTrustRoots: try pemClientTrustRootsFile.map { .certificates(try NIOSSLCertificate.fromPEMFile($0)) })
    }

    private static func identity(
        _ chainFile: String?, _ keyFile: String?, required: Bool
    ) throws -> ([NIOSSLCertificate], NIOSSLPrivateKey?) {
        guard let chainFile, let keyFile else {
            if required || chainFile != nil || keyFile != nil {
                throw DICOMNetworkError.invalidState("a TLS certificate chain needs its private key, and conversely")
            }
            return ([], nil)
        }
        let chain = try NIOSSLCertificate.fromPEMFile(chainFile)
        guard !chain.isEmpty else { throw DICOMNetworkError.invalidState("no certificate in \(chainFile)") }
        return (chain, try NIOSSLPrivateKey(file: keyFile, format: .pem))
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
