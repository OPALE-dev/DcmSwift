import Foundation
import NIOCore
import NIOSSL
import NIOTLS

/// A PDU as it crossed the connection: its bytes, header included, and its
/// decoded form (PS3.8 9.3). A debugging console shows what passed on the
/// wire from these records; DIMSE commands and data sets are the PDVs of
/// the P-DATA-TF PDUs.
public struct DICOMPDUTraceRecord: Sendable {
    public enum Direction: Sendable, Equatable {
        case sent, received
    }

    public let direction: Direction
    /// When the PDU was framed: decoded on receipt, encoded on sending.
    public let time: Date
    /// The connection, the same for every PDU of an association.
    public let connection: UUID
    public let localAddress: String?
    public let remoteAddress: String?
    /// The PDU as on the wire: type, reserved byte, length, then the body.
    public let bytes: [UInt8]
    public let pdu: DICOMPDU
    /// The TLS session of the connection, once its handshake is done: nil
    /// on a plain TCP connection, and for a client's first PDU, framed
    /// before the handshake ends.
    public let tls: DICOMTLSSession?

    public init(direction: Direction, time: Date = Date(), connection: UUID, localAddress: String?,
                remoteAddress: String?, bytes: [UInt8], pdu: DICOMPDU, tls: DICOMTLSSession? = nil) {
        self.direction = direction
        self.time = time
        self.connection = connection
        self.localAddress = localAddress
        self.remoteAddress = remoteAddress
        self.bytes = bytes
        self.pdu = pdu
        self.tls = tls
    }

    /// The PDU type (PS3.8 Table 9-11): 01H A-ASSOCIATE-RQ to 07H A-ABORT.
    public var type: UInt8 { bytes.first ?? 0 }
}

/// The TLS session of a connection (PS3.15 B.12): the protocol version
/// negotiated and the certificate the peer presented.
public struct DICOMTLSSession: Sendable, Equatable {
    public enum Version: String, Sendable {
        case tls10 = "TLS 1.0", tls11 = "TLS 1.1", tls12 = "TLS 1.2", tls13 = "TLS 1.3"
    }

    public let version: Version
    /// The peer's certificate, DER encoded; nil when it presented none.
    public let peerCertificate: [UInt8]?

    public init(version: Version, peerCertificate: [UInt8]?) {
        self.version = version
        self.peerCertificate = peerCertificate
    }
}

/// Receives each PDU sent or received, on the connection's event loop:
/// it must return quickly. Without one, no PDU is copied.
public typealias DICOMPDUTrace = @Sendable (DICOMPDUTraceRecord) -> Void

/// The trace of one connection, given to its framing. Used on the
/// connection's event loop only; the addresses are read at the first PDU,
/// once a client's connection is established.
final class DICOMConnectionTrace: @unchecked Sendable {
    let trace: DICOMPDUTrace
    let connection = UUID()
    private weak var channel: Channel?
    private var addresses: (local: String?, remote: String?)?
    /// Set once the handshake is done.
    var tls: DICOMTLSSession?

    init(_ trace: @escaping DICOMPDUTrace, channel: Channel) {
        self.trace = trace
        self.channel = channel
    }

    func record(_ direction: DICOMPDUTraceRecord.Direction, _ bytes: [UInt8], _ pdu: DICOMPDU) {
        if addresses == nil || addresses?.remote == nil {
            addresses = (channel?.localAddress?.description, channel?.remoteAddress?.description)
        }
        trace(DICOMPDUTraceRecord(direction: direction, connection: connection, localAddress: addresses?.local,
                                  remoteAddress: addresses?.remote, bytes: bytes, pdu: pdu, tls: tls))
    }
}


/// Gives the trace the TLS session of its connection once the handshake is
/// done: before, the version BoringSSL reports is not the one negotiated.
final class DICOMTLSSessionRecorder: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = NIOAny

    private let trace: DICOMConnectionTrace

    init(_ trace: DICOMConnectionTrace) {
        self.trace = trace
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if case .handshakeCompleted = event as? TLSUserEvent,
           let handler = try? context.pipeline.syncOperations.handler(type: NIOSSLHandler.self),
           let version = handler.tlsVersion {
            let versions: [TLSVersion: DICOMTLSSession.Version] = [.tlsv1: .tls10, .tlsv11: .tls11, .tlsv12: .tls12, .tlsv13: .tls13]
            trace.tls = versions[version].map {
                DICOMTLSSession(version: $0, peerCertificate: try? handler.peerCertificate?.toDERBytes())
            }
        }
        context.fireUserInboundEventTriggered(event)
    }
}
