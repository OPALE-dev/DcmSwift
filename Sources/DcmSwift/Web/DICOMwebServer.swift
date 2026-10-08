import Foundation
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL

/// The network configuration of a `DICOMwebServer`.
public struct DICOMwebServerNetworkConfiguration: Sendable {
    public var host: String
    /// The port to listen on; 0 picks a free one.
    public var port: Int
    /// TLS, from `DICOMTLSConfiguration.server(...)`; nil serves plain HTTP.
    public var tls: DICOMTLSConfiguration?
    /// Seconds a connection may stay idle before it is closed.
    public var idleTimeout: Int64
    /// The scheme and authority user agents use to reach the service, such
    /// as `https://pacs.example.org` behind a reverse proxy; nil derives it
    /// from each request's Host header field.
    public var publicOrigin: String?
    public var logger: Logging.Logger

    public init(host: String = "0.0.0.0", port: Int = 8080, tls: DICOMTLSConfiguration? = nil, idleTimeout: Int64 = 120,
                publicOrigin: String? = nil, logger: Logging.Logger = Logging.Logger(label: "dcmswift.dicomweb")) {
        self.host = host
        self.port = port
        self.tls = tls
        self.idleTimeout = idleTimeout
        self.publicOrigin = publicOrigin.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
        self.logger = logger
    }
}

/// Serves a `DICOMwebOriginServer` over HTTP/1.1, or HTTPS.
public final class DICOMwebServer: Sendable {
    public let origin: DICOMwebOriginServer
    public let network: DICOMwebServerNetworkConfiguration
    private let group: EventLoopGroup
    private let sslContext: NIOSSLContext?

    public init(origin: DICOMwebOriginServer, network: DICOMwebServerNetworkConfiguration = .init(),
                eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup.singleton) throws {
        self.origin = origin
        self.network = network
        group = eventLoopGroup
        sslContext = try network.tls.map { try NIOSSLContext(configuration: $0.configuration) }
    }

    private typealias Connection = NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>

    /// Binds and serves until the task is cancelled. `onBound` receives the
    /// bound port once connections are accepted.
    public func run(onBound: (@Sendable (Int) -> Void)? = nil) async throws {
        let sslContext = self.sslContext
        let idle = TimeAmount.seconds(network.idleTimeout)
        let server = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
            .bind(host: network.host, port: network.port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    if let sslContext {
                        try channel.pipeline.syncOperations.addHandler(NIOSSLServerHandler(context: sslContext))
                    }
                    try channel.pipeline.syncOperations.addHandler(IdleStateHandler(allTimeout: idle))
                    try channel.pipeline.syncOperations.configureHTTPServerPipeline()
                    try channel.pipeline.syncOperations.addHandler(IdleCloseHandler())
                    return try Connection(wrappingChannelSynchronously: channel)
                }
            }
        let port = server.channel.localAddress?.port ?? network.port
        network.logger.info("DICOMweb listening on \(network.host):\(port)\(sslContext != nil ? " (TLS)" : "")")
        onBound?(port)
        try await server.executeThenClose { connections in
            try await withThrowingTaskGroup(of: Void.self) { group in
                var running = 0
                for try await connection in connections {
                    // Finished connections are collected as new ones arrive.
                    while running >= 256 {
                        _ = try await group.next()
                        running -= 1
                    }
                    running += 1
                    group.addTask { await self.serve(connection) }
                }
            }
        }
    }

    /// Serves the requests of one connection in order; never throws.
    private func serve(_ connection: Connection) async {
        let channel = connection.channel
        let peer = channel.remoteAddress?.description
        let scheme = sslContext == nil ? "http" : "https"
        do {
            try await connection.executeThenClose { inbound, outbound in
                let reader = RequestReader(inbound.makeAsyncIterator())
                while let head = try await reader.nextHead() {
                    let host = head.headers.first(name: "Host")
                        ?? "\(network.host == "0.0.0.0" ? "localhost" : network.host):\(channel.localAddress?.port ?? network.port)"
                    var headers = DICOMwebMultipart.Headers()
                    for (name, value) in head.headers { headers[name] = value }
                    let parts = head.uri.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
                    let request = DICOMwebHTTPRequest(
                        method: head.method.rawValue, path: String(parts[0]), query: parts.count > 1 ? String(parts[1]) : "",
                        headers: headers, body: reader.body())
                    let certificate = try? await peerCertificate(channel)
                    let response = await origin.respond(
                        to: request, origin: network.publicOrigin ?? "\(scheme)://\(host)", remoteAddress: peer,
                        peerCertificate: certificate)
                    // Unread payload bytes are discarded before the response.
                    try await reader.drainBody()
                    try await write(response, method: head.method, keepAlive: head.isKeepAlive, version: head.version,
                                    to: outbound)
                    network.logger.debug("\(head.method) \(head.uri) \(response.status)")
                    if !head.isKeepAlive { break }
                }
            }
        } catch {
            network.logger.debug("connection from \(peer ?? "unknown") ended: \(error)")
        }
    }

    private func peerCertificate(_ channel: Channel) async throws -> NIOSSLCertificate? {
        guard sslContext != nil else { return nil }
        return try await channel.pipeline.handler(type: NIOSSLServerHandler.self).flatMap { handler in
            handler.peerCertificate.map { channel.eventLoop.makeSucceededFuture($0) }
                ?? channel.eventLoop.makeSucceededFuture(nil)
        }.get()
    }

    private func write(
        _ response: DICOMwebHTTPResponse, method: HTTPMethod, keepAlive: Bool, version: HTTPVersion,
        to outbound: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>
    ) async throws {
        var headers = HTTPHeaders()
        for field in response.headers { headers.add(name: field.name, value: field.value) }
        headers.replaceOrAdd(name: "Connection", value: keepAlive ? "keep-alive" : "close")
        let head = { (length: Int?) -> HTTPResponseHead in
            var headers = headers
            if let length { headers.replaceOrAdd(name: "Content-Length", value: String(length)) }
            return HTTPResponseHead(version: version, status: HTTPResponseStatus(statusCode: response.status),
                                    headers: headers)
        }
        switch response.body {
        case .empty:
            try await outbound.write(.head(head(0)))
        case .data(let data):
            try await outbound.write(.head(head(data.count)))
            if method != .HEAD && !data.isEmpty { try await outbound.write(.body(.byteBuffer(ByteBuffer(bytes: data)))) }
        case .stream(let stream, let length):
            // Without a known length, HTTP/1.1 chunked transfer coding applies.
            try await outbound.write(.head(head(length)))
            if method != .HEAD {
                for try await chunk in stream { try await outbound.write(.body(.byteBuffer(ByteBuffer(bytes: chunk)))) }
            }
        }
        try await outbound.write(.end(nil))
    }
}

/// Reads requests from a connection: their heads, and their payloads on
/// demand, so that a slow service slows the upload instead of buffering it.
private final class RequestReader: @unchecked Sendable {
    private var iterator: NIOAsyncChannelInboundStream<HTTPServerRequestPart>.AsyncIterator
    private let lock = NIOLock()
    private var bodyEnded = true

    init(_ iterator: NIOAsyncChannelInboundStream<HTTPServerRequestPart>.AsyncIterator) {
        self.iterator = iterator
    }

    /// The head of the next request, or nil when the connection ends.
    func nextHead() async throws -> HTTPRequestHead? {
        while let part = try await iterator.next() {
            if case .head(let head) = part {
                lock.withLock { bodyEnded = false }
                return head
            }
        }
        return nil
    }

    /// The payload of the current request, read as it is consumed.
    func body() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { [self] in try await nextBodyChunk() }
    }

    private func nextBodyChunk() async throws -> Data? {
        while !lock.withLock({ bodyEnded }) {
            guard let part = try await iterator.next() else {
                lock.withLock { bodyEnded = true }
                throw DICOMwebHTTPError(400, "the connection closed during the request")
            }
            switch part {
            case .body(let buffer):
                if buffer.readableBytes > 0 { return Data(buffer.readableBytesView) }
            case .end:
                lock.withLock { bodyEnded = true }
                return nil
            case .head:
                lock.withLock { bodyEnded = true }
                throw DICOMwebHTTPError(400, "unexpected request head")
            }
        }
        return nil
    }

    /// Discards what remains of the current payload.
    func drainBody() async throws {
        while try await nextBodyChunk() != nil {}
    }
}

/// Closes a connection that stays idle.
private final class IdleCloseHandler: ChannelInboundHandler, Sendable {
    typealias InboundIn = HTTPServerRequestPart

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is IdleStateHandler.IdleStateEvent {
            context.close(promise: nil)
        } else {
            context.fireUserInboundEventTriggered(event)
        }
    }
}
