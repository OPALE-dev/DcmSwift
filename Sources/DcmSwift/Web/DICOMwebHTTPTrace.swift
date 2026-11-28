import Foundation
import NIOCore
import NIOHTTP1

/// A moment of an HTTP exchange (RFC 9110) of a DICOMweb user agent or
/// origin server: its request head, its response head, a piece of either
/// payload, or its end. A debugging console rebuilds each exchange from
/// these records, the same `exchange` for all of them, in order.
public struct DICOMwebHTTPTraceRecord: Sendable {
    public enum Event: Sendable {
        /// The request line and header fields. A user agent traces the
        /// fields it gives AsyncHTTPClient, which adds Host and the framing
        /// fields (Content-Length or Transfer-Encoding); an origin server,
        /// those it received.
        case request(method: String, target: String, headers: [(name: String, value: String)])
        /// The status line and header fields: as received by a user agent,
        /// as sent by an origin server, framing fields included.
        case response(status: Int, reason: String, headers: [(name: String, value: String)])
        /// A piece of the request payload, as sent or received.
        case requestBody(Data)
        /// A piece of the response payload, as received or sent.
        case responseBody(Data)
        /// The exchange is over: the response payload ended, or the
        /// exchange failed with this error. A user agent traces it once the
        /// response payload has been read, which a caller that stops
        /// reading a stream early never does.
        case end(error: String?)
    }

    /// The exchange, the same for every record of one request and its response.
    public let exchange: UUID
    /// The connection of an origin server, the same for the exchanges of
    /// one persistent connection; nil for a user agent, whose connections
    /// AsyncHTTPClient pools.
    public let connection: UUID?
    public let time: Date
    /// The scheme and authority: those of the Base URI for a user agent,
    /// the origin a server answers for.
    public let origin: String
    /// The address of the peer: the client of an origin server; nil for a user agent.
    public let remoteAddress: String?
    public let event: Event

    public init(exchange: UUID, connection: UUID? = nil, time: Date = Date(), origin: String, remoteAddress: String? = nil,
                event: Event) {
        self.exchange = exchange
        self.connection = connection
        self.time = time
        self.origin = origin
        self.remoteAddress = remoteAddress
        self.event = event
    }
}

/// Receives each moment of each HTTP exchange; it must return quickly.
/// Without one, no payload is copied.
public typealias DICOMwebHTTPTrace = @Sendable (DICOMwebHTTPTraceRecord) -> Void

/// The trace of one exchange.
struct DICOMwebExchangeTrace: Sendable {
    let trace: DICOMwebHTTPTrace
    let exchange = UUID()
    let connection: UUID?
    let origin: String
    let remoteAddress: String?

    func callAsFunction(_ event: DICOMwebHTTPTraceRecord.Event) {
        trace(DICOMwebHTTPTraceRecord(exchange: exchange, connection: connection, origin: origin,
                                      remoteAddress: remoteAddress, event: event))
    }

    static func fields(_ headers: HTTPHeaders) -> [(name: String, value: String)] {
        headers.map { (name: $0.name, value: $0.value) }
    }

    /// `chunks`, each traced as it passes.
    func tracing<Chunks: AsyncSequence & Sendable>(
        _ chunks: Chunks, _ event: @escaping @Sendable (Data) -> DICOMwebHTTPTraceRecord.Event,
        endsExchange: Bool
    ) -> AsyncThrowingStream<ByteBuffer, Error> where Chunks.Element == ByteBuffer {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in chunks {
                        if chunk.readableBytes > 0 { self(event(Data(chunk.readableBytesView))) }
                        continuation.yield(chunk)
                    }
                    if endsExchange { self(.end(error: nil)) }
                    continuation.finish()
                } catch {
                    if endsExchange { self(.end(error: String(describing: error))) }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
