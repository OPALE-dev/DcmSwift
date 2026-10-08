import XCTest
@testable import DcmSwift

/// The DICOMweb origin server (PS3.18 10) over a directory archive, without
/// HTTP: Store, Search, Retrieve, rendering, and capabilities.
final class DcmSwiftWebServerTests: XCTestCase {
    static let study = "1.2.826.0.1.3680043.10.999.1"
    static let mrSeries = "1.2.826.0.1.3680043.10.999.1.1"
    static let ctSeries = "1.2.826.0.1.3680043.10.999.1.2"
    static let mrInstance = "1.2.826.0.1.3680043.10.999.1.1.1"
    static let ctInstance = "1.2.826.0.1.3680043.10.999.1.2.1"
    static let mrPixels: [UInt16] = [0, 1000, 2000, 4095]
    static let ctFrames: [[UInt16]] = [[0, 100, 200, 300, 400, 4095], [4095, 0, 1, 2, 3, 4]]
    static let origin = "http://localhost:8042"

    private var directory: URL!
    private var server: DICOMwebOriginServer!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-web-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let services = DICOMDirectoryArchiveServices(archive: DICOMDirectoryArchive(directory: directory))
        server = DICOMwebOriginServer(configuration: .init(basePath: "/dicomweb", maximumResults: 10),
                                      search: services, retrieve: services, store: services)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Fixtures

    private static func words(_ values: [UInt16]) -> Data {
        values.reduce(into: Data()) { $0.append(contentsOf: [UInt8($1 & 0xFF), UInt8($1 >> 8)]) }
    }

    private static func image(sopClass: String, instance: String, series: String, seriesNumber: String,
                              modality: String, rows: Int, columns: Int, frames: Int?) -> DataSet {
        let dataSet = DataSet()
        for (keyword, value) in [("SOPClassUID", sopClass), ("SOPInstanceUID", instance), ("StudyInstanceUID", study),
                                 ("SeriesInstanceUID", series), ("PatientID", "WEB-1"), ("PatientName", "DOE^JANE"),
                                 ("StudyDate", "20261008"), ("Modality", modality), ("SeriesNumber", seriesNumber),
                                 ("InstanceNumber", "1"), ("AccessionNumber", "A1"), ("StudyID", "S1")] {
            _ = dataSet.set(value: value, forTagName: keyword)
        }
        _ = dataSet.set(value: UInt16(rows), forTagName: "Rows")
        _ = dataSet.set(value: UInt16(columns), forTagName: "Columns")
        _ = dataSet.set(value: UInt16(1), forTagName: "SamplesPerPixel")
        _ = dataSet.set(value: "MONOCHROME2", forTagName: "PhotometricInterpretation")
        _ = dataSet.set(value: UInt16(16), forTagName: "BitsAllocated")
        _ = dataSet.set(value: UInt16(12), forTagName: "BitsStored")
        _ = dataSet.set(value: UInt16(11), forTagName: "HighBit")
        _ = dataSet.set(value: UInt16(0), forTagName: "PixelRepresentation")
        if let frames { _ = dataSet.set(value: String(frames), forTagName: "NumberOfFrames") }
        return dataSet
    }

    /// A Part 10 MR image, native, Explicit VR Little Endian.
    static func mrPart10() throws -> Data {
        let dataSet = image(sopClass: "1.2.840.10008.5.1.4.1.1.4", instance: mrInstance, series: mrSeries,
                            seriesNumber: "1", modality: "MR", rows: 2, columns: 2, frames: nil)
        let pixels = DataElement(withTagName: "PixelData", dataset: dataSet)!
        pixels.vr = .OW
        XCTAssertTrue(pixels.setValue(words(mrPixels)))
        dataSet.add(element: pixels)
        return DICOMPart10Header.encodeMetaInformation(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.4", sopInstanceUID: mrInstance,
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian, sourceAETitle: nil)
            + (try DICOMDataSetCoding.encode(dataSet, transferSyntax: TransferSyntax.explicitVRLittleEndian))
    }

    /// The RLE frames of the CT image.
    static func ctEncodedFrames() throws -> [Data] {
        let dataSet = image(sopClass: "1.2.840.10008.5.1.4.1.1.2", instance: ctInstance, series: ctSeries,
                            seriesNumber: "2", modality: "CT", rows: 2, columns: 3, frames: 1)
        let pixels = DataElement(withTagName: "PixelData", dataset: dataSet)!
        pixels.vr = .OW
        _ = pixels.setValue(Data(count: 12))
        dataSet.add(element: pixels)
        let layout = try DICOMPixelDescription(dataset: dataSet)
        return try ctFrames.map { try DICOMRLECodec().encode(words($0), description: layout) }
    }

    /// A Part 10 CT image with two RLE Lossless frames.
    static func ctPart10() throws -> Data {
        let dataSet = image(sopClass: "1.2.840.10008.5.1.4.1.1.2", instance: ctInstance, series: ctSeries,
                            seriesNumber: "2", modality: "CT", rows: 2, columns: 3, frames: 2)
        dataSet.transferSyntax = TransferSyntax(DICOMRLECodec.transferSyntaxUID)
        let encoded = try ctEncodedFrames()
        let sequence = PixelSequence(withTag: DataTag(withGroup: "7fe0", element: "0010"))
        sequence.vr = .OB
        sequence.length = -1
        let table = [UInt32(0), UInt32(8 + encoded[0].count)].reduce(into: Data()) { data, offset in
            data.append(contentsOf: (0..<4).map { UInt8((offset >> (8 * $0)) & 0xFF) })
        }
        for value in [table] + encoded {
            let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
            item.data = value
            item.length = value.count
            sequence.items.append(item)
        }
        dataSet.add(element: sequence)
        return DICOMPart10Header.encodeMetaInformation(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: ctInstance,
            transferSyntaxUID: DICOMRLECodec.transferSyntaxUID, sourceAETitle: nil)
            + (try DICOMDataSetCoding.encode(dataSet, transferSyntax: DICOMRLECodec.transferSyntaxUID))
    }

    /// A response with its payload collected.
    struct Response {
        let status: Int
        let headers: DICOMwebMultipart.Headers
        let body: Data
    }

    private func request(_ method: String, _ target: String, accept: String? = nil,
                         contentType: String? = nil, body: Data = Data()) async throws -> Response {
        var headers = DICOMwebMultipart.Headers()
        if let accept { headers["Accept"] = accept }
        if let contentType { headers["Content-Type"] = contentType }
        let response = await server.respond(
            to: DICOMwebHTTPRequest(method: method, target: target, headers: headers, body: body), origin: Self.origin)
        return Response(status: response.status, headers: response.headers, body: try await response.collectBody())
    }

    private func expect(_ status: Int, _ method: String, _ target: String, accept: String? = nil,
                        _ message: String = "", file: StaticString = #filePath, line: UInt = #line) async throws {
        let response = try await request(method, target, accept: accept)
        XCTAssertEqual(response.status, status, message, file: file, line: line)
    }

    private func storeFixtures() async throws {
        var part = DICOMwebMultipart.Headers()
        part["Content-Type"] = "application/dicom"
        let payload = DICOMwebMultipart.Writer.encode([(part, try Self.mrPart10()), (part, try Self.ctPart10())],
                                                      boundary: "stow")
        let response = try await request("POST", "/dicomweb/studies", accept: "application/dicom+json",
                                     contentType: "multipart/related; type=\"application/dicom\"; boundary=stow",
                                     body: payload)
        XCTAssertEqual(response.status, 200, String(decoding: response.body, as: UTF8.self))
    }

    private func parts(_ response: Response) throws -> [DICOMwebMultipart.Part] {
        let type = try XCTUnwrap(response.headers.contentType)
        XCTAssertTrue(type.isMultipartRelated, "\(response.status) \(type): \(String(decoding: response.body, as: UTF8.self))")
        return try DICOMwebMultipart.parse(response.body, boundary: try XCTUnwrap(type.boundary))
    }

    /// A preamble and File Meta Information holding only the Transfer Syntax.
    static func metaWithTransferSyntaxOnly() -> Data {
        var elements = Data()
        func element(_ number: UInt8, _ vr: String, _ value: [UInt8]) {
            elements.append(contentsOf: [0x02, 0x00, number, 0x00] + Array(vr.utf8))
            if vr == "OB" {
                elements.append(contentsOf: [0, 0, UInt8(value.count), 0, 0, 0])
            } else {
                elements.append(contentsOf: [UInt8(value.count), 0])
            }
            elements.append(contentsOf: value)
        }
        element(0x01, "OB", [0, 1])
        element(0x10, "UI", Array("1.2.840.10008.1.2.1".utf8) + [0])
        var data = Data(count: 128) + Data("DICM".utf8)
        data.append(contentsOf: [0x02, 0x00, 0x00, 0x00, 0x55, 0x4C, 0x04, 0x00, UInt8(elements.count), 0, 0, 0])
        return data + elements
    }

    // MARK: Store (PS3.18 10.5, Annex I)

    func testStoreReturnsTheStoreInstancesResponseModule() async throws {
        var part = DICOMwebMultipart.Headers()
        part["Content-Type"] = "application/dicom"
        var other = DICOMwebMultipart.Headers()
        other["Content-Type"] = "text/plain"
        let payload = DICOMwebMultipart.Writer.encode(
            [(part, try Self.mrPart10()), (other, Data("not DICOM".utf8))], boundary: "b")
        let response = try await request("POST", "/dicomweb/studies/\(Self.study)", accept: "application/dicom+json",
                                     contentType: "multipart/related; type=application/dicom; boundary=b", body: payload)
        XCTAssertEqual(response.status, 202, "one stored, one other failure")
        let dataSet = try XCTUnwrap(try DICOMJSON.decode(response.body).first)
        let module = try DICOMwebStoreResponse(dataSet: dataSet)
        XCTAssertEqual(module.retrieveURL, "\(Self.origin)/dicomweb/studies/\(Self.study)")
        XCTAssertEqual(module.stored.map(\.sopInstanceUID), [Self.mrInstance])
        XCTAssertEqual(module.stored.first?.retrieveURL,
                       "\(Self.origin)/dicomweb/studies/\(Self.study)/series/\(Self.mrSeries)/instances/\(Self.mrInstance)")
        XCTAssertEqual(module.otherFailures, [DICOMwebStoreResponse.cannotUnderstand])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(Self.mrInstance + ".dcm").path))

        // A study mismatch fails the instance: nothing stored gives 409.
        let mismatch = try await request("POST", "/dicomweb/studies/1.2.3", accept: "application/dicom+json",
                                     contentType: "multipart/related; type=\"application/dicom\"; boundary=b",
                                     body: DICOMwebMultipart.Writer.encode([(part, try Self.ctPart10())], boundary: "b"))
        XCTAssertEqual(mismatch.status, 409)
        let failed = try DICOMwebStoreResponse(dataSet: try XCTUnwrap(try DICOMJSON.decode(mismatch.body).first))
        XCTAssertEqual(failed.failed.first?.reason, DICOMwebStoreResponse.studyInstanceUIDMismatch)

        let xml = try await request("POST", "/dicomweb/studies", accept: "application/dicom+xml",
                                contentType: "multipart/related; type=\"application/dicom\"; boundary=b",
                                body: DICOMwebMultipart.Writer.encode([(part, try Self.ctPart10())], boundary: "b"))
        XCTAssertEqual(xml.status, 200)
        XCTAssertEqual(xml.headers.contentType, .dicomXML)
        let module2 = try DICOMwebStoreResponse(dataSet: try DICOMXML.decode(xml.body))
        XCTAssertEqual(module2.stored.map(\.sopInstanceUID), [Self.ctInstance])

        // File Meta Information without Media Storage UIDs: the data set
        // identifies the instance.
        let mr = try Self.mrPart10()
        let header = try DICOMPart10Header.parse(mr, totalLength: UInt64(mr.count))
        let anonymous = try await request(
            "POST", "/dicomweb/studies", accept: "application/dicom+json",
            contentType: "multipart/related; type=\"application/dicom\"; boundary=b",
            body: DICOMwebMultipart.Writer.encode(
                [(part, Self.metaWithTransferSyntaxOnly() + mr.dropFirst(Int(header.dataSetOffset)))], boundary: "b"))
        XCTAssertEqual(anonymous.status, 200, String(decoding: anonymous.body, as: UTF8.self))
        let unsupported = try await request("POST", "/dicomweb/studies", accept: "application/dicom+json",
                                        contentType: "application/dicom", body: try Self.mrPart10())
        XCTAssertEqual(unsupported.status, 415)
        let noAccept = try await request("POST", "/dicomweb/studies",
                                     contentType: "multipart/related; type=\"application/dicom\"; boundary=b", body: payload)
        XCTAssertEqual(noAccept.status, 406)
        let truncated = try await request("POST", "/dicomweb/studies", accept: "application/dicom+json",
                                      contentType: "multipart/related; type=\"application/dicom\"; boundary=b",
                                      body: payload.prefix(payload.count - 10))
        XCTAssertEqual(truncated.status, 400)
    }

    // MARK: Search (PS3.18 10.6)

    func testSearchStudiesSeriesAndInstances() async throws {
        try await storeFixtures()
        let studies = try await request("GET", "/dicomweb/studies?PatientID=WEB-1&includefield=StudyDescription",
                                    accept: "application/dicom+json")
        XCTAssertEqual(studies.status, 200)
        let results = try DICOMJSON.decode(studies.body)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].string(forTag: "StudyInstanceUID"), Self.study)
        XCTAssertEqual(results[0].string(forTag: "RetrieveURL"), "\(Self.origin)/dicomweb/studies/\(Self.study)")
        XCTAssertEqual(results[0].string(forTag: "NumberOfStudyRelatedInstances"), "2")
        XCTAssertEqual(results[0].string(forTag: "NumberOfStudyRelatedSeries"), "2")
        XCTAssertEqual(results[0].textValues(forTag: "ModalitiesInStudy"), ["CT", "MR"])
        XCTAssertNil(results[0].element(forTagName: "QueryRetrieveLevel"))

        let none = try await request("GET", "/dicomweb/studies?PatientID=NOBODY", accept: "application/dicom+json")
        XCTAssertEqual(none.status, 200)
        XCTAssertEqual(none.body, Data("[]".utf8), "no match is an empty array (PS3.18 8.3.4.4.1)")

        let series = try await request("GET", "/dicomweb/studies/\(Self.study)/series?Modality=CT", accept: "application/dicom+json")
        let seriesResults = try DICOMJSON.decode(series.body)
        XCTAssertEqual(seriesResults.map { $0.string(forTag: "SeriesInstanceUID") }, [Self.ctSeries])
        XCTAssertEqual(seriesResults.first?.string(forTag: "RetrieveURL"),
                       "\(Self.origin)/dicomweb/studies/\(Self.study)/series/\(Self.ctSeries)")

        // A relational search, paginated, with an unsupported option.
        let instances = try await request("GET", "/dicomweb/instances?limit=1&fuzzymatching=true", accept: "application/dicom+json")
        XCTAssertEqual(try DICOMJSON.decode(instances.body).count, 1)
        let warning = try XCTUnwrap(instances.headers["Warning"])
        XCTAssertTrue(warning.contains("There are 1 additional results that can be requested"), warning)
        XCTAssertTrue(warning.contains("fuzzymatching parameter is not supported"), warning)
        let second = try await request("GET", "/dicomweb/instances?limit=1&offset=1", accept: "application/dicom+json")
        let secondResults = try DICOMJSON.decode(second.body)
        XCTAssertEqual(secondResults.count, 1)
        XCTAssertNil(second.headers["Warning"])
        XCTAssertEqual(secondResults.first?.string(forTag: "StudyInstanceUID"), Self.study, "study attributes in a relational search")

        let xml = try await request("GET", "/dicomweb/studies/\(Self.study)/series", accept: "multipart/related; type=\"application/dicom+xml\"")
        XCTAssertEqual(try parts(xml).count, 2)

        try await expect(400, "GET", "/dicomweb/studies?limit=x", accept: "application/dicom+json")
        try await expect(406, "GET", "/dicomweb/studies", accept: "image/jpeg")
        try await expect(406, "GET", "/dicomweb/studies", "Accept is required")
    }

    // MARK: Retrieve (PS3.18 10.4)

    func testRetrieveInstancesInTheSelectedTransferSyntax() async throws {
        try await storeFixtures()
        // Explicit VR Little Endian by default: the RLE image is decompressed.
        let study = try await request("GET", "/dicomweb/studies/\(Self.study)", accept: "multipart/related; type=\"application/dicom\"")
        XCTAssertEqual(study.status, 200)
        let instances = try parts(study)
        XCTAssertEqual(instances.count, 2)
        for part in instances {
            XCTAssertEqual(part.headers.contentType?.transferSyntax, TransferSyntax.explicitVRLittleEndian)
            let header = try DICOMPart10Header.parse(part.body, totalLength: UInt64(part.body.count))
            XCTAssertEqual(header.transferSyntaxUID, TransferSyntax.explicitVRLittleEndian)
        }
        let ct = try XCTUnwrap(instances.first { $0.headers.contentLocation?.hasSuffix(Self.ctInstance) ?? false })
        let ctHeader = try DICOMPart10Header.parse(ct.body, totalLength: UInt64(ct.body.count))
        let ctDataSet = try DICOMDataSetCoding.decode(ct.body.dropFirst(Int(ctHeader.dataSetOffset)),
                                                      transferSyntax: ctHeader.transferSyntaxUID)
        let native = try DICOMNativePixelData(dataset: ctDataSet)
        XCTAssertEqual(try native.frameData(0), Self.words(Self.ctFrames[0]))
        XCTAssertEqual(try native.frameData(1), Self.words(Self.ctFrames[1]))

        // With transfer-syntax=*, the instance is returned as stored.
        let stored = try await request("GET", "/dicomweb/studies/\(Self.study)/series/\(Self.ctSeries)",
                                   accept: "multipart/related; type=\"application/dicom\"; transfer-syntax=*")
        let storedPart = try XCTUnwrap(try parts(stored).first)
        XCTAssertEqual(storedPart.body, try Self.ctPart10(), "byte-identical to the stored file")
        XCTAssertEqual(storedPart.headers.contentType?.transferSyntax, DICOMRLECodec.transferSyntaxUID)

        // A single instance may be single part.
        let single = try await request("GET", "/dicomweb/studies/\(Self.study)/series/\(Self.mrSeries)/instances/\(Self.mrInstance)",
                                   accept: "application/dicom")
        XCTAssertEqual(single.headers.contentType?.essence, "application/dicom")
        XCTAssertEqual(single.body, try Self.mrPart10())

        try await expect(406, "GET", "/dicomweb/studies/\(Self.study)/series/\(Self.ctSeries)",
                                     accept: "multipart/related; type=\"application/dicom\"; transfer-syntax=1.2.840.10008.1.2.4.90")
        try await expect(404, "GET", "/dicomweb/studies/1.2.3", accept: "multipart/related; type=\"application/dicom\"")
        try await expect(405, "DELETE", "/dicomweb/studies/\(Self.study)", accept: "*/*")
    }

    func testRetrieveMetadataFramesAndPixelData() async throws {
        try await storeFixtures()
        let metadata = try await request("GET", "/dicomweb/studies/\(Self.study)/series/\(Self.ctSeries)/metadata",
                                     accept: "application/dicom+json")
        XCTAssertEqual(metadata.status, 200)
        let objects = try XCTUnwrap(try JSONSerialization.jsonObject(with: metadata.body) as? [[String: Any]])
        XCTAssertEqual(objects.count, 1)
        let pixelData = try XCTUnwrap(objects[0]["7FE00010"] as? [String: Any])
        XCTAssertEqual(pixelData["BulkDataURI"] as? String,
                       "\(Self.origin)/dicomweb/studies/\(Self.study)/series/\(Self.ctSeries)/instances/\(Self.ctInstance)/pixeldata")
        XCTAssertNil(objects[0]["00020010"], "metadata holds no File Meta Information")

        let base = "/dicomweb/studies/\(Self.study)/series/\(Self.ctSeries)/instances/\(Self.ctInstance)"
        // Uncompressed frames by default.
        let frames = try await request("GET", base + "/frames/2,1", accept: "multipart/related; type=\"application/octet-stream\"")
        let frameParts = try parts(frames)
        XCTAssertEqual(frameParts.map(\.body), [Self.words(Self.ctFrames[1]), Self.words(Self.ctFrames[0])])
        XCTAssertEqual(frameParts.first?.headers.contentLocation, "\(Self.origin)\(base)/frames/2")
        // The stored compressed frame.
        let rle = try await request("GET", base + "/frames/1", accept: "multipart/related; type=\"image/dicom-rle\"")
        XCTAssertEqual(try parts(rle).first?.body, try Self.ctEncodedFrames()[0])
        try await expect(404, "GET", base + "/frames/3", accept: "multipart/related; type=\"application/octet-stream\"")

        // Pixel Data of an uncompressed image is one representation.
        let pixel = try await request("GET", "/dicomweb/studies/\(Self.study)/series/\(Self.mrSeries)/instances/\(Self.mrInstance)/pixeldata",
                                  accept: "multipart/related; type=\"application/octet-stream\"")
        XCTAssertEqual(try parts(pixel).map(\.body), [Self.words(Self.mrPixels)])
    }

    func testRenderedThumbnailAndCapabilities() async throws {
        try await storeFixtures()
        let base = "/dicomweb/studies/\(Self.study)/series/\(Self.mrSeries)/instances/\(Self.mrInstance)"
        let jpeg = try await request("GET", base + "/rendered", accept: "image/jpeg")
        XCTAssertEqual(jpeg.status, 200)
        XCTAssertEqual(jpeg.headers.contentType, .jpeg)
        XCTAssertTrue(jpeg.body.starts(with: [0xFF, 0xD8]))

        // viewport scales the 2x2 image into 8x4, keeping its aspect ratio.
        let png = try await request("GET", base + "/rendered?viewport=8,4&window=2048,4096,linear", accept: "image/png")
        let pngData = png.body
        XCTAssertTrue(pngData.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        func bigEndian(_ offset: Int) -> Int { pngData[offset..<(offset + 4)].reduce(0) { $0 << 8 | Int($1) } }
        XCTAssertEqual([bigEndian(16), bigEndian(20)], [4, 4], "PNG IHDR width and height")

        // Two frames are rendered as a multipart payload.
        let frames = try await request("GET", "/dicomweb/studies/\(Self.study)/series/\(Self.ctSeries)/rendered",
                                   accept: "multipart/related; type=\"image/png\"")
        XCTAssertEqual(try parts(frames).count, 2)
        let thumbnail = try await request("GET", "/dicomweb/studies/\(Self.study)/thumbnail?viewport=64,64", accept: "image/jpeg")
        XCTAssertEqual(thumbnail.status, 200)
        try await expect(400, "GET", "/dicomweb/studies/\(Self.study)/thumbnail?viewport=64,64,0,0,1,1",
                                     accept: "image/jpeg")
        try await expect(400, "GET", base + "/rendered?quality=0", accept: "image/jpeg")
        try await expect(406, "GET", base + "/rendered", accept: "application/dicom")
        let annotated = try await request("GET", base + "/rendered?annotation=patient", accept: "image/jpeg")
        XCTAssertTrue(annotated.headers["Warning"]?.contains("annotation values are not supported") ?? false)

        let capabilities = try await request("OPTIONS", "/dicomweb", accept: "application/vnd.sun.wadl+xml")
        XCTAssertEqual(capabilities.status, 200)
        let wadl = String(decoding: capabilities.body, as: UTF8.self)
        XCTAssertTrue(wadl.contains("<resources base=\"\(Self.origin)/dicomweb\">"), wadl)
        XCTAssertTrue(wadl.contains("StoreInstances"))
        try await expect(404, "GET", "/other/studies", accept: "application/dicom+json")
    }

    func testViewportCropsFlipsAndScales() {
        let image = DICOMRenderedImage(width: 4, height: 2, format: .gray8, pixels: [0, 10, 20, 30, 40, 50, 60, 70])
        let same = DICOMwebRenderingParameters.apply(.init(width: 4, height: 2), to: image)
        XCTAssertEqual(same, image)
        // The right half, flipped horizontally.
        let flipped = DICOMwebRenderingParameters.apply(
            .init(width: 2, height: 2, sourceX: 2, sourceY: 0, sourceWidth: -2, sourceHeight: 2), to: image)
        XCTAssertEqual(flipped.pixels, [30, 20, 70, 60])
        let scaled = DICOMwebRenderingParameters.apply(.init(width: 100, height: 10), to: image)
        XCTAssertEqual([scaled.width, scaled.height], [20, 10])
    }
}
