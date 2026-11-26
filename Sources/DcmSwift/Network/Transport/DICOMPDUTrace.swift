import Foundation
import NIOCore

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

    public init(direction: Direction, time: Date = Date(), connection: UUID, localAddress: String?,
                remoteAddress: String?, bytes: [UInt8], pdu: DICOMPDU) {
        self.direction = direction
        self.time = time
        self.connection = connection
        self.localAddress = localAddress
        self.remoteAddress = remoteAddress
        self.bytes = bytes
        self.pdu = pdu
    }

    /// The PDU type (PS3.8 Table 9-11): 01H A-ASSOCIATE-RQ to 07H A-ABORT.
    public var type: UInt8 { bytes.first ?? 0 }
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

    init(_ trace: @escaping DICOMPDUTrace, channel: Channel) {
        self.trace = trace
        self.channel = channel
    }

    func record(_ direction: DICOMPDUTraceRecord.Direction, _ bytes: [UInt8], _ pdu: DICOMPDU) {
        if addresses == nil || addresses?.remote == nil {
            addresses = (channel?.localAddress?.description, channel?.remoteAddress?.description)
        }
        trace(DICOMPDUTraceRecord(direction: direction, connection: connection, localAddress: addresses?.local,
                                  remoteAddress: addresses?.remote, bytes: bytes, pdu: pdu))
    }
}
