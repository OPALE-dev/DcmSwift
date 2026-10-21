import Foundation

/// Worklist Service, PS3.18 chapter 11, sharing the DIMSE UPS state machine.
public struct DICOMUPSRESTService: Sendable {
    public let steps: DICOMUnifiedProcedureStepService
    public init(steps: DICOMUnifiedProcedureStepService) { self.steps = steps }

    func respond(_ request: DICOMwebHTTPRequest, path: [String], baseURI: String,
                 configuration: DICOMwebServerConfiguration) async -> DICOMwebHTTPResponse {
        do {
            let query = try Self.parameters(request.query)
            if request.method == "OPTIONS" {
                return .init(status: 200, headers: .init([("Allow", "GET, POST, PUT, DELETE, OPTIONS")]))
            }
            let uid = path.count > 1 ? path[1] : nil
            if let uid, !Self.validUID(uid) { throw DICOMwebHTTPError(400, "invalid Workitem UID") }
            let selected = try representation(request, query: query)
            if path.count == 1 && request.method == "POST" {
                var object = try await payload(request, maximum: configuration.maximumRequestLength)
                let payloadUID = DICOMUnifiedProcedureStepService.value(object, "00080018")
                if let queryUID = query["workitem"], let payloadUID, queryUID != payloadUID {
                    throw DICOMwebHTTPError(400, "conflicting Workitem UIDs")
                }
                guard let requestedUID = query["workitem"] ?? payloadUID, Self.validUID(requestedUID) else {
                    throw DICOMwebHTTPError(400, "a valid Workitem UID is required")
                }
                object.removeValue(forKey: "00080018")
                let result = try await steps.create(requestedUID, object)
                var response = status(result, success: 201, operation: "create")
                if response.status == 201, let uid = result.sopInstanceUID {
                    response.headers["Location"] = baseURI + "/workitems/" + uid
                }
                return response
            }
            if path.count == 1 && request.method == "GET" {
                return try await search(request, selected, baseURI: baseURI, configuration: configuration)
            }
            guard let uid else { return Self.methodNotAllowed("GET, POST, OPTIONS") }
            if path.count == 2 && request.method == "GET" {
                let result = try await steps.get(uid)
                guard result.status.category != .failure, let data = result.dataSet else {
                    return status(result, operation: "get")
                }
                return try encode([DICOMJSON.object(data)], selected, location: baseURI + "/workitems/" + uid)
            }
            if path.count == 2 && request.method == "POST" {
                var changes = try await payload(request, maximum: configuration.maximumRequestLength)
                if let token = query["transactionuid"] ?? query["transactionUID"] ?? query["TransactionUID"] ?? query["TransactionUid"] {
                    if let supplied = DICOMUnifiedProcedureStepService.value(changes, "00081195"), token != supplied {
                        throw DICOMwebHTTPError(400, "conflicting Transaction UIDs")
                    }
                    changes["00081195"] = DICOMUnifiedProcedureStepService.attribute("UI", token)
                }
                return status(try await steps.set(uid, changes), operation: "update")
            }
            if path.count == 3 && path[2] == "state" && request.method == "PUT" {
                let object = try await payload(request, maximum: configuration.maximumRequestLength)
                let requester = query["requester"] ?? "HTTP"
                guard Self.validAE(requester) else { throw DICOMwebHTTPError(400, "invalid requesting AE") }
                return status(try await steps.changeState(uid, object, requestingAE: requester), operation: "state")
            }
            if path.count == 3 && path[2] == "cancelrequest" && request.method == "POST" {
                let object = try await payload(request, maximum: configuration.maximumRequestLength, allowEmpty: true)
                let requester = query["requester"] ?? "HTTP"
                guard Self.validAE(requester) else { throw DICOMwebHTTPError(400, "invalid requesting AE") }
                return status(try await steps.cancel(uid, object, requestingAE: requester), success: 202, operation: "cancel")
            }
            if path.count >= 4 && path[2] == "subscribers" {
                for try await chunk in request.body {
                    if !chunk.isEmpty { throw DICOMwebHTTPError(400, "subscription requests have no payload") }
                }
                let ae = path[3]
                guard Self.validAE(ae) else { throw DICOMwebHTTPError(400, "invalid subscriber AE") }
                let global = [DICOMSOPClass.upsGlobalSubscription, DICOMSOPClass.upsFilteredGlobalSubscription].contains(uid)
                let target = uid == DICOMSOPClass.upsFilteredGlobalSubscription ? DICOMSOPClass.upsGlobalSubscription : uid
                var object: [String: Any] = ["00741234": DICOMUnifiedProcedureStepService.attribute("AE", ae)]
                let action: UInt16
                if path.count == 5 && path[4] == "suspend" && request.method == "POST" && global { action = 5 }
                else if path.count == 4 && request.method == "DELETE" { action = 4 }
                else if path.count == 4 && request.method == "POST" {
                    action = 3
                    guard ["true", "false"].contains(query["deletionlock"] ?? "false") else {
                        throw DICOMwebHTTPError(400, "deletionlock must be true or false")
                    }
                    object["00741230"] = DICOMUnifiedProcedureStepService.attribute("CS", query["deletionlock"] == "true" ? "TRUE" : "FALSE")
                    if uid == DICOMSOPClass.upsFilteredGlobalSubscription {
                        guard let filter = query["filter"], !filter.isEmpty else { throw DICOMwebHTTPError(400, "filter is required") }
                        let filterQuery = filter.split(separator: ",").map(String.init).joined(separator: "&")
                        object.merge(try matchingKeys(DICOMwebSearchQuery(query: filterQuery))) { _, value in value }
                    }
                    guard await steps.eventHub.isConnected(ae) else {
                        throw DICOMwebHTTPError(404, "open the subscriber notification connection first")
                    }
                } else { return Self.methodNotAllowed("POST, DELETE, OPTIONS") }
                if action != 3 {
                    let id = ae + "|" + (global ? target : uid)
                    let existing = try await steps.index.document(id, in: .unifiedProcedureStepSubscriptions)
                    let filteredExisting = global ? try await steps.index.document(ae + "|" + DICOMSOPClass.upsFilteredGlobalSubscription,
                                                                                   in: .unifiedProcedureStepSubscriptions) : nil
                    var found = existing != nil || filteredExisting != nil
                    if action == 4 && global && !found {
                        let all = try await steps.index.documents(in: .unifiedProcedureStepSubscriptions, matching: DICOMQuery(conditions: []))
                        found = all.contains { $0.metadata["ae"] == ae }
                    }
                    guard found else { throw DICOMwebHTTPError(404, "subscription not found") }
                }
                var response = status(try await steps.subscription(action == 3 ? uid : target, action: action, object: object),
                                      success: action == 3 ? 201 : 200, operation: "subscribe")
                if response.status == 201 {
                    let ws = baseURI.replacingOccurrences(of: "https://", with: "wss://").replacingOccurrences(of: "http://", with: "ws://")
                    let encodedAE = ae.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ae
                    response.headers["Content-Location"] = ws + "/subscribers/" + encodedAE
                }
                return response
            }
            return Self.methodNotAllowed("GET, POST, PUT, DELETE, OPTIONS")
        } catch let error as DICOMwebHTTPError {
            return DICOMwebOriginServer.report(error.status, error.message)
        } catch is DICOMJSONError {
            return DICOMwebOriginServer.report(400, "invalid DICOM JSON dataset")
        } catch is DICOMServiceError {
            return DICOMwebOriginServer.report(400, "invalid Workitem matching keys")
        } catch is DICOMwebSearchQuery.ParseError {
            return DICOMwebOriginServer.report(400, "invalid search parameters")
        } catch {
            return DICOMwebOriginServer.report(500, String(describing: error))
        }
    }

    private func status(_ result: DICOMNormalizedResponse, success: Int = 200, operation: String) -> DICOMwebHTTPResponse {
        let code = result.status.code
        var status = success
        if result.status.category == .failure {
            switch code {
            case 0xC307: status = 404
            case 0x0111: status = 409
            case 0xC308: status = 404
            case 0xC315: status = 403
            case 0xC300, 0xC301: status = operation == "update" || operation == "state" ? 400 : 409
            case 0xC302, 0xC303, 0xC304, 0xC310, 0xC311, 0xC312, 0xC313: status = 409
            default: status = 400
            }
        }
        var response = status >= 400 ? DICOMwebOriginServer.report(status, result.errorComment ?? "UPS status \(String(format: "%04X", code))")
            : DICOMwebHTTPResponse(status: status)
        let warning: String?
        switch code {
        case 0xB304: warning = "The UPS is already in the requested state of CANCELED."
        case 0xB306: warning = "The UPS is already in the requested state of COMPLETED."
        case 0xC301: warning = "The Transaction UID is incorrect."
        case 0xC300, 0xC302, 0xC303, 0xC304, 0xC310: warning = "The submitted request is inconsistent with the state of the UPS Instance."
        default: warning = nil
        }
        if let warning { response.headers["Warning"] = "299 DcmSwift \"\(warning)\"" }
        return response
    }

    private func representation(_ request: DICOMwebHTTPRequest, query: [String: String]) throws -> DICOMwebMediaType {
        let selected = DICOMwebContentNegotiation.select(
            query: query["accept"].map(DICOMwebAcceptRange.parse) ?? [],
            header: DICOMwebAcceptRange.parse(request.headers["Accept"] ?? "*/*"),
            supported: [.dicomJSON, .multipartRelated(.dicomXML)], defaultType: .dicomJSON)
        switch selected {
        case .selected(let type): return type
        case .notAcceptable: throw DICOMwebHTTPError(406, "Accept application/dicom+json or multipart Native DICOM XML")
        case .badRequest(let message): throw DICOMwebHTTPError(400, message)
        }
    }

    private func payload(_ request: DICOMwebHTTPRequest, maximum: Int, allowEmpty: Bool = false) async throws -> [String: Any] {
        var bytes = Data()
        for try await chunk in request.body {
            guard chunk.count <= maximum - bytes.count else { throw DICOMwebHTTPError(413, "Workitem payload too large") }
            bytes += chunk
        }
        if bytes.isEmpty && allowEmpty { return [:] }
        guard let type = request.headers.contentType else { throw DICOMwebHTTPError(415, "Content-Type is required") }
        do {
            let dataset: DataSet
            if type.essence == DICOMwebMediaType.dicomJSON.essence {
                guard let objects = try JSONSerialization.jsonObject(with: bytes) as? [[String: Any]], objects.count == 1 else {
                    throw DICOMwebHTTPError(400, "expected one DICOM JSON dataset in an array")
                }
                dataset = try DICOMJSON.dataSet(objects[0])
            } else if type.isMultipartRelated, type.relatedType?.essence == DICOMwebMediaType.dicomXML.essence,
                      let boundary = type.boundary {
                var parser = try DICOMwebMultipart.Parser(boundary: boundary)
                let events = try parser.feed(bytes)
                try parser.finish()
                var bodies: [Data] = []
                for event in events {
                    switch event {
                    case .partStart(let headers):
                        guard headers.contentType?.essence == DICOMwebMediaType.dicomXML.essence else {
                            throw DICOMwebHTTPError(415, "expected a Native DICOM XML part")
                        }
                        bodies.append(Data())
                    case .bodyChunk(let data): bodies[bodies.count - 1] += data
                    case .partEnd: break
                    }
                }
                guard bodies.count == 1 else { throw DICOMwebHTTPError(400, "expected one XML part") }
                dataset = try DICOMXML.decode(bodies[0])
            } else { throw DICOMwebHTTPError(415, "unsupported Workitem media type") }
            let object = try DICOMJSON.object(dataset, options: .init(numbersAsStrings: true))
            func hasBulkURI(_ attributes: [String: Any]) -> Bool {
                attributes.values.contains { raw in
                    guard let attribute = raw as? [String: Any] else { return false }
                    return attribute["BulkDataURI"] != nil ||
                        (attribute["Value"] as? [[String: Any]] ?? []).contains(where: hasBulkURI)
                }
            }
            if hasBulkURI(object) { throw DICOMwebHTTPError(400, "Worklist transactions do not support Bulk Data references") }
            return object
        } catch let error as DICOMwebHTTPError { throw error }
        catch { throw DICOMwebHTTPError(400, "invalid Workitem representation: \(error)") }
    }

    private func encode(_ objects: [[String: Any]], _ type: DICOMwebMediaType, location: String) throws -> DICOMwebHTTPResponse {
        var headers = DICOMwebMultipart.Headers([("Content-Location", location), ("Cache-Control", "no-store")])
        let bytes: Data
        if type.essence == DICOMwebMediaType.dicomJSON.essence {
            bytes = try JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys])
            headers["Content-Type"] = DICOMwebMediaType.dicomJSON.description
        } else {
            let boundary = DICOMwebMultipart.makeBoundary()
            bytes = try DICOMwebMultipart.Writer.encode(objects.map {
                (.init([("Content-Type", DICOMwebMediaType.dicomXML.description)]), try DICOMXML.encode(DICOMJSON.dataSet($0)))
            }, boundary: boundary)
            headers["Content-Type"] = DICOMwebMediaType.multipartRelated(.dicomXML, boundary: boundary).description
        }
        return .init(status: 200, headers: headers, body: .data(bytes))
    }

    private static let returnTags = ["00080005", "00080016", "00080018", "00741200", "00741204", "00741202", "00741210",
        "00404025", "00404026", "00404027", "00404034", "00404005", "00404018", "00400400", "00404041", "00404021",
        "0020000D", "00100010", "00100020", "00100021", "00100024", "00101002", "00100030", "00100040", "00380010",
        "00380014", "00081080", "00081084", "0040A370", "00741000", "00741002", "00102000", "001021C0", "00380050"]

    private func matchingKeys(_ query: DICOMwebSearchQuery) throws -> [String: Any] {
        if query.fuzzyMatching || query.multipleValueMatching || query.emptyValueMatching {
            throw DICOMwebHTTPError(400, "extended matching is not supported for Workitems")
        }
        var object = try DICOMJSON.object(query.identifier(level: .instance, returnKeywords: []), options: .init(numbersAsStrings: true))
        object.removeValue(forKey: "00080052")
        return object
    }

    private func search(_ request: DICOMwebHTTPRequest, _ type: DICOMwebMediaType, baseURI: String,
                        configuration: DICOMwebServerConfiguration) async throws -> DICOMwebHTTPResponse {
        let query = try DICOMwebSearchQuery(query: request.query)
        var keys = try matchingKeys(query)
        let all = try await steps.index.documents(in: .unifiedProcedureSteps, matching: DICOMQuery(conditions: []))
        var tags = Set(Self.returnTags)
        if query.includeAllFields { for item in all { tags.formUnion(item.attributes.keys) } }
        for field in query.includeFields {
            if let tag = DicomSpec.shared.dataTag(forName: field.keywords[0]) { tags.insert(tag.code.uppercased()) }
        }
        tags.remove("00081195")
        for tag in tags where keys[tag] == nil {
            if let vr = DicomSpec.shared.vrForTag(withCode: tag) { keys[tag] = ["vr": String(describing: vr)] }
        }
        let matches = try await steps.matches(DICOMJSON.dataSet(keys))
        let limit = min(query.limit ?? configuration.maximumResults, configuration.maximumResults)
        let result = try matches.dropFirst(query.offset).prefix(limit).map { try DICOMJSON.object($0) }
        var response = try encode(result, type, location: baseURI + "/workitems")
        if matches.count > query.offset + result.count {
            response.headers["Warning"] = "299 DcmSwift \"There are additional results.\""
        }
        return response
    }

    static func parameters(_ query: String) throws -> [String: String] {
        var result: [String: String] = [:]
        for field in query.split(separator: "&") {
            let pair = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = String(pair[0]).removingPercentEncoding,
                  let value = (pair.count == 2 ? String(pair[1]) : "").removingPercentEncoding else {
                throw DICOMwebHTTPError(400, "invalid percent encoding")
            }
            if result[name] != nil && !["includefield"].contains(name) { throw DICOMwebHTTPError(400, "duplicate parameter \(name)") }
            result[name] = value
        }
        return result
    }
    static func validUID(_ uid: String) -> Bool {
        !uid.isEmpty && uid.utf8.count <= 64 && uid.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } && ($0.count == 1 || $0.first != "0")
        }
    }
    static func validAE(_ ae: String) -> Bool {
        !ae.trimmingCharacters(in: .whitespaces).isEmpty && ae.utf8.count <= 16 && ae.allSatisfy { $0.isASCII && $0.asciiValue! >= 32 && $0.asciiValue! < 127 && $0 != "\\" && $0 != "/" }
    }
    private static func methodNotAllowed(_ allow: String) -> DICOMwebHTTPResponse {
        DICOMwebOriginServer.report(405, "method not allowed", allow: allow)
    }
}
