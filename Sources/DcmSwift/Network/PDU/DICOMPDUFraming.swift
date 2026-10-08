import NIOCore

/// Splits the inbound byte stream into PDUs (PS3.8 9.3.1). A PDU longer than
/// allowed is refused from its header, before its body is buffered.
public struct DICOMPDUFrameDecoder: NIOSingleStepByteToMessageDecoder {
    public typealias InboundOut = DICOMPDU

    /// The largest P-DATA-TF variable field accepted: the Maximum Length
    /// Received this side announced (PS3.8 D.1), or the limit for an
    /// unlimited announcement.
    public var maximumDataLength: Int
    /// The largest A-ASSOCIATE-RQ or A-ASSOCIATE-AC variable field accepted.
    public var maximumAssociateLength: Int

    public init(maximumDataLength: Int, maximumAssociateLength: Int = 1 << 20) {
        self.maximumDataLength = maximumDataLength
        self.maximumAssociateLength = maximumAssociateLength
    }

    public mutating func decode(buffer: inout ByteBuffer) throws -> DICOMPDU? {
        guard let type = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self),
              let length = buffer.getInteger(at: buffer.readerIndex + 2, as: UInt32.self) else {
            return nil
        }
        let limit: Int
        switch type {
        case 0x01, 0x02: limit = maximumAssociateLength
        case 0x04: limit = maximumDataLength
        case 0x03, 0x05, 0x06, 0x07: limit = 4
        case 0x14...0x17 where buffer.getInteger(at: buffer.readerIndex + 1, as: UInt8.self) == 0x03:
            // A TLS record (content type, then version 3.x) where a PDU,
            // whose second byte is reserved as 0, was expected.
            throw DICOMPDUError.tlsRecord
        default: throw DICOMPDUError(.unrecognizedPDU, "PDU type 0x\(String(type, radix: 16))")
        }
        guard UInt64(length) <= UInt64(limit) else {
            throw DICOMPDUError(.invalidPDUParameterValue, "PDU type 0x\(String(type, radix: 16)) of \(length) bytes exceeds \(limit)")
        }
        guard buffer.readableBytes >= DICOMPDUCodec.headerLength + Int(length) else { return nil }
        buffer.moveReaderIndex(forwardBy: DICOMPDUCodec.headerLength)
        let body = buffer.readSlice(length: Int(length))!
        return try DICOMPDUCodec.decode(type: type, body: body)
    }

    public mutating func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws -> DICOMPDU? {
        // A PDU cut by the end of the connection is dropped.
        try decode(buffer: &buffer)
    }
}

/// Serializes outbound PDUs.
public struct DICOMPDUFrameEncoder: MessageToByteEncoder {
    public typealias OutboundIn = DICOMPDU

    public init() {}

    public func encode(data: DICOMPDU, out: inout ByteBuffer) throws {
        try DICOMPDUCodec.encode(data, into: &out)
    }
}
