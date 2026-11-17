import ArgumentParser
import DcmSwift
import Foundation
import Logging
import NIOCore
import NIOSSL

/// Options shared by the network tools (DcmEcho, DcmStore, DcmFind,
/// DcmServer): logging, limits, and timers.
public struct NetworkOptions: ParsableArguments {
    @Flag(name: .shortAndLong, help: "Log association and DIMSE details.")
    public var verbose = false

    @Option(name: .long, help: "Seconds allowed to connect, and for ARTIM (PS3.8 9.1.5).")
    public var timeout: Int = 30

    @Option(name: .long, help: "Seconds without data before aborting; 0 disables the timer.")
    public var idleTimeout: Int = 120

    @Option(name: .long, help: "Maximum PDU length announced (Maximum Length Received), in bytes.")
    public var maxPDU: UInt32 = 1 << 16

    public init() {}

    public var timeouts: DICOMNetworkTimeouts {
        DICOMNetworkTimeouts(
            connect: .seconds(Int64(timeout)), artim: .seconds(Int64(timeout)),
            idle: idleTimeout > 0 ? .seconds(Int64(idleTimeout)) : nil)
    }

    public var limits: DICOMNetworkLimits {
        DICOMNetworkLimits(maximumPDULength: maxPDU)
    }

    /// A logger writing to standard error, at debug level with `--verbose`.
    public func logger(label: String) -> Logging.Logger {
        var logger = Logging.Logger(label: label) { StreamLogHandler.standardError(label: $0) }
        logger.logLevel = verbose ? .debug : .warning
        return logger
    }

    public func validate() throws {
        guard timeout > 0 else { throw ValidationError("--timeout must be positive") }
        guard idleTimeout >= 0 else { throw ValidationError("--idle-timeout cannot be negative") }
        guard maxPDU == 0 || maxPDU >= 4096 else { throw ValidationError("--max-pdu must be 0 or at least 4096") }
    }
}

/// TLS options of a requestor (PS3.15 B.12 with the B.13 restrictions).
public struct ClientTLSOptions: ParsableArguments {
    @Flag(name: .long, help: "Connect with TLS.")
    public var tls = false

    @Option(name: .long, help: "PEM file of the CA certificates trusted for the server (default: the system's).")
    public var tlsCA: String?

    @Option(name: .long, help: "PEM certificate chain presented to the server.")
    public var tlsCertificate: String?

    @Option(name: .long, help: "PEM private key of --tls-certificate.")
    public var tlsKey: String?

    @Flag(name: .long, help: "Verify the server certificate but not its host name.")
    public var tlsNoHostnameCheck = false

    public init() {}

    public func validate() throws {
        if !tls, tlsCA != nil || tlsCertificate != nil || tlsKey != nil || tlsNoHostnameCheck {
            throw ValidationError("TLS options need --tls")
        }
        if (tlsCertificate == nil) != (tlsKey == nil) {
            throw ValidationError("--tls-certificate and --tls-key go together")
        }
    }

    /// The configuration, or nil without `--tls`.
    public func configuration() throws -> DICOMTLSConfiguration? {
        guard tls else { return nil }
        return try DICOMTLSConfiguration.client(
            pemTrustRootsFile: tlsCA, pemCertificateChainFile: tlsCertificate, pemPrivateKeyFile: tlsKey,
            verification: tlsNoHostnameCheck ? .noHostnameVerification : .fullVerification)
    }
}

/// TLS options of an acceptor.
public struct ServerTLSOptions: ParsableArguments {
    @Option(name: .long, help: "PEM certificate chain: accept TLS connections only (port 2762 is registered for DICOM over TLS).")
    public var tlsCertificate: String?

    @Option(name: .long, help: "PEM private key of --tls-certificate.")
    public var tlsKey: String?

    @Option(name: .long, help: "PEM file of the CA certificates of accepted clients: require client certificates.")
    public var tlsClientCA: String?

    public init() {}

    public func validate() throws {
        if (tlsCertificate == nil) != (tlsKey == nil) {
            throw ValidationError("--tls-certificate and --tls-key go together")
        }
        if tlsClientCA != nil, tlsCertificate == nil {
            throw ValidationError("--tls-client-ca needs --tls-certificate")
        }
    }

    public func configuration() throws -> DICOMTLSConfiguration? {
        guard let tlsCertificate, let tlsKey else { return nil }
        return try DICOMTLSConfiguration.server(
            pemCertificateChainFile: tlsCertificate, pemPrivateKeyFile: tlsKey, pemClientTrustRootsFile: tlsClientCA)
    }
}

/// The called AE: title, host, and port, as positional arguments.
public struct RemoteOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "Local (calling) AE title.")
    public var callingAET = "DCMCLIENT"

    @Argument(help: "Remote (called) AE title.")
    public var calledAET: String

    @Argument(help: "Remote host name or IP address.")
    public var calledHostname: String

    @Argument(help: "Remote port.")
    public var calledPort: Int

    public init() {}

    public func validate() throws {
        guard DICOMApplicationEntityTitle.isValid(callingAET) else { throw ValidationError("invalid AE title \(callingAET)") }
        guard DICOMApplicationEntityTitle.isValid(calledAET) else { throw ValidationError("invalid AE title \(calledAET)") }
        guard (1...65535).contains(calledPort) else { throw ValidationError("invalid port \(calledPort)") }
    }

    public func node(tls: Bool) -> DICOMRemoteNode {
        DICOMRemoteNode(aeTitle: calledAET, host: calledHostname, port: calledPort, useTLS: tls)
    }

    public var description: String { "\(calledAET)@\(calledHostname):\(calledPort)" }
}

extension Error {
    /// A one-line message for the terminal.
    public var commandLineDescription: String {
        if let error = self as? DICOMNetworkError { return error.description }
        if let error = self as? DICOMServiceError { return error.description }
        if let error = self as? NIOSSLError { return "TLS: \(error)" }
        if let error = self as? BoringSSLError { return "TLS: \(error)" }
        return "\(self)"
    }
}

/// Writes a line to standard error.
public func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
