import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix
import XCTest
@testable import DcmSwift

/// JPIP Referenced Pixel Data (PS3.5 8.4.1): JPP-stream parsing, codestream
/// reconstruction, and retrieval. The fixtures are responses of Kakadu's
/// kdu_server 8.4.1 for synthetic images, and kdu_expand's decoding of them.
final class DcmSwiftJPIPTests: XCTestCase {
    private func resource(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext)))
    }

    /// The samples of a binary PGM file.
    private func pgm(_ data: Data) throws -> (width: Int, height: Int, samples: [UInt8]) {
        let bytes = [UInt8](data)
        var fields: [String] = [], position = 2, current = ""
        while fields.count < 3, position < bytes.count {
            let character = Character(UnicodeScalar(bytes[position]))
            if character.isWhitespace {
                if !current.isEmpty { fields.append(current); current = "" }
            } else {
                current.append(character)
            }
            position += 1
        }
        return (Int(fields[0])!, Int(fields[1])!, Array(bytes[position...]))
    }

    private func cache(_ stream: Data) throws -> JPIPCache {
        var parser = JPIPStreamParser()
        var cache = JPIPCache()
        for message in try parser.feed(stream) { try cache.add(message) }
        try parser.finish()
        return cache
    }

    // MARK: Messages (ISO/IEC 15444-9 Annex A)

    func testParserReadsHeadersAcrossChunks() throws {
        let stream = Data([
            0x70, 0x06, 0x00, 0x00, 0x02, 0xFF, 0x4F,   // Class 6, CSn 0, id 0, complete: SOC
            0xA1, 0x05, 0x01, 0x03, 0xAA, 0xBB, 0xCC,   // same Class and CSn, id 0x85 (two bytes), offset 1
            0x60, 0x01, 0x02, 0x00, 0x01, 0x07, 0xDD,   // extended precinct 0 of codestream 2, Aux 7
            0x00, 0x01, 0x01, 0x42,                     // End of Response: image done, body 0x42
        ])
        var parser = JPIPStreamParser()
        var messages: [JPIPMessage] = []
        for byte in stream { messages += try parser.feed([byte]) }
        try parser.finish()
        XCTAssertEqual(messages, [
            .dataBin(classID: 6, codestream: 0, id: 0, offset: 0, data: Data([0xFF, 0x4F]), isLast: true),
            .dataBin(classID: 6, codestream: 0, id: 0x85, offset: 1, data: Data([0xAA, 0xBB, 0xCC]), isLast: false),
            .dataBin(classID: 1, codestream: 2, id: 0, offset: 0, data: Data([0xDD]), isLast: false),
            .endOfResponse(reason: 1, body: Data([0x42])),
        ])
        var truncated = JPIPStreamParser()
        _ = try truncated.feed([0x70, 0x06, 0x00, 0x00, 0x05, 0xFF])
        XCTAssertThrowsError(try truncated.finish())
        var invalid = JPIPStreamParser()
        XCTAssertThrowsError(try invalid.feed([0x10, 0x00]), "a Bin-ID indicator of 0 is invalid")
    }

    func testCacheAssemblesRangesInAnyOrder() throws {
        var cache = JPIPCache()
        try cache.add(.dataBin(classID: 0, codestream: 0, id: 3, offset: 4, data: Data([5, 6]), isLast: true))
        XCTAssertEqual(cache.dataBin(.precinct, codestream: 0, id: 3)?.isComplete, false)
        XCTAssertEqual(cache.dataBin(.precinct, codestream: 0, id: 3)?.data, Data())
        try cache.add(.dataBin(classID: 1, codestream: 0, id: 3, offset: 0, data: Data([1, 2, 3, 4]), isLast: false))
        let bin = cache.dataBin(.precinct, codestream: 0, id: 3)
        XCTAssertEqual(bin?.data, Data([1, 2, 3, 4, 5, 6]), "extended precincts fill the same data-bin")
        XCTAssertEqual(bin?.isComplete, true)
        // An offset from the network cannot make the cache allocate gigabytes.
        var bounded = JPIPCache(maximumDataBinLength: 1 << 20)
        XCTAssertThrowsError(try bounded.add(.dataBin(classID: 0, codestream: 0, id: 0, offset: Int(Int32.max),
                                                      data: Data([1]), isLast: true)))
    }

    // MARK: Codestreams rebuilt from Kakadu responses

    func testKakaduJPPStreamRebuildsTheSourceImage() throws {
        let codestream = try JPIPCodestream.build(from: cache(resource("jpip-gray8", "jpp")))
        let source = try pgm(resource("jpip-gray8", "pgm"))
        let description = DICOMPixelDescription(
            rows: source.height, columns: source.width, samplesPerPixel: 1, photometricInterpretation: .monochrome2,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false, planarConfiguration: 0, numberOfFrames: 1,
            isEncapsulated: true)
        let decoded = try DICOMJPEG2000Codec().decode(codestream, description: description)
        XCTAssertEqual([UInt8](decoded.data), source.samples)
    }

    /// Three components with the reversible color transform, SOP and EPH
    /// markers, COC precinct overrides, and six tiles; served in LRCP and
    /// rebuilt in RPCL.
    func testKakaduJPPStreamWithComponentOverridesAndMarkers() throws {
        let codestream = try JPIPCodestream.build(from: cache(resource("jpip-coc", "jpp")))
        XCTAssertNil(codestream.range(of: Data([0xFF, 0x91])), "SOP markers are not in precinct data-bins")
        let components = try (0..<3).map { try pgm(resource("jpip-coc-\($0)", "pgm")) }
        let description = DICOMPixelDescription(
            rows: components[0].height, columns: components[0].width, samplesPerPixel: 3,
            photometricInterpretation: .ybrRCT, bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false,
            planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: true)
        let decoded = [UInt8](try DICOMJPEG2000Codec().decode(codestream, description: description).data)
        for component in 0..<3 {
            let samples = stride(from: component, to: decoded.count, by: 3).map { decoded[$0] }
            XCTAssertEqual(samples, components[component].samples, "component \(component)")
        }
        // The same image decoded from the original file.
        let original = try DICOMJPIPClient.contiguousCodestream(resource("jpip-coc", "jp2"), index: 0)
        XCTAssertEqual(try DICOMJPEG2000Codec().decode(original, description: description).data, Data(decoded))
    }

    /// Mutated responses fail cleanly: the parser and the reconstruction
    /// read untrusted network data.
    func testMutatedStreamsNeverCrash() throws {
        let stream = [UInt8](try resource("jpip-coc", "jpp"))
        var generator = SystemRandomNumberGenerator()
        for iteration in 0..<300 {
            var mutated = stream
            for _ in 0...(iteration % 8) {
                let index = Int.random(in: 0..<mutated.count, using: &generator)
                mutated[index] = UInt8.random(in: 0...255, using: &generator)
            }
            if iteration % 5 == 0 { mutated.removeLast(Int.random(in: 0..<200, using: &generator)) }
            var parser = JPIPStreamParser()
            var cache = JPIPCache()
            guard let messages = try? parser.feed(mutated) else { continue }
            for message in messages { try? cache.add(message) }
            _ = try? JPIPCodestream.build(from: cache)
        }
    }

    /// A tile origin after the image would give no tile, or a negative
    /// count, and tile indexes have 16 bits; such SIZ segments are rejected
    /// (ISO/IEC 15444-1 A.4.2, A.5.1).
    func testSIZWithTileOriginOutsideTheImageIsRejected() {
        func siz(width: Int, x0: Int, tileWidth: Int, tileX0: Int) -> [UInt8] {
            func u32(_ value: Int) -> [UInt8] { [24, 16, 8, 0].map { UInt8((value >> $0) & 0xFF) } }
            var body: [UInt8] = [0, 0]
            for value in [width, 64, x0, 0, tileWidth, 64, tileX0, 0] { body += u32(value) }
            return body + [0, 1, 7, 1, 1]
        }
        XCTAssertNoThrow(try JPIPCodestream.SIZ(siz(width: 64, x0: 0, tileWidth: 64, tileX0: 0)))
        XCTAssertThrowsError(try JPIPCodestream.SIZ(siz(width: 64, x0: 0, tileWidth: 32, tileX0: 200)))
        XCTAssertThrowsError(try JPIPCodestream.SIZ(siz(width: 64, x0: 40, tileWidth: 32, tileX0: 0)))
        XCTAssertThrowsError(try JPIPCodestream.SIZ(siz(width: 1 << 20, x0: 0, tileWidth: 1, tileX0: 0)), "too many tiles")
    }

    func testIncompleteDataBinsAreRejected() throws {
        var stream = [UInt8](try resource("jpip-gray8", "jpp"))
        stream.removeLast(40)
        var parser = JPIPStreamParser()
        var cache = JPIPCache()
        for message in try parser.feed(stream) { try cache.add(message) }
        XCTAssertThrowsError(try JPIPCodestream.build(from: cache))
        XCTAssertThrowsError(try JPIPCodestream.build(from: JPIPCache()), "no main header")
    }

    /// Every file of `DCMSWIFT_JPIP_FILES`, served by the JPIP server at
    /// `DCMSWIFT_JPIP_ORACLE` (such as kdu_server), is retrieved and decoded
    /// like the file itself. With `DCMSWIFT_JPIP_OUTPUT`, the rebuilt
    /// codestreams are written there for Scripts/crosscheck/jpip_kakadu.sh.
    func testRetrievalFromAnIndependentJPIPServer() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let oracle = environment["DCMSWIFT_JPIP_ORACLE"], let folder = environment["DCMSWIFT_JPIP_FILES"] else {
            throw XCTSkip("Set DCMSWIFT_JPIP_ORACLE and DCMSWIFT_JPIP_FILES to run")
        }
        let output = environment["DCMSWIFT_JPIP_OUTPUT"].map { URL(fileURLWithPath: $0) }
        let client = DICOMJPIPClient()
        var checked = 0
        let names = try FileManager.default.contentsOfDirectory(atPath: folder).sorted()
            .filter { ["jp2", "jph", "jpx", "j2c"].contains(($0 as NSString).pathExtension) }
        for name in names {
            let file = try Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent(name))
            var originals: [Data] = []
            if file.starts(with: [0xFF, 0x4F]) {
                originals = [file]
            } else {
                while let codestream = try? DICOMJPIPClient.contiguousCodestream(file, index: originals.count) {
                    originals.append(codestream)
                }
            }
            for (index, original) in originals.enumerated() {
                let main = try JPIPCodestream.MainHeader(Self.mainHeader(original))
                let width = main.siz.width - main.siz.x0, height = main.siz.height - main.siz.y0
                let rebuilt = try await client.codestream(providerURL: "\(oracle)/\(name)", width: width, height: height,
                                                         stream: originals.count > 1 ? index : nil)
                if let output {
                    try rebuilt.write(to: output.appendingPathComponent("\(name)-\(index).j2c"))
                }
                // Both decoded by the built-in decoder, when it reads the file.
                let components = main.siz.components
                let description = DICOMPixelDescription(
                    rows: height, columns: width, samplesPerPixel: components.count,
                    photometricInterpretation: components.count == 3 ? .ybrRCT : .monochrome2,
                    bitsAllocated: components[0].precision > 8 ? 16 : 8, bitsStored: components[0].precision,
                    highBit: components[0].precision - 1, isSigned: false, planarConfiguration: 0, numberOfFrames: 1,
                    isEncapsulated: true)
                guard Set(components.map(\.dx)) == [1], Set(components.map(\.dy)) == [1],
                      let expected = try? DICOMJPEG2000Codec().decode(original, description: description) else {
                    print("\(name) codestream \(index): rebuilt; not decodable by OpenJPEG, compare with kdu_expand")
                    continue
                }
                XCTAssertEqual(try DICOMJPEG2000Codec().decode(rebuilt, description: description).data, expected.data,
                               "\(name) codestream \(index)")
                checked += 1
            }
        }
        print("JPIP interoperability: \(checked) codestreams decoded identically")
        XCTAssertGreaterThan(checked, 0)
    }

    /// The main header of a codestream: SOC up to the first SOT.
    static func mainHeader(_ codestream: Data) -> Data {
        let bytes = [UInt8](codestream)
        var position = 2
        while position + 4 <= bytes.count, bytes[position] == 0xFF, bytes[position + 1] != 0x90 {
            position += 2 + (Int(bytes[position + 2]) << 8 | Int(bytes[position + 3]))
        }
        return Data(bytes[..<position])
    }

    func testJPIPChannelAndJP2Boxes() throws {
        let channel = try XCTUnwrap(DICOMJPIPClient.channel(
            "cid=JPH_3aa2,path=jpip,transport=http", providerURL: "http://host:8080/images/a.jp2?target=a"))
        XCTAssertEqual(channel.id, "JPH_3aa2")
        XCTAssertEqual(channel.base, "http://host:8080/jpip")
        XCTAssertNil(DICOMJPIPClient.channel("path=jpip", providerURL: "http://host/a.jp2"))
        let jp2 = try resource("jpip-coc", "jp2")
        let codestream = try DICOMJPIPClient.contiguousCodestream(jp2, index: 0)
        XCTAssertTrue(codestream.starts(with: [0xFF, 0x4F]))
        XCTAssertThrowsError(try DICOMJPIPClient.contiguousCodestream(jp2, index: 1))
        XCTAssertTrue(DICOMJPIPClient.isReversible(codestream))
    }

    // MARK: DICOM instances

    func testDeflatedJPIPTransferSyntaxRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-jpip-\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: url) }
        let dataSet = jpipInstance(url: "http://example.org/jpip?target=a.jp2", frames: nil)
        dataSet.transferSyntax = TransferSyntax(TransferSyntax.jpipReferencedDeflate)
        dataSet.hasPreamble = true
        _ = dataSet.set(value: TransferSyntax.jpipReferencedDeflate, forTagName: "TransferSyntaxUID")
        _ = dataSet.set(value: "1.2.840.10008.5.1.4.1.1.7", forTagName: "MediaStorageSOPClassUID")
        _ = dataSet.set(value: "1.2.826.0.1.3680043.10.999.7", forTagName: "MediaStorageSOPInstanceUID")
        XCTAssertTrue(try DicomOutputStream(url: url).write(dataset: dataSet))
        let read = try XCTUnwrap(try DicomInputStream(url: url).readDataset())
        XCTAssertEqual(read.transferSyntax.tsUID, TransferSyntax.jpipReferencedDeflate)
        XCTAssertEqual(read.string(forTag: "PixelDataProviderURL"), "http://example.org/jpip?target=a.jp2")
        XCTAssertTrue(DICOMJPIPClient.isJPIPReferenced(read))
        XCTAssertTrue(TransferSyntax.deflatesDataSet(TransferSyntax.jpipHTJ2KReferencedDeflate))
        XCTAssertFalse(TransferSyntax.deflatesDataSet(TransferSyntax.jpipReferenced))
    }

    private func jpipInstance(url: String, frames: Int?) -> DataSet {
        let dataSet = DataSet()
        dataSet.transferSyntax = TransferSyntax(TransferSyntax.jpipReferenced)
        for (keyword, value) in [("SOPClassUID", "1.2.840.10008.5.1.4.1.1.7"),
                                 ("SOPInstanceUID", "1.2.826.0.1.3680043.10.999.7"),
                                 ("PhotometricInterpretation", "MONOCHROME2"), ("PixelDataProviderURL", url)] {
            _ = dataSet.set(value: value, forTagName: keyword)
        }
        _ = dataSet.set(value: UInt16(48), forTagName: "Rows")
        _ = dataSet.set(value: UInt16(64), forTagName: "Columns")
        _ = dataSet.set(value: UInt16(1), forTagName: "SamplesPerPixel")
        _ = dataSet.set(value: UInt16(8), forTagName: "BitsAllocated")
        _ = dataSet.set(value: UInt16(8), forTagName: "BitsStored")
        _ = dataSet.set(value: UInt16(7), forTagName: "HighBit")
        _ = dataSet.set(value: UInt16(0), forTagName: "PixelRepresentation")
        if let frames { _ = dataSet.set(value: String(frames), forTagName: "NumberOfFrames") }
        return dataSet
    }

    /// A provider that answers every request with the gray8 JPP-stream.
    func testResolveRetrievesAndEncapsulatesTheFrames() async throws {
        let stream = try resource("jpip-gray8", "jpp")
        let requests = NIOLockedValueBox<[String]>([])
        let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(FixedResponder(body: stream, contentType: "image/jpp-stream", requests: requests))
                }
            }
            .bind(host: "127.0.0.1", port: 0).get()
        defer { try? server.close().wait() }
        let port = try XCTUnwrap(server.localAddress?.port)

        let dataSet = jpipInstance(url: "http://127.0.0.1:\(port)/gray8.jp2", frames: nil)
        let client = DICOMJPIPClient()
        let frames = try await client.decodedFrames(of: dataSet)
        let source = try pgm(resource("jpip-gray8", "pgm"))
        XCTAssertEqual([UInt8](frames[0].data), source.samples)
        XCTAssertTrue(requests.withLockedValue { $0 }.first?.contains("fsiz=64,48") ?? false)

        let resolved = try await client.resolve(dataSet)
        XCTAssertEqual(resolved.transferSyntax.tsUID, DICOMJPEG2000Codec.lossless, "a reversible codestream is lossless")
        XCTAssertNil(resolved.element(forTagName: "PixelDataProviderURL"))
        let encapsulated = try DICOMEncapsulatedPixelData(dataset: resolved)
        XCTAssertEqual([UInt8](try encapsulated.decodedFrame(0).data), source.samples)
        let rendered = try DICOMImageRenderer(dataset: resolved).render(frame: 0)
        XCTAssertEqual(rendered.width, 64)

        let multiFrame = jpipInstance(url: "http://127.0.0.1:\(port)/frames.jpx?target=x", frames: 2)
        do {
            _ = try await client.codestream(of: multiFrame, frame: 2)
            XCTFail("the provider only holds codestream 0")
        } catch is JPIPError {}
        XCTAssertTrue(requests.withLockedValue { $0 }.last?.contains("?target=x&type=jpp-stream") ?? false)
        XCTAssertTrue(requests.withLockedValue { $0 }.last?.contains("stream=2") ?? false)
    }
}

/// Answers every request with the same body.
private final class FixedResponder: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    let body: Data
    let contentType: String
    let requests: NIOLockedValueBox<[String]>

    init(body: Data, contentType: String, requests: NIOLockedValueBox<[String]>) {
        self.body = body
        self.contentType = contentType
        self.requests = requests
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requests.withLockedValue { $0.append(head.uri) }
        case .body:
            break
        case .end:
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: contentType)
            headers.add(name: "Content-Length", value: String(body.count))
            context.write(wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: .ok, headers: headers))), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(ByteBuffer(bytes: body)))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}
