import XCTest
@testable import DcmSwift

/// DICOMweb building blocks (PS3.18): media types and content negotiation,
/// multipart/related payloads, Search Query Parameters, and resources.
final class DcmSwiftWebTests: XCTestCase {
    // MARK: Media types (PS3.18 8.7)

    func testMediaTypeParsingAndFormatting() throws {
        let type = try XCTUnwrap(DICOMwebMediaType(
            "Multipart/Related; type=\"application/dicom\"; transfer-syntax=1.2.840.10008.1.2.4.50; boundary=**"))
        XCTAssertTrue(type.isMultipartRelated)
        XCTAssertEqual(type.relatedType, .dicom)
        XCTAssertEqual(type.transferSyntax, "1.2.840.10008.1.2.4.50")
        XCTAssertEqual(type.boundary, "**")
        XCTAssertEqual(type.description,
                       "multipart/related; type=\"application/dicom\"; transfer-syntax=1.2.840.10008.1.2.4.50; boundary=**")
        // Quoted and unquoted values are equivalent (PS3.18 8.7).
        XCTAssertEqual(DICOMwebMediaType("multipart/related; type=application/dicom+json"),
                       DICOMwebMediaType("multipart/related; type=\"Application/DICOM+JSON\""))
        XCTAssertEqual(DICOMwebMediaType.multipartRelated(.dicom.with("transfer-syntax", "*"), boundary: "b").description,
                       "multipart/related; type=\"application/dicom\"; transfer-syntax=*; boundary=b")
        XCTAssertNil(DICOMwebMediaType("application"))
        XCTAssertNil(DICOMwebMediaType("application/dicom; transfer-syntax"))
        XCTAssertNil(DICOMwebMediaType("application/dicom; type=\"unterminated"))
        XCTAssertEqual(DICOMwebMediaType.compressedBulkData(for: "1.2.840.10008.1.2.4.201")?.essence, "image/jphc")
        XCTAssertNil(DICOMwebMediaType.compressedBulkData(for: TransferSyntax.explicitVRLittleEndian))
    }

    func testAcceptListKeepsQuotedCommasAndWeights() {
        let ranges = DICOMwebAcceptRange.parse(
            "multipart/related; type=\"application/dicom\";transfer-syntax=1.2.840.10008.1.2.4.50;boundary=**, "
            + "multipart/related; type=\"application/dicom\";transfer-syntax=1.2.840.10008.1.2.4.57;q=0.5;boundary=**, "
            + "bad, image/*;q=2")
        XCTAssertEqual(ranges.count, 2, "malformed members are ignored")
        XCTAssertEqual(ranges[0].quality, 1)
        XCTAssertEqual(ranges[1].quality, 0.5)
        XCTAssertEqual(ranges[1].range.transferSyntax, "1.2.840.10008.1.2.4.57")
        XCTAssertNil(ranges[1].range[parameter: "q"])
    }

    /// PS3.18 Table 8.7.8-1: the qvalue of each representation comes from
    /// the most specific matching range.
    func testNegotiationFollowsTable8_7_8_1() throws {
        let header = DICOMwebAcceptRange.parse(
            "text/*; q=0.5, text/html; q=0.4, text/html; level=1, text/html; level=2; q=0.7, image/png, */*; q=0.4")
        let supported = try ["text/html; level=1", "text/html; level=2", "text/plain", "text/rtf", "text/html",
                             "text/x-latex"].map { try XCTUnwrap(DICOMwebMediaType($0)) }
        XCTAssertEqual(DICOMwebContentNegotiation.select(header: header, supported: supported, defaultType: .html,
                                                         defaultTransferSyntax: nil),
                       .selected(supported[0]))
        // Without text/html; level=1, level=2 wins with 0.7.
        XCTAssertEqual(DICOMwebContentNegotiation.select(header: header, supported: Array(supported.dropFirst()),
                                                         defaultType: .html, defaultTransferSyntax: nil),
                       .selected(supported[1]))
        // text/plain gets 0.5 from text/*, so it is selected rather than the
        // text/html default that */* stands for. (The table gives text/x-latex
        // 0.4 from */*, although text/* matches it more specifically.)
        XCTAssertEqual(DICOMwebContentNegotiation.select(header: header, supported: [supported[2]],
                                                         defaultType: .html, defaultTransferSyntax: nil),
                       .selected(supported[2]))
    }

    func testNegotiationOfInstanceRepresentations() {
        let stored = "1.2.840.10008.1.2.4.50"
        let supported = [DICOMwebMediaType.multipartRelated(.dicom.with("transfer-syntax", stored)),
                         .multipartRelated(.dicom.with("transfer-syntax", TransferSyntax.explicitVRLittleEndian))]
        func select(_ accept: String?) -> DICOMwebContentNegotiation.Outcome {
            DICOMwebContentNegotiation.select(header: accept.map(DICOMwebAcceptRange.parse), supported: supported,
                                              defaultType: supported[1])
        }
        // No transfer-syntax parameter selects the default (PS3.18 8.7.8.2).
        XCTAssertEqual(select("multipart/related; type=\"application/dicom\""), .selected(supported[1]))
        // The wildcard lets the server answer as stored.
        XCTAssertEqual(select("multipart/related; type=\"application/dicom\"; transfer-syntax=*"), .selected(supported[0]))
        XCTAssertEqual(select("multipart/related; type=\"application/dicom\"; transfer-syntax=\(stored)"),
                       .selected(supported[0]))
        XCTAssertEqual(select("*/*"), .selected(supported[1]))
        XCTAssertEqual(select("multipart/related; type=\"application/dicom\"; transfer-syntax=1.2.840.10008.1.2.4.90"),
                       .notAcceptable)
        XCTAssertEqual(select(nil), .notAcceptable, "a request without Accept gets 406 (PS3.18 8.7.5)")
        guard case .badRequest = select("application/dicom, text/html") else {
            return XCTFail("DICOM and rendered media types together are a bad request")
        }
        // application/json is neither DICOM nor rendered: it is ignored, as
        // dicomweb-client sends it after application/dicom+json.
        XCTAssertEqual(DICOMwebContentNegotiation.select(
            header: DICOMwebAcceptRange.parse("application/dicom+json, application/json"),
            supported: [.dicomJSON], defaultType: .dicomJSON), .selected(.dicomJSON))
        // The accept Query Parameter takes precedence over the header.
        XCTAssertEqual(DICOMwebContentNegotiation.select(
            query: DICOMwebAcceptRange.parse("multipart/related; type=\"application/dicom\"; transfer-syntax=\(stored)"),
            header: DICOMwebAcceptRange.parse("*/*"), supported: supported, defaultType: supported[1]),
                       .selected(supported[0]))
    }

    // MARK: Multipart (PS3.18 8.6.1.2)

    func testMultipartRoundTripAndIncrementalParsing() throws {
        var first = DICOMwebMultipart.Headers()
        first["Content-Type"] = "application/dicom"
        first["Content-Location"] = "/studies/1.2/series/1.3/instances/1.4"
        var second = DICOMwebMultipart.Headers()
        second["Content-Type"] = "application/octet-stream"
        // Bodies that contain the boundary without the CRLF and dashes that
        // make a delimiter, and CRLF sequences.
        let bodies = [Data("--abc\r\n-abc\r\n--ab".utf8), Data((0..<2000).map { UInt8($0 % 251) })]
        let payload = DICOMwebMultipart.Writer.encode([(first, bodies[0]), (second, bodies[1])], boundary: "abc")
        XCTAssertTrue(payload.starts(with: Data("--abc\r\n".utf8)))
        XCTAssertEqual(payload.suffix(11), Data("\r\n--abc--\r\n".utf8))

        let parts = try DICOMwebMultipart.parse(payload, boundary: "abc")
        XCTAssertEqual(parts.map(\.body), bodies)
        XCTAssertEqual(parts[0].headers.contentLocation, "/studies/1.2/series/1.3/instances/1.4")
        XCTAssertEqual(parts[1].headers["content-length"], "2000")
        XCTAssertEqual(parts[0].headers.contentType, .dicom)

        // Byte by byte, every split of a delimiter is handled.
        var parser = try DICOMwebMultipart.Parser(boundary: "abc")
        var bodiesSeen: [Data] = [], current = Data()
        for byte in payload {
            for event in try parser.feed([byte]) {
                switch event {
                case .partStart: current = Data()
                case .bodyChunk(let chunk): current += chunk
                case .partEnd: bodiesSeen.append(current)
                }
            }
        }
        try parser.finish()
        XCTAssertEqual(bodiesSeen, bodies)
    }

    func testMultipartPreambleEpilogueAndErrors() throws {
        let payload = Data("This is a preamble.\r\n--b  \r\nContent-Type: text/plain\r\n\r\nhello\r\n--b--\r\nepilogue".utf8)
        let parts = try DICOMwebMultipart.parse(payload, boundary: "b")
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].body, Data("hello".utf8))
        // A part without header fields.
        XCTAssertEqual(try DICOMwebMultipart.parse(Data("--b\r\n\r\nx\r\n--b--".utf8), boundary: "b").first?.body,
                       Data("x".utf8))
        XCTAssertThrowsError(try DICOMwebMultipart.parse(Data("--b\r\nContent-Type: a/b\r\n\r\ncut".utf8), boundary: "b"))
        XCTAssertThrowsError(try DICOMwebMultipart.parse(Data("--b junk\r\n\r\nx\r\n--b--".utf8), boundary: "b"))
        XCTAssertThrowsError(try DICOMwebMultipart.Parser(boundary: ""))
        // An empty multipart payload is only a close delimiter.
        XCTAssertEqual(try DICOMwebMultipart.parse(DICOMwebMultipart.Writer(boundary: "b").close(), boundary: "b"), [])
    }

    // MARK: Search (PS3.18 8.3.4, 10.6)

    /// The example URIs of PS3.18 10.6.1.2.1.
    func testSearchQueryParsesTheStandardExamples() throws {
        var query = try DICOMwebSearchQuery(query: "00100010=SMITH*&00101002.00100020=11235813&limit=25")
        XCTAssertEqual(query.matches.map(\.attribute.description), ["PatientName", "OtherPatientIDsSequence.PatientID"])
        XCTAssertEqual(query.limit, 25)

        query = try DICOMwebSearchQuery(query: "PatientID=11235813&includefield=00081048,00081049,00081060")
        XCTAssertEqual(query.includeFields.map(\.description),
                       ["PhysiciansOfRecord", "PhysiciansOfRecordIdentificationSequence", "NameOfPhysiciansReadingStudy"])
        let repeated = try DICOMwebSearchQuery(
            query: "PatientID=11235813&includefield=00081048&includefield=00081049&includefield=00081060")
        XCTAssertEqual(repeated.includeFields, query.includeFields)

        query = try DICOMwebSearchQuery(query: "PatientID=11235813&StudyDate=20130509-20130510")
        XCTAssertEqual(query.matches.last?.values, ["20130509-20130510"])

        query = try DICOMwebSearchQuery(query: "StudyInstanceUID=1.2.392.200036.9116.2.2.2.2162893313.1029997326.94587,"
                                        + "1.2.392.200036.9116.2.2.2.2162893313.1029997326.94583")
        XCTAssertEqual(query.matches.first?.values.count, 2)
        let identifier = query.identifier(level: .study)
        XCTAssertEqual(identifier.string(forTag: "StudyInstanceUID"),
                       "1.2.392.200036.9116.2.2.2.2162893313.1029997326.94587\\1.2.392.200036.9116.2.2.2.2162893313.1029997326.94583")
        XCTAssertEqual(identifier.string(forTag: "QueryRetrieveLevel"), "STUDY")
        XCTAssertNotNil(identifier.element(forTagName: "NumberOfStudyRelatedInstances"), "required return keys")
        XCTAssertNil(identifier.element(forTagName: "RetrieveURL"), "Retrieve URL is filled by the origin server")

        query = try DICOMwebSearchQuery(query: "includefield=all&fuzzymatching=true&offset=10&accept=application%2Fdicom%2Bjson")
        XCTAssertTrue(query.includeAllFields)
        XCTAssertTrue(query.fuzzyMatching)
        XCTAssertEqual(query.offset, 10)
        XCTAssertEqual(query.otherParameters.first?.values, ["application/dicom+json"])
    }

    func testSearchQueryRejectsInvalidValuesAndRoundTrips() throws {
        for bad in ["limit=-1", "limit=x", "fuzzymatching=yes", "NotAKeyword=1", "PatientID=1&PatientID=2",
                    "PatientName.PatientID=1", "includefield=Unknown"] {
            XCTAssertThrowsError(try DICOMwebSearchQuery(query: bad), bad)
        }
        var query = DICOMwebSearchQuery()
        query.match("PatientName", "O'BRIEN^J*")
        query.match("AccessionNumber", "A&B=C,D#1")
        query.includeFields = [DICOMwebAttributePath(["StudyDescription"])]
        query.limit = 5
        XCTAssertEqual(query.queryString,
                       "PatientName=O'BRIEN%5EJ*&AccessionNumber=A%26B%3DC%2CD%231&includefield=StudyDescription&limit=5")
        XCTAssertEqual(try DICOMwebSearchQuery(query: query.queryString), query)
    }

    func testSequenceMatchingKeyBuildsAnItem() throws {
        let query = try DICOMwebSearchQuery(query: "OtherPatientIDsSequence.PatientID=11235813")
        let identifier = query.identifier(level: .study)
        let sequence = try XCTUnwrap(identifier.sequence(forTagName: "OtherPatientIDsSequence"))
        XCTAssertEqual(sequence.items.count, 1)
        XCTAssertEqual(sequence.items.first?.elements.first?.value as? String, "11235813")
    }

    // MARK: Resources (PS3.18 10.4.1, 10.5.1, 10.6.1)

    func testResourcesParseAndFormat() throws {
        let cases: [(String, DICOMwebResource.Kind, DICOMwebSearchLevel?)] = [
            ("/studies", .search, .study), ("/series", .search, .series), ("/instances", .search, .instance),
            ("/studies/1.2", .instances, nil), ("/studies/1.2/series", .search, .series),
            ("/studies/1.2/instances", .search, .instance), ("/studies/1.2/series/1.3", .instances, nil),
            ("/studies/1.2/series/1.3/instances", .search, .instance),
            ("/studies/1.2/series/1.3/instances/1.4", .instances, nil),
            ("/studies/1.2/metadata", .metadata, nil), ("/studies/1.2/series/1.3/rendered", .rendered, nil),
            ("/studies/1.2/series/1.3/instances/1.4/thumbnail", .thumbnail, nil),
            ("/studies/1.2/series/1.3/instances/1.4/frames/1,3,5", .frames, nil),
            ("/studies/1.2/series/1.3/instances/1.4/frames/2/rendered", .rendered, nil),
            ("/studies/1.2/bulkdata", .bulkdata, nil), ("/studies/1.2/series/1.3/instances/1.4/pixeldata", .pixeldata, nil),
        ]
        for (path, kind, level) in cases {
            let resource = try XCTUnwrap(DICOMwebResource(pathComponents: path.split(separator: "/").map(String.init)), path)
            XCTAssertEqual(resource.kind, kind, path)
            XCTAssertEqual(resource.searchLevel, level, path)
            XCTAssertEqual(resource.path, path)
        }
        XCTAssertEqual(DICOMwebResource(pathComponents: ["studies", "1.2", "series", "1.3", "instances", "1.4",
                                                         "frames", "1,3,5"])?.frames, [1, 3, 5])
        for invalid in ["/patients", "/studies/not-a-uid", "/studies/1.2/instances/1.4", "/series/1.3",
                        "/studies/1.2/series/1.3/instances/1.4/frames/0", "/studies/1.2/metadata/extra",
                        "/studies/1.2/frames/1"] {
            XCTAssertNil(DICOMwebResource(pathComponents: invalid.split(separator: "/").map(String.init)), invalid)
        }
        XCTAssertEqual(DICOMwebResource.search(.instance, study: "1.2", series: "1.3").path, "/studies/1.2/series/1.3/instances")
        XCTAssertEqual(DICOMwebResource.frames([2], study: "1.2", series: "1.3", instance: "1.4", rendered: true).path,
                       "/studies/1.2/series/1.3/instances/1.4/frames/2/rendered")
    }
}
