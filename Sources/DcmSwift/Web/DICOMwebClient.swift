import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1

/// An error answered by a DICOMweb origin server, or a malformed response.
public struct DICOMwebClientError: Error, Equatable, CustomStringConvertible {
    /// The HTTP status, or 0 for a malformed response.
    public let status: Int
    public let message: String

    public init(status: Int, message: String) {
        self.status = status
        self.message = message
    }

    public var description: String { status == 0 ? "DICOMweb: \(message)" : "DICOMweb \(status): \(message)" }
}

/// The matches of a Search Transaction.
public struct DICOMwebSearchResult: Sendable {
    public let matches: [DataSet]
    /// Warning header fields, such as "There are 3 additional results that
    /// can be requested" (PS3.18 8.3.4.4.1).
    public let warnings: [String]
    /// The number of further matches the origin server announced, if any.
    public var remaining: Int? {
        for warning in warnings {
            guard let range = warning.range(of: "There are ") else { continue }
            let digits = warning[range.upperBound...].prefix { $0.isNumber }
            if let count = Int(digits) { return count }
        }
        return nil
    }
}

/// An instance received by the Retrieve Transaction: a Part 10 file.
public struct DICOMwebRetrievedInstance: Sendable {
    public let contentLocation: String?
    public let transferSyntaxUID: String?
    /// The Part 10 bytes.
    public let data: Data

    /// The data set of the instance.
    public func dataSet() throws -> DataSet {
        let header = try DICOMPart10Header.parse(data, totalLength: UInt64(data.count), name: contentLocation ?? "an instance")
        return try DICOMDataSetCoding.decode(data.dropFirst(Int(header.dataSetOffset)), transferSyntax: header.transferSyntaxUID)
    }
}

/// A user agent of the Studies Service (PS3.18 10): QIDO-RS, WADO-RS, and
/// STOW-RS over AsyncHTTPClient.
public final class DICOMwebClient: Sendable {
    /// The Base URI of the service, without a trailing slash.
    public let baseURI: String
    /// Header fields added to every request, such as Authorization.
    public let headers: [(name: String, value: String)]
    public let timeout: TimeAmount
    private let httpClient: HTTPClient

    public init(baseURI: String, headers: [(name: String, value: String)] = [], timeout: TimeAmount = .seconds(60),
                httpClient: HTTPClient = .shared) {
        var baseURI = baseURI
        while baseURI.hasSuffix("/") { baseURI.removeLast() }
        self.baseURI = baseURI
        self.headers = headers
        self.timeout = timeout
        self.httpClient = httpClient
    }

    // MARK: Search (QIDO-RS, PS3.18 10.6)

    /// Searches for studies, series, or instances; `study` and `series`
    /// scope the search to their children.
    public func search(
        _ level: DICOMwebSearchLevel, study: String? = nil, series: String? = nil,
        query: DICOMwebSearchQuery = DICOMwebSearchQuery()
    ) async throws -> DICOMwebSearchResult {
        let resource = DICOMwebResource.search(level, study: study, series: series)
        let target = resource.path + (query.queryString.isEmpty ? "" : "?" + query.queryString)
        let response = try await execute(.GET, target, accept: DICOMwebMediaType.dicomJSON.description)
        let body = try await Self.collect(response.body)
        try Self.check(response, body)
        let matches = body.isEmpty ? [] : try DICOMJSON.decode(body)
        return DICOMwebSearchResult(matches: matches, warnings: response.headers["Warning"])
    }

    // MARK: Retrieve (WADO-RS, PS3.18 10.4)

    /// The instances of a study, series, or instance. `transferSyntax` asks
    /// for a Transfer Syntax: nil for Explicit VR Little Endian, "*" for the
    /// stored one. Instances are delivered as their parts arrive.
    public func instances(
        study: String, series: String? = nil, instance: String? = nil, transferSyntax: String? = nil
    ) -> AsyncThrowingStream<DICOMwebRetrievedInstance, Error> {
        var type = DICOMwebMediaType.dicom
        if let transferSyntax { type = type.with("transfer-syntax", transferSyntax) }
        let resource = DICOMwebResource.target(study: study, series: series, instance: instance)
        return parts(resource.path, accept: DICOMwebMediaType.multipartRelated(type).description) { part in
            DICOMwebRetrievedInstance(contentLocation: part.headers.contentLocation,
                                      transferSyntaxUID: part.headers.contentType?.transferSyntax, data: part.body)
        }
    }

    /// The metadata of the instances of a study, series, or instance. Bulk
    /// Data is not loaded: such elements keep their `bulkDataURI`.
    public func metadata(study: String, series: String? = nil, instance: String? = nil) async throws -> [DataSet] {
        let resource = DICOMwebResource.target(study: study, series: series, instance: instance, kind: .metadata)
        let response = try await execute(.GET, resource.path, accept: DICOMwebMediaType.dicomJSON.description)
        let body = try await Self.collect(response.body)
        try Self.check(response, body)
        return try DICOMJSON.decode(body, options: .init(keepsBulkDataURIs: true))
    }

    /// Frames of an instance (one-based), uncompressed by default, or in a
    /// compressed media type such as `image/jls`.
    public func frames(
        _ numbers: [Int], study: String, series: String, instance: String,
        mediaType: DICOMwebMediaType = .octetStream
    ) async throws -> [Data] {
        let resource = DICOMwebResource.frames(numbers, study: study, series: series, instance: instance)
        var frames: [Data] = []
        for try await frame in parts(resource.path, accept: DICOMwebMediaType.multipartRelated(mediaType).description,
                                     transform: { $0.body }) {
            frames.append(frame)
        }
        return frames
    }

    /// A rendered representation, such as a JPEG image of a frame; several
    /// images come back for multi-frame or multi-instance resources.
    ///
    /// `multipart` chooses the media type asked for: a single image for an
    /// instance, one frame, or a thumbnail, and multipart/related otherwise,
    /// unless given. Only one is sent, since some origin servers do not
    /// accept a list for rendered resources.
    public func rendered(
        _ resource: DICOMwebResource, mediaType: DICOMwebMediaType = .jpeg,
        parameters: [String: String] = [:], multipart: Bool? = nil
    ) async throws -> [Data] {
        let query = parameters.keys.sorted().map { "\($0)=\(DICOMwebSearchQuery.encode(parameters[$0]!))" }.joined(separator: "&")
        let target = resource.path + (query.isEmpty ? "" : "?" + query)
        let single = resource.kind == .thumbnail || (resource.frames?.count ?? (resource.instance != nil ? 1 : 2)) == 1
        let accept = (multipart ?? !single) ? DICOMwebMediaType.multipartRelated(mediaType) : mediaType
        let response = try await execute(.GET, target, accept: accept.description)
        guard let type = response.headers["Content-Type"].first.flatMap(DICOMwebMediaType.init), type.isMultipartRelated else {
            let body = try await Self.collect(response.body)
            try Self.check(response, body)
            return [body]
        }
        var images: [Data] = []
        for try await part in Self.parts(response) { images.append(part.body) }
        return images
    }

    // MARK: Store (STOW-RS, PS3.18 10.5)

    /// Stores Part 10 files, streamed from disk. With `study`, every
    /// instance must belong to that study.
    public func store(files: [URL], study: String? = nil) async throws -> DICOMwebStoreResponse {
        var lengths: [Int] = []
        for url in files {
            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
            lengths.append(size)
        }
        var writer = DICOMwebMultipart.Writer()
        var part = DICOMwebMultipart.Headers()
        part["Content-Type"] = DICOMwebMediaType.dicom.description
        let partHeaders = zip(files, lengths).map { _, length in writer.partHeader(part, length: length) }
        let close = writer.close()
        let total = partHeaders.reduce(close.count) { $0 + $1.count } + lengths.reduce(0, +)
        let chunks = AsyncThrowingStream<ByteBuffer, Error> { continuation in
            do {
                for (url, header) in zip(files, partHeaders) {
                    continuation.yield(ByteBuffer(bytes: header))
                    let file = try DICOMPOSIXFile.open(reading: url)
                    while true {
                        let chunk = try file.read(upTo: 1 << 20)
                        if chunk.isEmpty { break }
                        continuation.yield(ByteBuffer(bytes: chunk))
                    }
                    try file.close()
                }
                continuation.yield(ByteBuffer(bytes: close))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        return try await store(.stream(chunks, length: .known(Int64(total))), boundary: writer.boundary, study: study)
    }

    /// Stores data sets, encoded in Explicit VR Little Endian unless they
    /// declare another Transfer Syntax.
    public func store(_ dataSets: [DataSet], study: String? = nil) async throws -> DICOMwebStoreResponse {
        var writer = DICOMwebMultipart.Writer()
        var part = DICOMwebMultipart.Headers()
        part["Content-Type"] = DICOMwebMediaType.dicom.description
        var body = Data()
        for dataSet in dataSets {
            let syntax = dataSet.transferSyntax?.tsUID ?? TransferSyntax.explicitVRLittleEndian
            let item = try DICOMRetrieveItem(dataSet: dataSet, transferSyntaxUID: syntax)
            body += writer.part(part, body: DICOMPart10Header.encodeMetaInformation(
                sopClassUID: item.sopClassUID, sopInstanceUID: item.sopInstanceUID, transferSyntaxUID: syntax,
                sourceAETitle: nil) + (try item.payload.data()))
        }
        body += writer.close()
        return try await store(.bytes(ByteBuffer(bytes: body)), boundary: writer.boundary, study: study)
    }

    private func store(_ body: HTTPClientRequest.Body, boundary: String, study: String?) async throws -> DICOMwebStoreResponse {
        let path = study.map { "/studies/\($0)" } ?? "/studies"
        let contentType = DICOMwebMediaType.multipartRelated(.dicom, boundary: boundary).description
        let response = try await execute(.POST, path, accept: DICOMwebMediaType.dicomJSON.description,
                                         contentType: contentType, body: body)
        let payload = try await Self.collect(response.body)
        // 409 carries the module too, describing why nothing was stored.
        guard [200, 202, 409].contains(Int(response.status.code)),
              response.headers["Content-Type"].first.flatMap(DICOMwebMediaType.init)?.essence == "application/dicom+json",
              let dataSet = try DICOMJSON.decode(payload).first else {
            try Self.check(response, payload)
            throw DICOMwebClientError(status: Int(response.status.code), message: "no Store Instances Response Module")
        }
        return try DICOMwebStoreResponse(dataSet: dataSet)
    }

    // MARK: Capabilities (PS3.18 8.9)

    /// The WADL Capabilities Description of the service.
    public func capabilities() async throws -> String {
        let response = try await execute(.OPTIONS, "", accept: "application/vnd.sun.wadl+xml")
        let body = try await Self.collect(response.body)
        try Self.check(response, body)
        return String(decoding: body, as: UTF8.self)
    }

    // MARK: Transport

    private func execute(
        _ method: HTTPMethod, _ target: String, accept: String, contentType: String? = nil,
        body: HTTPClientRequest.Body? = nil
    ) async throws -> HTTPClientResponse {
        var request = HTTPClientRequest(url: baseURI + target)
        request.method = method
        for header in headers { request.headers.add(name: header.name, value: header.value) }
        request.headers.replaceOrAdd(name: "Accept", value: accept)
        if let contentType { request.headers.replaceOrAdd(name: "Content-Type", value: contentType) }
        if let body { request.body = body }
        return try await httpClient.execute(request, timeout: timeout)
    }

    private func parts<T: Sendable>(
        _ target: String, accept: String, transform: @escaping @Sendable (DICOMwebMultipart.Part) throws -> T
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await execute(.GET, target, accept: accept)
                    for try await part in Self.parts(response) { continuation.yield(try transform(part)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The parts of a multipart/related response, each complete, as they
    /// arrive.
    static func parts(_ response: HTTPClientResponse) -> AsyncThrowingStream<DICOMwebMultipart.Part, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard response.status == .ok else {
                        let body = try await collect(response.body)
                        try check(response, body)
                        throw DICOMwebClientError(status: Int(response.status.code), message: "unexpected status")
                    }
                    guard let type = response.headers["Content-Type"].first.flatMap(DICOMwebMediaType.init),
                          type.isMultipartRelated, let boundary = type.boundary else {
                        throw DICOMwebClientError(status: 0, message: "the response is not multipart/related")
                    }
                    var parser = try DICOMwebMultipart.Parser(boundary: boundary)
                    var current: DICOMwebMultipart.Part?
                    for try await buffer in response.body {
                        for event in try parser.feed(buffer.readableBytesView) {
                            switch event {
                            case .partStart(let headers): current = DICOMwebMultipart.Part(headers: headers, body: Data())
                            case .bodyChunk(let chunk): current?.body += chunk
                            case .partEnd:
                                if let part = current { continuation.yield(part) }
                                current = nil
                            }
                        }
                    }
                    try parser.finish()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func collect(_ body: HTTPClientResponse.Body) async throws -> Data {
        var data = Data()
        for try await buffer in body { data.append(contentsOf: buffer.readableBytesView) }
        return data
    }

    /// Throws for an error status, with the text of its Status Report.
    static func check(_ response: HTTPClientResponse, _ body: Data) throws {
        let code = Int(response.status.code)
        guard !(200..<300).contains(code) else { return }
        var message = String(decoding: body.prefix(2000), as: UTF8.self)
        if let start = message.range(of: "<p>"), let end = message.range(of: "</p>", range: start.upperBound..<message.endIndex) {
            message = String(message[start.upperBound..<end.lowerBound])
        }
        throw DICOMwebClientError(status: code, message: message.isEmpty ? response.status.reasonPhrase : message)
    }
}
