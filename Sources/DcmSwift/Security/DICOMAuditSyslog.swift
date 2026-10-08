import Foundation
import NIOCore
import NIOPosix
import NIOSSL

/// Receives the audit messages of an application, such as the archive
/// services of `DcmServer`.
public protocol DICOMAuditRecorder: Sendable {
    func record(_ message: DICOMAuditMessage) async
}

/// The syslog message that carries an audit message (RFC 5424), as the
/// Audit Trail Message Transmission Profiles require (PS3.15 A.6, A.7):
/// facility 10 (security/authorization), severity 5 (notice) unless told
/// otherwise, so PRI <85>; MSGID DICOM+RFC3881; no structured data; the XML
/// as MSG, in UTF-8 with its byte order mark.
public struct DICOMSyslogMessage: Sendable {
    public var severity: Int
    public var hostname: String
    public var appName: String
    public var processID: String
    public var timestamp: Date
    public var message: Data

    public static let facility = 10
    public static let messageID = "DICOM+RFC3881"

    public init(audit: DICOMAuditMessage, severity: Int = 5, hostname: String = ProcessInfo.processInfo.hostName,
                appName: String = ProcessInfo.processInfo.processName,
                processID: String = String(ProcessInfo.processInfo.processIdentifier), timestamp: Date = Date()) {
        self.severity = severity
        self.hostname = hostname
        self.appName = appName
        self.processID = processID
        self.timestamp = timestamp
        message = audit.xml()
    }

    /// SYSLOG-MSG of RFC 5424.
    public func encoded() -> Data {
        // Header fields are printable US-ASCII without spaces, of bounded
        // length; "-" stands for an unknown value.
        func field(_ value: String, _ limit: Int) -> String {
            let printable = String(value.unicodeScalars.filter { (33...126).contains($0.value) }.map(Character.init).prefix(limit))
            return printable.isEmpty ? "-" : printable
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let header = "<\(Self.facility * 8 + severity)>1 \(formatter.string(from: timestamp)) "
            + "\(field(hostname, 255)) \(field(appName, 48)) \(field(processID, 128)) \(Self.messageID) - "
        return Data(header.utf8) + Data([0xEF, 0xBB, 0xBF]) + message
    }
}

/// Sends audit messages to a syslog collector over TLS (RFC 5425, PS3.15
/// A.6) or UDP (RFC 5426, PS3.15 A.7).
public actor DICOMAuditSyslogSender: DICOMAuditRecorder {
    public enum Transport: Sendable {
        /// SYSLOG-TLS; the registered port is 6514.
        case tls(DICOMTLSConfiguration)
        /// SYSLOG-UDP; the default port is 514. Messages longer than a
        /// datagram are truncated by the network.
        case udp
    }

    public let host: String
    public let port: Int
    public let transport: Transport
    public let hostname: String
    public let appName: String
    private let group: EventLoopGroup
    private var channel: Channel?
    private var sslContext: NIOSSLContext?

    public init(host: String, port: Int? = nil, transport: Transport,
                hostname: String = ProcessInfo.processInfo.hostName,
                appName: String = ProcessInfo.processInfo.processName,
                group: EventLoopGroup = MultiThreadedEventLoopGroup.singleton) {
        self.host = host
        if case .tls = transport { self.port = port ?? 6514 } else { self.port = port ?? 514 }
        self.transport = transport
        self.hostname = hostname
        self.appName = appName
        self.group = group
    }

    /// Sends a message, logging the error when it cannot be sent.
    public func record(_ message: DICOMAuditMessage) async {
        do {
            try await send(message)
        } catch {
            Logger.error("Cannot send the audit message to \(host):\(port): \(error)")
        }
    }

    public func send(_ message: DICOMAuditMessage, severity: Int = 5) async throws {
        let syslog = DICOMSyslogMessage(audit: message, severity: severity, hostname: hostname, appName: appName)
        try await send(syslog.encoded())
    }

    /// Sends an encoded SYSLOG-MSG: over TLS framed with its octet count
    /// (RFC 5425 4.3), over UDP as one datagram.
    public func send(_ encoded: Data) async throws {
        switch transport {
        case .tls(let tls):
            var frame = ByteBufferAllocator().buffer(capacity: encoded.count + 8)
            frame.writeString("\(encoded.count) ")
            frame.writeBytes(encoded)
            do {
                try await connection(tls).writeAndFlush(frame)
            } catch {
                // The collector may have closed the connection: retry once.
                channel = nil
                try await connection(tls).writeAndFlush(frame)
            }
        case .udp:
            let address = try SocketAddress.makeAddressResolvingHost(host, port: port)
            let channel = try await DatagramBootstrap(group: group)
                .bind(host: address.protocol == .inet6 ? "::" : "0.0.0.0", port: 0).get()
            defer { channel.close(promise: nil) }
            var buffer = channel.allocator.buffer(capacity: encoded.count)
            buffer.writeBytes(encoded)
            try await channel.writeAndFlush(AddressedEnvelope(remoteAddress: address, data: buffer))
        }
    }

    /// Closes the TLS connection.
    public func close() async {
        try? await channel?.close()
        channel = nil
    }

    private func connection(_ tls: DICOMTLSConfiguration) async throws -> Channel {
        if let channel, channel.isActive { return channel }
        let context = try sslContext ?? NIOSSLContext(configuration: tls.configuration)
        sslContext = context
        let host = self.host
        let channel = try await ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let serverName = host.first?.isNumber == true || host.contains(":") ? nil : host
                    try channel.pipeline.syncOperations.addHandler(
                        try NIOSSLClientHandler(context: context, serverHostname: serverName))
                }
            }
            .connect(host: host, port: port).get()
        self.channel = channel
        return channel
    }
}

/// Several recorders at once.
public struct DICOMAuditRecorders: DICOMAuditRecorder {
    public let recorders: [DICOMAuditRecorder]

    public init(_ recorders: [DICOMAuditRecorder]) {
        self.recorders = recorders
    }

    public func record(_ message: DICOMAuditMessage) async {
        for recorder in recorders { await recorder.record(message) }
    }
}
