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
        limits: DICOMNetworkLimits, timeouts: DICOMNetworkTimeouts, trace: DICOMPDUTrace? = nil
    ) throws -> Async {
        let pipeline = channel.pipeline.syncOperations
        let connectionTrace = trace.map { DICOMConnectionTrace($0, channel: channel) }
        try pipeline.addHandler(QuickAcknowledgment())
        if let tls {
            if isServer {
                try pipeline.addHandler(NIOSSLServerHandler(context: tls))
            } else {
                try pipeline.addHandler(try NIOSSLClientHandler(context: tls, serverHostname: serverHostname))
            }
            if let connectionTrace { try pipeline.addHandler(DICOMTLSSessionRecorder(connectionTrace)) }
        }
        if let idle = timeouts.idle {
            try pipeline.addHandler(IdleStateHandler(readTimeout: idle))
            try pipeline.addHandler(IdleTimeoutHandler(timeout: idle))
        }
        var decoder = DICOMPDUFrameDecoder(
            maximumDataLength: limits.maximumPDULength == 0 ? Int(UInt32.max) : Int(limits.maximumPDULength),
            maximumAssociateLength: limits.maximumAssociatePDULength)
        decoder.trace = connectionTrace
        var encoder = DICOMPDUFrameEncoder()
        encoder.trace = connectionTrace
        try pipeline.addHandler(ByteToMessageHandler(decoder))
        try pipeline.addHandler(MessageToByteHandler(encoder))
        return try Async(
            wrappingChannelSynchronously: channel,
            configuration: Async.Configuration(backPressureStrategy: .init(lowWatermark: 2, highWatermark: 8)))
    }
}

extension DICOMChannel {
    /// The certificate the peer presented, once the TLS handshake is done.
    static func peerCertificate(of channel: Channel) async -> NIOSSLCertificate? {
        try? await channel.pipeline.handler(type: NIOSSLHandler.self).map { $0.peerCertificate }.get()
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

/// Acknowledges received segments at once (Linux `TCP_QUICKACK`, reset by the kernel after each
/// read, so set again on every read). A peer that leaves Nagle's algorithm on holds the small end
/// of each message until the previous segment is acknowledged; with the kernel's delayed
/// acknowledgment, every C-STORE then waited about 40 ms before its last bytes arrived. Elsewhere
/// it does nothing.
final class QuickAcknowledgment: ChannelInboundHandler {
    typealias InboundIn = NIOAny
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        #if os(Linux)
        // TCP_QUICKACK = 12 (linux/tcp.h).
        try? context.channel.syncOptions?.setOption(ChannelOptions.tcpOption(.init(rawValue: 12)), value: 1)
        #endif
        context.fireChannelRead(data)
    }
}
