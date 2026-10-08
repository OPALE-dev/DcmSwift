import Foundation

/// A `multipart/related` payload (RFC 2387, PS3.18 8.6.1.2): writes parts,
/// and parses a payload incrementally as its bytes arrive.
public enum DICOMwebMultipart {
    /// A new random boundary, made of characters every implementation accepts.
    public static func makeBoundary() -> String {
        "DcmSwift-" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    /// The header fields of a part, by name as written; lookups ignore case.
    public struct Headers: Sendable, Equatable, Sequence {
        public private(set) var fields: [(name: String, value: String)]

        public init(_ fields: [(name: String, value: String)] = []) {
            self.fields = fields
        }

        public subscript(name: String) -> String? {
            get { fields.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value }
            set {
                fields.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                if let newValue { fields.append((name, newValue)) }
            }
        }

        public var contentType: DICOMwebMediaType? { self["Content-Type"].flatMap(DICOMwebMediaType.init) }
        public var contentLocation: String? { self["Content-Location"] }

        public func makeIterator() -> IndexingIterator<[(name: String, value: String)]> {
            fields.makeIterator()
        }

        public static func == (lhs: Headers, rhs: Headers) -> Bool {
            lhs.fields.map { "\($0.name.lowercased()):\($0.value)" } == rhs.fields.map { "\($0.name.lowercased()):\($0.value)" }
        }
    }

    /// Encodes the parts of a payload in order. Each call returns the bytes
    /// to send; `close()` returns the final delimiter.
    public struct Writer: Sendable {
        public let boundary: String
        private var wroteFirstPart = false

        public init(boundary: String = DICOMwebMultipart.makeBoundary()) {
            self.boundary = boundary
        }

        /// The delimiter and header fields that start a part. Its body
        /// follows; Content-Length is added when `length` is known.
        public mutating func partHeader(_ headers: Headers, length: Int? = nil) -> Data {
            var text = (wroteFirstPart ? "\r\n" : "") + "--\(boundary)\r\n"
            wroteFirstPart = true
            var headers = headers
            if let length, headers["Content-Length"] == nil { headers["Content-Length"] = String(length) }
            for field in headers.fields { text += "\(field.name): \(field.value)\r\n" }
            return Data((text + "\r\n").utf8)
        }

        /// A whole part: its delimiter, header fields, and body.
        public mutating func part(_ headers: Headers, body: Data) -> Data {
            partHeader(headers, length: body.count) + body
        }

        /// The close delimiter, which ends the payload.
        public func close() -> Data {
            Data(((wroteFirstPart ? "\r\n" : "") + "--\(boundary)--\r\n").utf8)
        }

        /// A complete payload.
        public static func encode(_ parts: [(Headers, Data)], boundary: String = DICOMwebMultipart.makeBoundary()) -> Data {
            var writer = Writer(boundary: boundary)
            var data = Data()
            for (headers, body) in parts { data += writer.part(headers, body: body) }
            return data + writer.close()
        }
    }

    /// What the parser found in the bytes given so far.
    public enum Event: Equatable, Sendable {
        /// A part begins with these header fields.
        case partStart(Headers)
        /// Bytes of the current part's body, in order.
        case bodyChunk(Data)
        /// The current part is complete.
        case partEnd
    }

    public struct ParseError: Error, Equatable, CustomStringConvertible {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var description: String { "multipart/related: \(message)" }
    }

    /// Parses a payload incrementally: feed bytes as they arrive, collect the
    /// events, then call `finish()`. Body bytes are released as soon as they
    /// cannot belong to a delimiter, so large parts are not held in memory.
    public struct Parser: Sendable {
        private enum State { case preamble, headers, body, epilogue }

        private let delimiter: [UInt8]
        private var buffer: [UInt8] = []
        private var state = State.preamble
        private let maximumHeaderLength: Int

        public init(boundary: String, maximumHeaderLength: Int = 16 * 1024) throws {
            guard (1...70).contains(boundary.utf8.count) else { throw ParseError("invalid boundary") }
            self.delimiter = Array("\r\n--\(boundary)".utf8)
            self.maximumHeaderLength = maximumHeaderLength
        }

        /// Parses the next bytes of the payload.
        public mutating func feed(_ bytes: some Sequence<UInt8>) throws -> [Event] {
            buffer.append(contentsOf: bytes)
            var events: [Event] = []
            while try step(&events) {}
            return events
        }

        /// Checks that the payload ended with its close delimiter.
        public func finish() throws {
            guard state == .epilogue else { throw ParseError("the payload ends before its close delimiter") }
        }

        /// Parses one unit; returns false when more bytes are needed.
        private mutating func step(_ events: inout [Event]) throws -> Bool {
            switch state {
            case .preamble:
                // The first delimiter may start the payload without CRLF.
                let first = Array(delimiter.dropFirst(2))
                if buffer.starts(with: first) {
                    buffer.removeFirst(first.count)
                } else if let index = find(delimiter) {
                    buffer.removeFirst(index + delimiter.count)
                } else {
                    // Keep what could be the start of a split delimiter.
                    if buffer.count > delimiter.count { buffer.removeFirst(buffer.count - delimiter.count) }
                    return false
                }
                state = .headers
                return true
            case .headers:
                // After a delimiter: "--" closes, otherwise optional
                // whitespace then CRLF precede the header fields.
                guard buffer.count >= 2 else { return false }
                if buffer[0] == UInt8(ascii: "-") && buffer[1] == UInt8(ascii: "-") {
                    buffer.removeAll()
                    state = .epilogue
                    return false
                }
                guard let end = find(Array("\r\n\r\n".utf8)) ?? (buffer.starts(with: Array("\r\n\r\n".utf8)) ? 0 : nil)
                else {
                    if buffer.count > maximumHeaderLength { throw ParseError("part header fields too long") }
                    return false
                }
                let text = String(decoding: buffer[..<end], as: UTF8.self)
                buffer.removeFirst(end + 4)
                events.append(.partStart(try Self.headers(text)))
                state = .body
                return true
            case .body:
                if let index = find(delimiter) {
                    if index > 0 { events.append(.bodyChunk(Data(buffer[..<index]))) }
                    buffer.removeFirst(index + delimiter.count)
                    events.append(.partEnd)
                    state = .headers
                    return true
                }
                let safe = buffer.count - (delimiter.count - 1)
                if safe > 0 {
                    events.append(.bodyChunk(Data(buffer[..<safe])))
                    buffer.removeFirst(safe)
                }
                return false
            case .epilogue:
                buffer.removeAll()
                return false
            }
        }

        private func find(_ pattern: [UInt8]) -> Int? {
            guard buffer.count >= pattern.count, let first = pattern.first else { return nil }
            var index = 0
            let last = buffer.count - pattern.count
            while index <= last {
                if buffer[index] == first && buffer[index..<(index + pattern.count)].elementsEqual(pattern) { return index }
                index += 1
            }
            return nil
        }

        /// The header fields after a delimiter line: transport padding, CRLF,
        /// then `name: value` lines.
        private static func headers(_ text: String) throws -> Headers {
            var lines = text.components(separatedBy: "\r\n")
            // The rest of the delimiter line may only hold whitespace.
            let padding = lines.removeFirst()
            guard padding.allSatisfy({ $0 == " " || $0 == "\t" }) else {
                throw ParseError("unexpected characters after a boundary")
            }
            var headers = Headers()
            for line in lines where !line.isEmpty {
                guard let colon = line.firstIndex(of: ":") else { throw ParseError("malformed header field \(line)") }
                headers[String(line[..<colon]).trimmingCharacters(in: .whitespaces)] =
                    String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
            return headers
        }
    }

    /// A part read whole.
    public struct Part: Sendable, Equatable {
        public var headers: Headers
        public var body: Data

        public init(headers: Headers, body: Data) {
            self.headers = headers
            self.body = body
        }
    }

    /// Parses a complete payload held in memory.
    public static func parse(_ payload: Data, boundary: String) throws -> [Part] {
        var parser = try Parser(boundary: boundary)
        var parts: [Part] = []
        for event in try parser.feed(payload) {
            switch event {
            case .partStart(let headers): parts.append(Part(headers: headers, body: Data()))
            case .bodyChunk(let chunk): parts[parts.count - 1].body += chunk
            case .partEnd: break
            }
        }
        try parser.finish()
        return parts
    }
}
