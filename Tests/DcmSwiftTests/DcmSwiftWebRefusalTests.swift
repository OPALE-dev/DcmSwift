import XCTest
@testable import DcmSwift

/// Refusals of the DICOMweb origin server for images it cannot decode or
/// render: an image over the ``DICOMImageLimits``, and a Transfer Syntax
/// without an available decoder. Both are 406 with a typed error, never 404
/// ("no image") or 500.
final class DcmSwiftWebRefusalTests: XCTestCase {
    typealias Fixtures = DcmSwiftWebServerTests
    static let largeSeries = "1.2.826.0.1.3680043.10.999.1.7"
    static let largeInstance = "1.2.826.0.1.3680043.10.999.1.7.1"
    static let htj2kSeries = "1.2.826.0.1.3680043.10.999.1.8"
    static let htj2kInstance = "1.2.826.0.1.3680043.10.999.1.8.1"
    static let htj2k = "1.2.840.10008.1.2.4.201"

    private var directory: URL!
    private var server: DICOMwebOriginServer!
    private var htj2kWasEnabled = false

    override func setUp() async throws {
        htj2kWasEnabled = DICOMCapabilities.isHTJ2KEnabled
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-web-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let services = DICOMArchiveServices(archive: DICOMArchive(directory: directory))
        server = DICOMwebOriginServer(configuration: .init(basePath: "/dicomweb"),
                                      search: services, retrieve: services, store: services)
    }

    override func tearDown() async throws {
        DICOMCapabilities.isHTJ2KEnabled = htj2kWasEnabled
        try? FileManager.default.removeItem(at: directory)
    }

    /// A native 2x2 image that declares more frames than the default limit
    /// of 1,000,000; its Pixel Data holds one frame.
    static func largePart10() throws -> Data {
        let dataSet = Fixtures.image(sopClass: "1.2.840.10008.5.1.4.1.1.4", instance: largeInstance,
                                     series: largeSeries, seriesNumber: "7", modality: "MR", rows: 2, columns: 2,
                                     frames: 2_000_000)
        let pixels = DataElement(withTagName: "PixelData", dataset: dataSet)!
        pixels.vr = .OW
        _ = pixels.setValue(Data(count: 8))
        dataSet.add(element: pixels)
        return DICOMPart10Header.encodeMetaInformation(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.4", sopInstanceUID: largeInstance,
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian, sourceAETitle: nil)
            + (try DICOMDataSetCoding.encode(dataSet, transferSyntax: TransferSyntax.explicitVRLittleEndian))
    }

    /// An HTJ2K image with one frame; the frame is never decoded here.
    static func htj2kPart10() throws -> Data {
        let dataSet = Fixtures.image(sopClass: "1.2.840.10008.5.1.4.1.1.4", instance: htj2kInstance,
                                     series: htj2kSeries, seriesNumber: "8", modality: "MR", rows: 2, columns: 2,
                                     frames: 1)
        dataSet.transferSyntax = TransferSyntax(htj2k)
        let sequence = PixelSequence(withTag: DataTag(withGroup: "7fe0", element: "0010"))
        sequence.vr = .OB
        sequence.length = -1
        for value in [Data(), Data([0xFF, 0x4F, 0xFF, 0x51, 0xFF, 0xD9])] {
            let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
            item.data = value
            item.length = value.count
            sequence.items.append(item)
        }
        dataSet.add(element: sequence)
        return DICOMPart10Header.encodeMetaInformation(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.4", sopInstanceUID: htj2kInstance,
            transferSyntaxUID: htj2k, sourceAETitle: nil)
            + (try DICOMDataSetCoding.encode(dataSet, transferSyntax: htj2k))
    }

    private func respond(_ method: String, _ target: String, accept: String? = nil,
                         contentType: String? = nil, body: Data = Data()) async -> DICOMwebHTTPResponse {
        var headers = DICOMwebMultipart.Headers()
        if let accept { headers["Accept"] = accept }
        if let contentType { headers["Content-Type"] = contentType }
        return await server.respond(to: DICOMwebHTTPRequest(method: method, target: target, headers: headers, body: body),
                                    origin: Fixtures.origin)
    }

    private func store(_ instances: [Data]) async throws {
        var part = DICOMwebMultipart.Headers()
        part["Content-Type"] = "application/dicom"
        let payload = DICOMwebMultipart.Writer.encode(instances.map { (part, $0) }, boundary: "stow")
        let response = await respond("POST", "/dicomweb/studies", accept: "application/dicom+json",
                                     contentType: "multipart/related; type=\"application/dicom\"; boundary=stow",
                                     body: payload)
        let body = try await response.collectBody()
        XCTAssertEqual(response.status, 200, String(decoding: body, as: UTF8.self))
    }

    private func message(_ response: DICOMwebHTTPResponse) async throws -> String {
        String(decoding: try await response.collectBody(), as: UTF8.self)
    }

    func testImageOverTheLimitsIsRefusedWith406() async throws {
        try await store([try Self.largePart10()])
        let series = "/dicomweb/studies/\(Fixtures.study)/series/\(Self.largeSeries)"
        let instance = series + "/instances/\(Self.largeInstance)"
        for (method, target, accept) in [
            ("GET", instance + "/rendered", "image/jpeg"), ("HEAD", instance + "/rendered", "image/jpeg"),
            ("GET", instance + "/thumbnail", "image/jpeg"), ("GET", series + "/rendered", nil),
            ("GET", series + "/thumbnail", nil), ("GET", instance + "/frames/1", "multipart/related; type=\"application/octet-stream\""),
            ("GET", instance + "/pixeldata", nil),
        ] {
            let response = await respond(method, target, accept: accept)
            XCTAssertEqual(response.status, 406, "\(method) \(target)")
            guard case .limitExceeded(let name, let value, let limit)? = response.error?.pixelDataError else {
                return XCTFail("\(method) \(target): \(String(describing: response.error))")
            }
            XCTAssertEqual(value, 2_000_000)
            XCTAssertEqual(limit, DICOMImageLimits.defaultMaximumNumberOfFrames)
            XCTAssertEqual(name, "NumberOfFrames")
            if method == "GET" {
                let text = try await message(response)
                XCTAssertTrue(text.contains("above the limit"), text)
                XCTAssertFalse(text.contains("no renderable image") || text.contains("no Pixel Data"), text)
            }
        }
    }

    func testTransferSyntaxWithoutDecoderIsRefusedWith406() async throws {
        DICOMCapabilities.isHTJ2KEnabled = false
        try await store([try Self.htj2kPart10()])
        let series = "/dicomweb/studies/\(Fixtures.study)/series/\(Self.htj2kSeries)"
        let instance = series + "/instances/\(Self.htj2kInstance)"
        for (method, target, accept) in [
            ("GET", instance + "/rendered", "image/jpeg"), ("HEAD", instance + "/rendered", "image/png"),
            ("GET", instance + "/thumbnail", nil), ("GET", series + "/rendered", nil),
            ("GET", instance + "/frames/1", "multipart/related; type=\"application/octet-stream\""),
        ] {
            let response = await respond(method, target, accept: accept)
            XCTAssertEqual(response.status, 406, "\(method) \(target)")
            XCTAssertEqual(response.error?.pixelDataError, .encapsulatedPixelData(transferSyntax: Self.htj2k),
                           "\(method) \(target)")
            if method == "GET" {
                let text = try await message(response)
                XCTAssertTrue(text.contains("No decoder is available") && text.contains("HTJ2K decoding is disabled"),
                              text)
            }
        }
        // The stored frame stays available as it is.
        let compressed = await respond("GET", instance + "/frames/1", accept: "multipart/related; type=\"image/jphc\"")
        XCTAssertEqual(compressed.status, 200)
        XCTAssertNil(compressed.error)
    }

    func testOtherRefusalsKeepTheirStatusAndCarryTheirError() async throws {
        try await store([try Fixtures.mrPart10()])
        let missing = await respond("GET", "/dicomweb/studies/\(Fixtures.study)/series/9.9/instances/9.9/rendered")
        XCTAssertEqual(missing.status, 404)
        XCTAssertNil(missing.error?.pixelDataError)
        let base = "/dicomweb/studies/\(Fixtures.study)/series/\(Fixtures.mrSeries)/instances/\(Fixtures.mrInstance)"
        let rendered = await respond("GET", base + "/rendered", accept: "image/jpeg")
        XCTAssertEqual(rendered.status, 200)
        XCTAssertNil(rendered.error)
        let unacceptable = await respond("GET", base + "/rendered", accept: "application/dicom")
        XCTAssertEqual(unacceptable.status, 406)
        XCTAssertEqual(unacceptable.error?.status, 406)
        XCTAssertNil(unacceptable.error?.pixelDataError)
    }
}
