import Foundation
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOWebSocket
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
    /// Receives each request and response, payloads included, for a
    /// debugging console. UPS event notifications over WebSocket are not traced.
    public var httpTrace: DICOMwebHTTPTrace?

    public init(host: String = "0.0.0.0", port: Int = 8080, tls: DICOMTLSConfiguration? = nil, idleTimeout: Int64 = 120,
                publicOrigin: String? = nil, logger: Logging.Logger = Logging.Logger(label: "dcmswift.dicomweb"),
                httpTrace: DICOMwebHTTPTrace? = nil) {
        self.host = host
        self.port = port
        self.tls = tls
        self.idleTimeout = idleTimeout
        self.publicOrigin = publicOrigin.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
        self.logger = logger
        self.httpTrace = httpTrace
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
    private struct Negotiation: Sendable {
        let channel: Channel
        let result: EventLoopFuture<UpgradeResult>
    }
    private enum UpgradeResult: Sendable {
        case http(Connection)
        case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>, DICOMUPSEventHub.Connection)
    }

    private func notificationAE(_ head: HTTPRequestHead) -> String? {
        guard origin.worklist != nil, head.method == .GET, !head.uri.contains("?"),
              let path = origin.relativePath(head.uri), path.count == 2, path[0] == "subscribers",
              DICOMUPSRESTService.validAE(path[1]), head.headers.first(name: "Origin") != nil,
              head.headers.first(name: "Content-Length").map({ $0 == "0" }) ?? true,
              head.headers.first(name: "Transfer-Encoding") == nil else { return nil }
        return path[1]
    }

    /// Binds and serves until the task is cancelled. `onBound` receives the
    /// bound port once connections are accepted.
    public func run(onBound: (@Sendable (Int) -> Void)? = nil) async throws {
        let sslContext = self.sslContext
        let idle = TimeAmount.seconds(network.idleTimeout)
        let server: NIOAsyncChannel<Negotiation, Never> = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)
            .bind(host: network.host, port: network.port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    if let sslContext {
                        try channel.pipeline.syncOperations.addHandler(NIOSSLServerHandler(context: sslContext))
                    }
                    try channel.pipeline.syncOperations.addHandler(IdleStateHandler(allTimeout: idle))
                    if #available(macOS 13, iOS 16, *) {
                        let listenerBox = NIOLockedValueBox<DICOMUPSEventHub.Connection?>(nil)
                        channel.closeFuture.whenComplete { _ in
                            if let listener = listenerBox.withLockedValue({ $0 }), let hub = self.origin.worklist?.steps.eventHub {
                                Task { await hub.disconnect(listener.id) }
                            }
                        }
                        let upgrader = NIOTypedWebSocketServerUpgrader<UpgradeResult>(
                            maxFrameSize: 64 << 10,
                            shouldUpgrade: { channel, head in
                                var headers = HTTPHeaders()
                                if let source = head.headers.first(name: "Origin") { headers.add(name: "Origin", value: source) }
                                if let protocols = head.headers.first(name: "Sec-WebSocket-Protocol"),
                                   protocols.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).contains("dicom") {
                                    headers.add(name: "Sec-WebSocket-Protocol", value: "dicom")
                                }
                                guard let ae = self.notificationAE(head), let hub = self.origin.worklist?.steps.eventHub else {
                                    return channel.eventLoop.makeSucceededFuture(nil)
                                }
                                let responseHeaders = headers
                                return channel.eventLoop.makeFutureWithTask {
                                    let listener = await hub.connect(ae: ae)
                                    listenerBox.withLockedValue { $0 = listener }
                                    return responseHeaders
                                }
                            },
                            upgradePipelineHandler: { channel, head in
                                channel.eventLoop.makeCompletedFuture {
                                    guard let listener = listenerBox.withLockedValue({ $0 }) else {
                                        throw DICOMwebHTTPError(400, "notification connection was not registered")
                                    }
                                    return .websocket(try NIOAsyncChannel<WebSocketFrame, WebSocketFrame>(wrappingChannelSynchronously: channel), listener)
                                }
                            })
                        let upgrade = NIOTypedHTTPServerUpgradeConfiguration<UpgradeResult>(
                            upgraders: [upgrader], notUpgradingCompletionHandler: { channel in
                                channel.eventLoop.makeCompletedFuture {
                                    .http(try Connection(wrappingChannelSynchronously: channel))
                                }
                            })
                        try channel.pipeline.syncOperations.addHandler(IdleCloseHandler())
                        let result = try channel.pipeline.syncOperations.configureUpgradableHTTPServerPipeline(
                            configuration: .init(upgradeConfiguration: upgrade))
                        return Negotiation(channel: channel, result: result)
                    } else {
                        // Preserve the existing HTTP server on older deployment targets.
                        try channel.pipeline.syncOperations.configureHTTPServerPipeline()
                        try channel.pipeline.syncOperations.addHandler(IdleCloseHandler())
                        return Negotiation(channel: channel, result: channel.eventLoop.makeSucceededFuture(
                            .http(try Connection(wrappingChannelSynchronously: channel))))
                    }
                }
            }
        let port = server.channel.localAddress?.port ?? network.port
        network.logger.info("DICOMweb listening on \(network.host):\(port)\(sslContext != nil ? " (TLS)" : "")")
        onBound?(port)
        try await server.executeThenClose { connections in
            try await withThrowingTaskGroup(of: Void.self) { group in
                var running = 0
                for try await negotiated in connections {
                    while running >= 256 {
                        _ = try await group.next()
                        running -= 1
                    }
                    running += 1
                    group.addTask {
                        do {
                            try await withTaskCancellationHandler {
                                switch try await negotiated.result.get() {
                                case .http(let connection): await self.serve(connection)
                                case .websocket(let connection, let listener): await self.serveNotifications(connection, listener: listener)
                                }
                            } onCancel: {
                                negotiated.channel.close(promise: nil)
                            }
                        } catch {
                            self.network.logger.debug("HTTP/WebSocket negotiation ended: \(error)")
                        }
                    }
                }
            }
        }
    }

    private func serveNotifications(_ connection: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>,
                                    listener: DICOMUPSEventHub.Connection) async {
        guard let hub = origin.worklist?.steps.eventHub else { return }
        do {
            try await connection.executeThenClose { inbound, outbound in
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for try await event in listener.events {
                            try await outbound.write(WebSocketFrame(fin: true, opcode: .text, data: ByteBuffer(bytes: event)))
                        }
                    }
                    group.addTask {
                        for try await frame in inbound {
                            guard frame.maskKey != nil else {
                                var data = ByteBuffer(); data.writeInteger(UInt16(1002))
                                try await outbound.write(WebSocketFrame(fin: true, opcode: .connectionClose, data: data))
                                return
                            }
                            switch frame.opcode {
                            case .ping:
                                try await outbound.write(WebSocketFrame(fin: true, opcode: .pong, data: frame.unmaskedData))
                            case .pong: break
                            case .connectionClose:
                                try await outbound.write(WebSocketFrame(fin: true, opcode: .connectionClose, data: frame.unmaskedData))
                                return
                            default:
                                // Notification connections carry no client application messages.
                                var data = ByteBuffer(); data.writeInteger(UInt16(1003))
                                try await outbound.write(WebSocketFrame(fin: true, opcode: .connectionClose, data: data))
                                return
                            }
                        }
                    }
                    defer { group.cancelAll() }
                    _ = try await group.next()
                    await hub.disconnect(listener.id)
                }
            }
        } catch {
            network.logger.debug("UPS notification connection ended: \(error)")
        }
        await hub.disconnect(listener.id)
    }

    /// Serves the requests of one connection in order; never throws.
    private func serve(_ connection: Connection) async {
        let channel = connection.channel
        let peer = channel.remoteAddress?.description
        let scheme = sslContext == nil ? "http" : "https"
        let connectionID = UUID()
        do {
            try await connection.executeThenClose { inbound, outbound in
                let reader = RequestReader(inbound.makeAsyncIterator())
                while let head = try await reader.nextHead() {
                    let host = head.headers.first(name: "Host")
                        ?? "\(network.host == "0.0.0.0" ? "localhost" : network.host):\(channel.localAddress?.port ?? network.port)"
                    var headers = DICOMwebMultipart.Headers()
                    for (name, value) in head.headers { headers[name] = value }
                    let parts = head.uri.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
                    let answeredOrigin = network.publicOrigin ?? "\(scheme)://\(host)"
                    let trace = network.httpTrace.map {
                        DICOMwebExchangeTrace(trace: $0, connection: connectionID, origin: answeredOrigin, remoteAddress: peer)
                    }
                    trace?(.request(method: head.method.rawValue, target: head.uri, headers: DICOMwebExchangeTrace.fields(head.headers)))
                    var body = reader.body()
                    if let trace {
                        let untraced = body
                        body = AsyncThrowingStream { continuation in
                            let task = Task {
                                do {
                                    for try await chunk in untraced {
                                        trace(.requestBody(chunk))
                                        continuation.yield(chunk)
                                    }
                                    continuation.finish()
                                } catch {
                                    continuation.finish(throwing: error)
                                }
                            }
                            continuation.onTermination = { _ in task.cancel() }
                        }
                    }
                    let request = DICOMwebHTTPRequest(
                        method: head.method.rawValue, path: String(parts[0]), query: parts.count > 1 ? String(parts[1]) : "",
                        headers: headers, body: body)
                    let certificate = try? await peerCertificate(channel)
                    let response = await origin.respond(
                        to: request, origin: answeredOrigin, remoteAddress: peer, peerCertificate: certificate)
                    // Unread payload bytes are discarded before the response.
                    try await reader.drainBody()
                    do {
                        try await write(response, method: head.method, keepAlive: head.isKeepAlive, version: head.version,
                                        to: outbound, trace: trace)
                        trace?(.end(error: nil))
                    } catch {
                        trace?(.end(error: String(describing: error)))
                        throw error
                    }
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
        to outbound: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>, trace: DICOMwebExchangeTrace? = nil
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
        let writeHead = { (head: HTTPResponseHead) in
            var fields = DICOMwebExchangeTrace.fields(head.headers)
            // As NIO frames it: chunked, without a length.
            if head.headers["Content-Length"].isEmpty && head.headers["Transfer-Encoding"].isEmpty {
                fields.append((name: "Transfer-Encoding", value: "chunked"))
            }
            trace?(.response(status: Int(head.status.code), reason: head.status.reasonPhrase, headers: fields))
            try await outbound.write(.head(head))
        }
        switch response.body {
        case .empty:
            try await writeHead(head(0))
        case .data(let data):
            try await writeHead(head(data.count))
            if method != .HEAD && !data.isEmpty {
                trace?(.responseBody(data))
                try await outbound.write(.body(.byteBuffer(ByteBuffer(bytes: data))))
            }
        case .stream(let stream, let length):
            // Without a known length, HTTP/1.1 chunked transfer coding applies.
            try await writeHead(head(length))
            if method != .HEAD {
                for try await chunk in stream {
                    trace?(.responseBody(chunk))
                    try await outbound.write(.body(.byteBuffer(ByteBuffer(bytes: chunk))))
                }
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
