import NIOCore
import NIOSSL

/// The channel pipeline of a DICOM connection: optional TLS, an idle
/// timeout, then PDU framing bounded by the limits, wrapped in a
/// back-pressured `NIOAsyncChannel`.
enum DICOMChannel {
    typealias Async = NIOAsyncChannel<DICOMPDU, DICOMPDU>

    /// Configures `channel`; must run on its event loop.
    static func configure(
        _ channel: Channel, tls: NIOSSLContext?, serverHostname: String?, isServer: Bool,
        limits: DICOMNetworkLimits, timeouts: DICOMNetworkTimeouts
    ) throws -> Async {
        let pipeline = channel.pipeline.syncOperations
        if let tls {
            if isServer {
                try pipeline.addHandler(NIOSSLServerHandler(context: tls))
            } else {
                try pipeline.addHandler(try NIOSSLClientHandler(context: tls, serverHostname: serverHostname))
            }
        }
        if let idle = timeouts.idle {
            try pipeline.addHandler(IdleStateHandler(readTimeout: idle))
            try pipeline.addHandler(IdleTimeoutHandler(timeout: idle))
        }
        try pipeline.addHandler(ByteToMessageHandler(DICOMPDUFrameDecoder(
            maximumDataLength: limits.maximumPDULength == 0 ? Int(UInt32.max) : Int(limits.maximumPDULength),
            maximumAssociateLength: limits.maximumAssociatePDULength)))
        try pipeline.addHandler(MessageToByteHandler(DICOMPDUFrameEncoder()))
        return try Async(
            wrappingChannelSynchronously: channel,
            configuration: Async.Configuration(backPressureStrategy: .init(lowWatermark: 2, highWatermark: 8)))
    }
}

/// Turns a read-idle event into an error, which ends the inbound stream.
private final class IdleTimeoutHandler: ChannelInboundHandler {
    typealias InboundIn = NIOAny

    private let timeout: TimeAmount

    init(timeout: TimeAmount) {
        self.timeout = timeout
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let idle = event as? IdleStateHandler.IdleStateEvent, idle == .read {
            context.fireErrorCaught(DICOMNetworkError.timeout(
                "no data received for \(timeout.nanoseconds / 1_000_000_000) s"))
            context.close(promise: nil)
            return
        }
        context.fireUserInboundEventTriggered(event)
    }
}
