import Foundation
import NIOSSL

/// An HTTP request as the origin server sees it, independent of transport.
public struct DICOMwebHTTPRequest: Sendable {
    public var method: String
    /// The percent-encoded path, without the query component.
    public var path: String
    /// The query component, without "?".
    public var query: String
    public var headers: DICOMwebMultipart.Headers
    /// The payload, as it arrives.
    public var body: AsyncThrowingStream<Data, Error>

    public init(method: String, path: String, query: String = "", headers: DICOMwebMultipart.Headers = .init(),
                body: AsyncThrowingStream<Data, Error> = AsyncThrowingStream { $0.finish() }) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }

    /// A request whose payload is held in memory.
    public init(method: String, target: String, headers: DICOMwebMultipart.Headers = .init(), body: Data) {
        let parts = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        self.init(method: method, path: String(parts[0]), query: parts.count > 1 ? String(parts[1]) : "",
                  headers: headers, body: AsyncThrowingStream { continuation in
                      if !body.isEmpty { continuation.yield(body) }
                      continuation.finish()
                  })
    }
}

/// An HTTP response produced by the origin server.
public struct DICOMwebHTTPResponse: Sendable {
    public enum Body: Sendable {
        case empty
        case data(Data)
        /// Bytes produced while they are sent, such as instances read from
        /// disk; `length` is the total when known.
        case stream(AsyncThrowingStream<Data, Error>, length: Int?)
    }

    public var status: Int
    public var headers: DICOMwebMultipart.Headers
    public var body: Body

    public init(status: Int, headers: DICOMwebMultipart.Headers = .init(), body: Body = .empty) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// The whole payload, collected.
    public func collectBody() async throws -> Data {
        switch body {
        case .empty: return Data()
        case .data(let data): return data
        case .stream(let stream, _):
            var data = Data()
            for try await chunk in stream { data += chunk }
            return data
        }
    }
}

/// Limits and options of a DICOMweb origin server.
public struct DICOMwebServerConfiguration: Sendable {
    /// The path of the service under the host, such as "/dicomweb"; empty
    /// when the service is at the root.
    public var basePath: String
    /// The most matches a search returns at once (PS3.18 8.3.4.4.1).
    public var maximumResults: Int
    /// The longest request payload accepted; longer ones get 413.
    public var maximumRequestLength: Int
    /// A stored part larger than this is spilled to a temporary file.
    public var memoryLimit: Int
    public var temporaryDirectory: URL

    public init(basePath: String = "", maximumResults: Int = 1000, maximumRequestLength: Int = 4 << 30,
                memoryLimit: Int = 16 << 20, temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        var basePath = basePath
        while basePath.hasSuffix("/") { basePath.removeLast() }
        if !basePath.isEmpty && !basePath.hasPrefix("/") { basePath = "/" + basePath }
        self.basePath = basePath
        self.maximumResults = maximumResults
        self.maximumRequestLength = maximumRequestLength
        self.memoryLimit = memoryLimit
        self.temporaryDirectory = temporaryDirectory
    }
}

/// The Studies Service of PS3.18 chapter 10 over DICOMweb services:
/// Search (QIDO-RS), Retrieve (WADO-RS), Store (STOW-RS), and Retrieve
/// Capabilities. It turns requests into responses; `DICOMwebServer` carries
/// them over HTTP.
public struct DICOMwebOriginServer: Sendable {
    public let configuration: DICOMwebServerConfiguration
    public let search: (any DICOMwebSearchService)?
    public let retrieve: (any DICOMwebRetrieveService)?
    public let store: (any DICOMwebStoreService)?

    public init(configuration: DICOMwebServerConfiguration = .init(), search: (any DICOMwebSearchService)? = nil,
                retrieve: (any DICOMwebRetrieveService)? = nil, store: (any DICOMwebStoreService)? = nil) {
        self.configuration = configuration
        self.search = search
        self.retrieve = retrieve
        self.store = store
    }

    /// Answers a request. `origin` is the scheme and authority the request
    /// reached, such as `https://pacs.example.org`.
    public func respond(
        to request: DICOMwebHTTPRequest, origin: String, remoteAddress: String? = nil,
        peerCertificate: NIOSSLCertificate? = nil
    ) async -> DICOMwebHTTPResponse {
        let baseURI = origin + configuration.basePath
        let context = DICOMwebRequestContext(
            remoteAddress: remoteAddress, headers: request.headers, peerCertificate: peerCertificate, baseURI: baseURI)
        do {
            guard let relative = relativePath(request.path) else { return Self.report(404, "No such resource") }
            if relative.isEmpty || relative == ["/"] || relative.allSatisfy(\.isEmpty) {
                guard request.method == "OPTIONS" else { return Self.report(405, "Use OPTIONS", allow: "OPTIONS") }
                return capabilities(baseURI)
            }
            guard let resource = DICOMwebResource(pathComponents: relative) else {
                return Self.report(404, "No such resource")
            }
            switch (request.method, resource.kind) {
            case ("OPTIONS", _):
                return capabilities(baseURI)
            case ("GET", .search), ("HEAD", .search):
                return try await searchResponse(resource, request, context)
            case ("POST", .search) where resource.searchLevel == .study,
                 ("POST", .instances) where resource.series == nil:
                return try await storeResponse(resource, request, context)
            case ("GET", .instances), ("HEAD", .instances):
                return try await instancesResponse(resource, request, context)
            case ("GET", .metadata), ("HEAD", .metadata):
                return try await metadataResponse(resource, request, context)
            case ("GET", .frames), ("GET", .pixeldata), ("HEAD", .frames), ("HEAD", .pixeldata):
                return try await pixelResponse(resource, request, context)
            case ("GET", .rendered), ("GET", .thumbnail), ("HEAD", .rendered), ("HEAD", .thumbnail):
                return try await renderedResponse(resource, request, context)
            case ("GET", .bulkdata):
                return Self.report(501, "Bulk Data is retrieved through the Bulk Data URIs of the metadata")
            default:
                let allow = resource.kind == .search ? "GET, POST, OPTIONS" : "GET, OPTIONS"
                return Self.report(405, "\(request.method) is not supported on \(resource.path)", allow: allow)
            }
        } catch let error as DICOMwebHTTPError {
            return Self.report(error.status, error.message)
        } catch {
            return Self.report(500, String(describing: error))
        }
    }

    /// The path components below the base path, or nil outside it.
    private func relativePath(_ path: String) -> [String]? {
        let decoded = path.removingPercentEncoding ?? path
        guard decoded.hasPrefix(configuration.basePath) else { return nil }
        let rest = decoded.dropFirst(configuration.basePath.count)
        guard rest.isEmpty || rest.hasPrefix("/") else { return nil }
        return rest.split(separator: "/").map(String.init)
    }

    // MARK: Search

    private func searchResponse(
        _ resource: DICOMwebResource, _ request: DICOMwebHTTPRequest, _ context: DICOMwebRequestContext
    ) async throws -> DICOMwebHTTPResponse {
        guard let search, let level = resource.searchLevel else { return Self.report(501, "Search is not supported") }
        let query: DICOMwebSearchQuery
        do { query = try DICOMwebSearchQuery(query: request.query) } catch {
            return Self.report(400, String(describing: error))
        }
        let selected = try negotiate(request, query: query.otherParameters,
                                     supported: [.dicomJSON, .multipartRelated(.dicomXML)], defaultType: .dicomJSON)

        var returnKeys = level.responseKeywords
        // Relational searches return the attributes of the levels above
        // (PS3.18 10.6.3.3.2, 10.6.3.3.3), and every match needs the UIDs of
        // its Retrieve URL.
        if level != .study {
            if resource.study == nil { returnKeys = DICOMwebSearchLevel.study.responseKeywords + returnKeys }
            if level == .instance && resource.series == nil {
                returnKeys = DICOMwebSearchLevel.series.responseKeywords + returnKeys
            }
            returnKeys += ["StudyInstanceUID"] + (level == .instance ? ["SeriesInstanceUID"] : [])
        }
        let identifier = query.identifier(level: level, returnKeywords: returnKeys)
        if let study = resource.study { _ = identifier.set(value: study, forTagName: "StudyInstanceUID") }
        if let series = resource.series { _ = identifier.set(value: series, forTagName: "SeriesInstanceUID") }

        let matches = try await search.search(identifier, level: level, query: query, context: context)
        let limit = min(query.limit ?? configuration.maximumResults, configuration.maximumResults)
        let page = Array(matches.dropFirst(query.offset).prefix(limit))
        let remaining = max(0, matches.count - query.offset - page.count)
        for match in page {
            if let url = retrieveURL(of: match, level: level, baseURI: context.baseURI) {
                _ = match.set(value: url, forTagName: "RetrieveURL")
            }
            _ = match.remove(elementForTagName: "QueryRetrieveLevel")
        }

        var headers = DICOMwebMultipart.Headers()
        var warnings: [String] = []
        if remaining > 0 { warnings.append("299 \(context.baseURI): There are \(remaining) additional results that can be requested") }
        if query.fuzzyMatching {
            warnings.append("299 \(context.baseURI): The fuzzymatching parameter is not supported. Only literal matching has been performed.")
        }
        if query.emptyValueMatching {
            warnings.append("299 \(context.baseURI): The emptyvaluematching parameter is not supported. Empty Value Matching has not been performed.")
        }
        if query.multipleValueMatching {
            warnings.append("299 \(context.baseURI): The multiplevaluematching parameter is not supported. Multiple Value Matching has not been performed.")
        }
        if !warnings.isEmpty { headers["Warning"] = warnings.joined(separator: ", ") }

        if selected.isMultipartRelated {
            var writer = DICOMwebMultipart.Writer()
            var body = Data()
            var partHeaders = DICOMwebMultipart.Headers()
            partHeaders["Content-Type"] = DICOMwebMediaType.dicomXML.description
            for match in page { body += writer.part(partHeaders, body: try DICOMXML.encode(match)) }
            if page.isEmpty {
                // An empty result is an empty NativeDicomModel (PS3.18 8.3.4.4.1).
                body += writer.part(partHeaders, body: try DICOMXML.encode(DataSet()))
            }
            body += writer.close()
            headers["Content-Type"] = DICOMwebMediaType.multipartRelated(.dicomXML, boundary: writer.boundary).description
            return DICOMwebHTTPResponse(status: 200, headers: headers, body: .data(request.method == "HEAD" ? Data() : body))
        }
        headers["Content-Type"] = DICOMwebMediaType.dicomJSON.description
        let body = try DICOMJSON.encode(page)
        return DICOMwebHTTPResponse(status: 200, headers: headers, body: .data(request.method == "HEAD" ? Data() : body))
    }

    private func retrieveURL(of match: DataSet, level: DICOMwebSearchLevel, baseURI: String) -> String? {
        guard let study = match.string(forTag: "StudyInstanceUID"), !study.isEmpty else { return nil }
        var url = "\(baseURI)/studies/\(study)"
        if level == .study { return url }
        guard let series = match.string(forTag: "SeriesInstanceUID"), !series.isEmpty else { return nil }
        url += "/series/\(series)"
        if level == .series { return url }
        guard let instance = match.string(forTag: "SOPInstanceUID"), !instance.isEmpty else { return nil }
        return url + "/instances/\(instance)"
    }

    // MARK: Retrieve

    private func items(_ resource: DICOMwebResource, _ context: DICOMwebRequestContext) async throws -> [DICOMRetrieveItem] {
        guard let retrieve else { throw DICOMwebHTTPError(501, "Retrieve is not supported") }
        guard let study = resource.study else { throw DICOMwebHTTPError(404, "No such resource") }
        let items = try await retrieve.instances(study: study, series: resource.series, instance: resource.instance,
                                                 context: context)
        guard !items.isEmpty else { throw DICOMwebHTTPError(404, "\(resource.path) does not exist") }
        return items
    }

    private func instancesResponse(
        _ resource: DICOMwebResource, _ request: DICOMwebHTTPRequest, _ context: DICOMwebRequestContext
    ) async throws -> DICOMwebHTTPResponse {
        let items = try await items(resource, context)
        let accept = Self.acceptQueryParameter(request.query)
        let singleAllowed = resource.instance != nil && items.count == 1
        // The Transfer Syntax of each part is selected separately (PS3.18 8.7.8).
        var selections: [(item: DICOMRetrieveItem, syntax: String)] = []
        var multipart: Bool?
        for item in items {
            let syntaxes = DICOMwebTranscoding.availableTransferSyntaxes(of: item)
            var supported: [DICOMwebMediaType] = []
            if multipart != false {
                supported += syntaxes.map { .multipartRelated(.dicom.with("transfer-syntax", $0)) }
            }
            if singleAllowed && multipart != true {
                supported += syntaxes.map { .dicom.with("transfer-syntax", $0) }
            }
            let defaultType = supported.first { $0.transferSyntax == TransferSyntax.explicitVRLittleEndian && $0.isMultipartRelated }
                ?? supported.first { $0.isMultipartRelated }
            let selected = try negotiate(request, accept: accept, supported: supported, defaultType: defaultType)
            if selected.relatedType?.essence == "application/octet-stream" {
                throw DICOMwebHTTPError(406, "Request the Bulk Data or Pixel Data resource for octet-stream")
            }
            multipart = selected.isMultipartRelated
            selections.append((item, selected.transferSyntax ?? TransferSyntax.explicitVRLittleEndian))
        }
        let base = context.baseURI
        func location(_ item: DICOMRetrieveItem) -> String {
            // The study and series come from the request path when known.
            "\(base)/studies/\(resource.study ?? "")" + (resource.series.map { "/series/\($0)" } ?? "")
                + "/instances/\(item.sopInstanceUID)"
        }
        if multipart == false, let only = selections.first {
            let payload = try DICOMwebTranscoding.payload(only.item, in: only.syntax)
            let meta = DICOMPart10Header.encodeMetaInformation(
                sopClassUID: only.item.sopClassUID, sopInstanceUID: only.item.sopInstanceUID,
                transferSyntaxUID: only.syntax, sourceAETitle: nil)
            var headers = DICOMwebMultipart.Headers()
            headers["Content-Type"] = DICOMwebMediaType.dicom.with("transfer-syntax", only.syntax).description
            headers["Content-Location"] = location(only.item)
            return DICOMwebHTTPResponse(status: 200, headers: headers, body: request.method == "HEAD" ? .empty
                : .stream(Self.stream([(nil, meta, payload)]), length: meta.count + payload.length))
        }

        var writer = DICOMwebMultipart.Writer()
        var parts: [(Data?, Data, DICOMDataSetPayload)] = []
        for selection in selections {
            let payload = try DICOMwebTranscoding.payload(selection.item, in: selection.syntax)
            let meta = DICOMPart10Header.encodeMetaInformation(
                sopClassUID: selection.item.sopClassUID, sopInstanceUID: selection.item.sopInstanceUID,
                transferSyntaxUID: selection.syntax, sourceAETitle: nil)
            var partHeaders = DICOMwebMultipart.Headers()
            partHeaders["Content-Type"] = DICOMwebMediaType.dicom.with("transfer-syntax", selection.syntax).description
            partHeaders["Content-Location"] = location(selection.item)
            parts.append((writer.partHeader(partHeaders, length: meta.count + payload.length), meta, payload))
        }
        let close = writer.close()
        var headers = DICOMwebMultipart.Headers()
        let syntaxes = Set(selections.map(\.syntax))
        var type = DICOMwebMediaType.dicom
        if syntaxes.count == 1 { type = type.with("transfer-syntax", syntaxes.first) }
        headers["Content-Type"] = DICOMwebMediaType.multipartRelated(type, boundary: writer.boundary).description
        var length = close.count
        for (header, meta, payload) in parts {
            length += (header?.count ?? 0) + meta.count + payload.length
        }
        return DICOMwebHTTPResponse(status: 200, headers: headers, body: request.method == "HEAD" ? .empty
            : .stream(Self.stream(parts, trailer: close), length: length))
    }

    /// Streams part headers, File Meta Information, and data set bytes.
    private static func stream(
        _ parts: [(Data?, Data, DICOMDataSetPayload)], trailer: Data = Data()
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            do {
                for (header, meta, payload) in parts {
                    if let header { continuation.yield(header) }
                    continuation.yield(meta)
                    for chunk in try payload.chunks(of: 1 << 20) { continuation.yield(chunk) }
                }
                if !trailer.isEmpty { continuation.yield(trailer) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    private func metadataResponse(
        _ resource: DICOMwebResource, _ request: DICOMwebHTTPRequest, _ context: DICOMwebRequestContext
    ) async throws -> DICOMwebHTTPResponse {
        let items = try await items(resource, context)
        let selected = try negotiate(request, accept: Self.acceptQueryParameter(request.query),
                                     supported: [.dicomJSON, .multipartRelated(.dicomXML)], defaultType: .dicomJSON)
        var dataSets: [DataSet] = []
        var options: [DICOMJSON.EncodingOptions] = []
        for item in items {
            let dataSet = try DICOMwebTranscoding.dataSet(item)
            let study = dataSet.string(forTag: "StudyInstanceUID") ?? resource.study ?? ""
            let series = dataSet.string(forTag: "SeriesInstanceUID") ?? resource.series ?? ""
            let instanceURL = "\(context.baseURI)/studies/\(study)/series/\(series)/instances/\(item.sopInstanceUID)"
            // Pixel Data is referenced by its Pixel Data resource; other
            // binary values stay inline (PS3.18 10.4.3.3.2 permits either).
            var option = DICOMJSON.EncodingOptions()
            option.bulkDataURI = { element in
                // Top-level Pixel Data only, not that of an Icon Image Sequence.
                !(element.parent is DataItem) && DICOMwebTranscoding.pixelDataTags.contains(element.tagCode().lowercased())
                    ? instanceURL + "/pixeldata" : nil
            }
            dataSets.append(dataSet)
            options.append(option)
        }
        var headers = DICOMwebMultipart.Headers()
        if selected.isMultipartRelated {
            var writer = DICOMwebMultipart.Writer()
            var body = Data()
            var partHeaders = DICOMwebMultipart.Headers()
            partHeaders["Content-Type"] = DICOMwebMediaType.dicomXML.description
            for (dataSet, option) in zip(dataSets, options) {
                body += writer.part(partHeaders, body: try DICOMXML.encode(dataSet, options: option))
            }
            body += writer.close()
            headers["Content-Type"] = DICOMwebMediaType.multipartRelated(.dicomXML, boundary: writer.boundary).description
            return DICOMwebHTTPResponse(status: 200, headers: headers, body: .data(request.method == "HEAD" ? Data() : body))
        }
        var objects: [[String: Any]] = []
        for (dataSet, option) in zip(dataSets, options) { objects.append(try DICOMJSON.object(dataSet, options: option)) }
        headers["Content-Type"] = DICOMwebMediaType.dicomJSON.description
        let body = try JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys])
        return DICOMwebHTTPResponse(status: 200, headers: headers, body: .data(request.method == "HEAD" ? Data() : body))
    }

    /// Frames and Pixel Data resources: uncompressed frames as
    /// application/octet-stream, or the stored compressed frames.
    private func pixelResponse(
        _ resource: DICOMwebResource, _ request: DICOMwebHTTPRequest, _ context: DICOMwebRequestContext
    ) async throws -> DICOMwebHTTPResponse {
        let items = try await items(resource, context)
        let accept = Self.acceptQueryParameter(request.query)
        var writer = DICOMwebMultipart.Writer()
        var body = Data()
        var commonType: DICOMwebMediaType?
        for item in items {
            let dataSet = try DICOMwebTranscoding.dataSet(item)
            let description: DICOMPixelDescription
            do { description = try DICOMPixelDescription(dataset: dataSet) } catch {
                if resource.instance != nil { throw DICOMwebHTTPError(404, "The instance has no Pixel Data") }
                continue
            }
            let numbers = resource.frames ?? Array(1...max(1, description.numberOfFrames))
            var supported: [DICOMwebMediaType] = []
            if !description.isEncapsulated || DICOMwebTranscoding.losslessEncapsulated.contains(item.transferSyntaxUID)
                || DICOMCodecRegistry.decoder(for: item.transferSyntaxUID) != nil {
                supported.append(.multipartRelated(.octetStream.with("transfer-syntax", TransferSyntax.explicitVRLittleEndian)))
            }
            if description.isEncapsulated, let compressed = DICOMwebMediaType.compressedBulkData(for: item.transferSyntaxUID) {
                supported.append(.multipartRelated(compressed))
            }
            let selected = try negotiate(request, accept: accept, supported: supported, defaultType: supported.first,
                                         defaultTransferSyntax: description.isEncapsulated && supported.count == 1
                                             ? item.transferSyntaxUID : TransferSyntax.explicitVRLittleEndian)
            let part = selected.relatedType ?? selected
            let compressed = part != .octetStream && part.essence != "application/octet-stream"
            let frames: [Data]
            do { frames = try DICOMwebTranscoding.frames(dataSet, numbers: numbers, compressed: compressed) } catch let error as DICOMPixelDataError {
                if case .frameOutOfRange = error { throw DICOMwebHTTPError(404, String(describing: error)) }
                throw error
            }
            let study = dataSet.string(forTag: "StudyInstanceUID") ?? resource.study ?? ""
            let series = dataSet.string(forTag: "SeriesInstanceUID") ?? resource.series ?? ""
            let instanceURL = "\(context.baseURI)/studies/\(study)/series/\(series)/instances/\(item.sopInstanceUID)"
            var partHeaders = DICOMwebMultipart.Headers()
            partHeaders["Content-Type"] = (compressed ? part : DICOMwebMediaType.octetStream
                .with("transfer-syntax", TransferSyntax.explicitVRLittleEndian)).description
            if compressed || resource.kind == .frames {
                // One part per frame (PS3.18 8.7.3.3).
                for (number, frame) in zip(numbers, frames) {
                    partHeaders["Content-Location"] = resource.kind == .frames
                        ? "\(instanceURL)/frames/\(number)" : "\(instanceURL)/pixeldata"
                    body += writer.part(partHeaders, body: frame)
                }
            } else {
                // Uncompressed multi-frame Pixel Data is one representation.
                partHeaders["Content-Location"] = "\(instanceURL)/pixeldata"
                body += writer.part(partHeaders, body: frames.reduce(Data(), +))
            }
            commonType = commonType ?? (compressed ? part : .octetStream)
        }
        guard let commonType else { throw DICOMwebHTTPError(404, "No Pixel Data in \(resource.path)") }
        body += writer.close()
        var headers = DICOMwebMultipart.Headers()
        headers["Content-Type"] = DICOMwebMediaType.multipartRelated(
            DICOMwebMediaType(type: commonType.type, subtype: commonType.subtype), boundary: writer.boundary).description
        return DICOMwebHTTPResponse(status: 200, headers: headers, body: .data(request.method == "HEAD" ? Data() : body))
    }

    // MARK: Store

    private func storeResponse(
        _ resource: DICOMwebResource, _ request: DICOMwebHTTPRequest, _ context: DICOMwebRequestContext
    ) async throws -> DICOMwebHTTPResponse {
        guard let store else { return Self.report(501, "Store is not supported") }
        let responseType = try negotiate(request, supported: [.dicomJSON, .dicomXML], defaultType: .dicomJSON)
        guard let contentType = request.headers.contentType, contentType.isMultipartRelated,
              let boundary = contentType.boundary, let partType = contentType.relatedType else {
            return Self.report(415, "The payload must be multipart/related")
        }
        guard partType.essence == "application/dicom" else {
            return Self.report(415, "Only application/dicom parts are supported; metadata with Bulk Data is not")
        }
        var parser: DICOMwebMultipart.Parser
        do { parser = try DICOMwebMultipart.Parser(boundary: boundary) } catch {
            return Self.report(400, String(describing: error))
        }
        var response = DICOMwebStoreResponse()
        var sink: DataSetSink?
        var partIsDICOM = false
        var received = 0
        do {
            for try await chunk in request.body {
                received += chunk.count
                guard received <= configuration.maximumRequestLength else {
                    return Self.report(413, "The payload exceeds \(configuration.maximumRequestLength) bytes")
                }
                for event in try parser.feed(chunk) {
                    switch event {
                    case .partStart(let headers):
                        partIsDICOM = (headers.contentType ?? partType).essence == "application/dicom"
                        sink = DataSetSink(memoryLimit: configuration.memoryLimit,
                                           maximumLength: configuration.maximumRequestLength,
                                           directory: configuration.temporaryDirectory)
                    case .bodyChunk(let bytes):
                        if partIsDICOM { try sink?.append(bytes) }
                    case .partEnd:
                        defer { sink = nil }
                        guard partIsDICOM, let sink else {
                            response.otherFailures.append(DICOMwebStoreResponse.cannotUnderstand)
                            continue
                        }
                        await storePart(sink, resource: resource, context: context, into: &response)
                    }
                }
            }
            try parser.finish()
        } catch let error as DICOMwebMultipart.ParseError {
            return Self.report(400, error.description)
        }
        if response.stored.isEmpty && response.failed.isEmpty && response.otherFailures.isEmpty {
            return Self.report(400, "The payload contains no instance")
        }
        if let study = resource.study {
            response.retrieveURL = "\(context.baseURI)/studies/\(study)"
        } else if let first = response.stored.first?.retrieveURL, let range = first.range(of: "/series/") {
            let studyURL = String(first[..<range.lowerBound])
            if response.stored.allSatisfy({ $0.retrieveURL?.hasPrefix(studyURL + "/") ?? false }) {
                response.retrieveURL = studyURL
            }
        }
        var headers = DICOMwebMultipart.Headers()
        let body: Data
        if responseType == .dicomXML {
            headers["Content-Type"] = DICOMwebMediaType.dicomXML.description
            body = try DICOMXML.encode(response.dataSet)
        } else {
            headers["Content-Type"] = DICOMwebMediaType.dicomJSON.description
            body = try DICOMJSON.encode(response.dataSet)
        }
        return DICOMwebHTTPResponse(status: response.httpStatus, headers: headers, body: .data(body))
    }

    private func storePart(
        _ sink: DataSetSink, resource: DICOMwebResource, context: DICOMwebRequestContext,
        into response: inout DICOMwebStoreResponse
    ) async {
        let header: DICOMPart10Header
        do {
            header = try DICOMPart10Header.parse(sink.head, totalLength: UInt64(sink.length), name: "a part",
                                                 requiresSOPIdentification: false)
        } catch {
            response.otherFailures.append(DICOMwebStoreResponse.cannotUnderstand)
            return
        }
        var reference = DICOMwebStoreResponse.Reference(sopClassUID: header.sopClassUID, sopInstanceUID: header.sopInstanceUID)
        do {
            guard TransferSyntax(header.transferSyntaxUID) != nil else {
                reference.reason = DICOMwebStoreResponse.transferSyntaxNotSupported
                response.failed.append(reference)
                return
            }
            let payload = try sink.finish(skipping: Int(header.dataSetOffset))
            let parsed = try DICOMDataSetCoding.decode(payload.data(), transferSyntax: header.transferSyntaxUID)
            // The data set identifies the instance; File Meta Information that
            // disagrees with it is not trusted (PS3.10 7.1).
            let sopClass = parsed.string(forTag: "SOPClassUID").flatMap { $0.isEmpty ? nil : $0 } ?? header.sopClassUID
            let sopInstance = parsed.string(forTag: "SOPInstanceUID").flatMap { $0.isEmpty ? nil : $0 } ?? header.sopInstanceUID
            reference = DICOMwebStoreResponse.Reference(sopClassUID: sopClass, sopInstanceUID: sopInstance)
            guard !sopClass.isEmpty, !sopInstance.isEmpty else {
                reference.reason = DICOMwebStoreResponse.cannotUnderstand
                response.failed.append(reference)
                return
            }
            let instance = DICOMReceivedInstance(
                sopClassUID: sopClass, sopInstanceUID: sopInstance,
                transferSyntaxUID: header.transferSyntaxUID, payload: payload, moveOriginatorAETitle: nil,
                moveOriginatorMessageID: nil, sourceAETitle: "")
            let dataSet = parsed
            let study = dataSet.string(forTag: "StudyInstanceUID") ?? ""
            if let target = resource.study, target != study {
                reference.reason = DICOMwebStoreResponse.studyInstanceUIDMismatch
                response.failed.append(reference)
                return
            }
            switch try await self.store!.store(instance, context: context) {
            case .stored:
                break
            case .storedWithWarning(let reason):
                reference.reason = reason
            case .failed(let reason):
                reference.reason = reason
                response.failed.append(reference)
                return
            }
            let series = dataSet.string(forTag: "SeriesInstanceUID") ?? ""
            reference.retrieveURL = "\(context.baseURI)/studies/\(study)/series/\(series)/instances/\(sopInstance)"
            response.stored.append(reference)
        } catch {
            reference.reason = DICOMwebStoreResponse.processingFailure
            response.failed.append(reference)
        }
    }

    // MARK: Capabilities (PS3.18 8.9, Annex H)

    private func capabilities(_ baseURI: String) -> DICOMwebHTTPResponse {
        func method(_ name: String, _ id: String, _ types: [String]) -> String {
            "<method name=\"\(name)\" id=\"\(id)\"><response>"
                + types.map { "<representation mediaType=\"\(Self.xmlEscape($0))\"/>" }.joined()
                + "</response></method>"
        }
        let instance = ["multipart/related; type=\"application/dicom\""]
        let metadata = ["application/dicom+json", "multipart/related; type=\"application/dicom+xml\""]
        let pixels = ["multipart/related; type=\"application/octet-stream\""]
        let rendered = ["image/jpeg", "image/png"]
        var retrieve: [String] = []
        if self.retrieve != nil {
            retrieve = [
                "<resource path=\"metadata\">" + method("GET", "RetrieveMetadata", metadata) + "</resource>",
                "<resource path=\"rendered\">" + method("GET", "RetrieveRendered", rendered) + "</resource>",
                "<resource path=\"thumbnail\">" + method("GET", "RetrieveThumbnail", rendered) + "</resource>",
                "<resource path=\"pixeldata\">" + method("GET", "RetrievePixelData", pixels) + "</resource>",
            ]
        }
        let searchMethod = search != nil ? method("GET", "Search", metadata) : ""
        let frames = self.retrieve != nil
            ? "<resource path=\"frames/{frames}\">" + method("GET", "RetrieveFrames", pixels)
                + "<resource path=\"rendered\">" + method("GET", "RetrieveRenderedFrames", rendered) + "</resource></resource>"
            : ""
        let instanceResource = "<resource path=\"{SOPInstance}\">"
            + (self.retrieve != nil ? method("GET", "RetrieveInstance", instance) : "") + retrieve.joined() + frames + "</resource>"
        let seriesResource = "<resource path=\"{SeriesInstance}\">"
            + (self.retrieve != nil ? method("GET", "RetrieveSeries", instance) : "") + retrieve.joined()
            + "<resource path=\"instances\">" + searchMethod + instanceResource + "</resource></resource>"
        let studyResource = "<resource path=\"{StudyInstance}\">"
            + (self.retrieve != nil ? method("GET", "RetrieveStudy", instance) : "")
            + (store != nil ? method("POST", "StoreStudyInstances", metadata.prefix(1).map { $0 }) : "")
            + retrieve.joined()
            + "<resource path=\"series\">" + searchMethod + seriesResource + "</resource>"
            + "<resource path=\"instances\">" + searchMethod + "</resource></resource>"
        let studies = "<resource path=\"studies\">" + searchMethod
            + (store != nil ? method("POST", "StoreInstances", ["application/dicom+json"]) : "") + studyResource + "</resource>"
        let wadl = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            + "<application xmlns=\"http://wadl.dev.java.net/2009/02\">"
            + "<resources base=\"\(Self.xmlEscape(baseURI))\">" + studies
            + "<resource path=\"series\">" + searchMethod + "</resource>"
            + "<resource path=\"instances\">" + searchMethod + "</resource>"
            + "</resources></application>"
        var headers = DICOMwebMultipart.Headers()
        headers["Content-Type"] = "application/vnd.sun.wadl+xml"
        headers["Allow"] = "GET, POST, OPTIONS"
        return DICOMwebHTTPResponse(status: 200, headers: headers, body: .data(Data(wadl.utf8)))
    }

    // MARK: Negotiation and errors

    /// The media types of the `accept` Query Parameter.
    static func acceptQueryParameter(_ query: String) -> [DICOMwebAcceptRange] {
        query.split(separator: "&").compactMap { parameter -> [DICOMwebAcceptRange]? in
            let pair = parameter.split(separator: "=", maxSplits: 1)
            guard pair.count == 2, pair[0] == "accept", let value = String(pair[1]).removingPercentEncoding else { return nil }
            return DICOMwebAcceptRange.parse(value)
        }.flatMap { $0 }
    }

    private func negotiate(
        _ request: DICOMwebHTTPRequest, query: [(name: String, values: [String])] = [], accept: [DICOMwebAcceptRange]? = nil,
        supported: [DICOMwebMediaType], defaultType: DICOMwebMediaType?,
        defaultTransferSyntax: String? = TransferSyntax.explicitVRLittleEndian
    ) throws -> DICOMwebMediaType {
        let fromQuery = accept ?? query.filter { $0.name == "accept" }.flatMap { DICOMwebAcceptRange.parse($0.values.joined(separator: ",")) }
        let header = request.headers["Accept"].map(DICOMwebAcceptRange.parse)
        switch DICOMwebContentNegotiation.select(query: fromQuery, header: header, supported: supported,
                                                 defaultType: defaultType, defaultTransferSyntax: defaultTransferSyntax) {
        case .selected(let type): return type
        case .notAcceptable:
            throw DICOMwebHTTPError(406, "Acceptable media types: " + supported.map(\.description).joined(separator: ", "))
        case .badRequest(let message): throw DICOMwebHTTPError(400, message)
        }
    }

    /// A Status Report (PS3.18 8.6.3) in text/html, the default media type of
    /// the Text resource category.
    static func report(_ status: Int, _ message: String, allow: String? = nil) -> DICOMwebHTTPResponse {
        var headers = DICOMwebMultipart.Headers()
        headers["Content-Type"] = "text/html; charset=utf-8"
        if let allow { headers["Allow"] = allow }
        let html = "<!DOCTYPE html><html><head><title>\(status)</title></head><body><p>\(xmlEscape(message))</p></body></html>"
        return DICOMwebHTTPResponse(status: status, headers: headers, body: .data(Data(html.utf8)))
    }

    static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// An error answered with an HTTP status and a Status Report.
struct DICOMwebHTTPError: Error {
    let status: Int
    let message: String

    init(_ status: Int, _ message: String) {
        self.status = status
        self.message = message
    }
}
