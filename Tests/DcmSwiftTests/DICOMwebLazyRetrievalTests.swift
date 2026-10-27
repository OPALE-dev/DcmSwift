import XCTest
@testable import DcmSwift

final class DICOMwebLazyRetrievalTests: XCTestCase {
    func testMetadataURILeavesDeferredValuesUnloaded() throws {
        for vr: VR.VR in [.OW, .UN] {
            let ds = DataSet()
            let pixels = DataElement(withTag: DataTag(withGroup: "7FE0", element: "0010"), dataset: ds)
            pixels.vr = vr
            pixels.length = 1024
            pixels.deferData(to: DICOMBulkDataReference(url: URL(fileURLWithPath: "/does-not-exist/metadata-pixels"), offset: 0, length: 1024))
            ds.add(element: pixels)
            var options = DICOMJSON.EncodingOptions()
            options.bulkDataURI = { _ in "https://example.test/pixeldata" }
            let json = try DICOMJSON.object(ds, options: options)
            XCTAssertEqual((json["7FE00010"] as? [String: Any])?["BulkDataURI"] as? String, "https://example.test/pixeldata")
            XCTAssertFalse(pixels.isDataLoaded)
        }
    }

    func testUnambiguousUnknownBinaryVRKeepsItsDeferredReference() throws {
        let ds = DataSet()
        let document = DataElement(withTag: DataTag(withGroup: "0042", element: "0011"), dataset: ds)
        document.vr = .UN; document.length = 4096
        document.deferData(to: DICOMBulkDataReference(url: URL(fileURLWithPath: "/does-not-exist/document"), offset: 0, length: 4096))
        ds.add(element: document)
        var options = DICOMJSON.EncodingOptions()
        options.bulkDataURI = { $0.vr == .OB ? "https://example.test/document" : nil }
        let object = try DICOMJSON.object(ds, options: options)
        let attribute = try XCTUnwrap(object["00420011"] as? [String: Any])
        XCTAssertEqual(attribute["vr"] as? String, "OB")
        XCTAssertEqual(attribute["BulkDataURI"] as? String, "https://example.test/document")
        XCTAssertFalse(document.isDataLoaded)
    }

    func testEncapsulatedFramesDoNotAccumulateInTheDataset() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("dicomweb-encapsulated-\(UUID())")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let file=directory.appendingPathComponent("cine.dcm")
        try DcmSwiftWebServerTests.ctPart10().write(to:file)
        let ds=try DICOMwebTranscoding.dataSet(DICOMRetrieveItem(file:file))
        let sequence=try XCTUnwrap(ds.element(forTagName:"PixelData") as? DataSequence)
        let frames=try DICOMEncapsulatedPixelData(dataset:ds)
        let expected=try DcmSwiftWebServerTests.ctEncodedFrames()
        for number in expected.indices {
            XCTAssertEqual(try frames.encodedFrame(number),expected[number])
            XCTAssertEqual(try frames.decodedFrame(number).data.count,12)
            XCTAssertTrue(sequence.items.dropFirst().allSatisfy { !$0.isDataLoaded },"Previously sent fragments must stay file-backed")
        }
    }

    func testFileResponseIsPulledAndPropagatesReadErrors() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("dicomweb-stream-\(UUID())")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let file=directory.appendingPathComponent("payload")
        try Data([10,11,12]).write(to:file)
        let body=DICOMwebPayloadBody([(Data([1]),Data([2]),DICOMDataSetPayload(file:file,length:3))],trailer:Data([3]))
        var iterator=body.stream().makeAsyncIterator()
        let first=try await iterator.next();XCTAssertEqual(first,Data([1]))
        // The source has not been opened or collected ahead of the consumer.
        try FileManager.default.removeItem(at:file)
        let second=try await iterator.next();XCTAssertEqual(second,Data([2]))
        do {_ = try await iterator.next();XCTFail("Source read failure must reach the consumer")}
        catch {}
    }

    func testTruncatedResponseCannotSilentlyFinish() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("dicomweb-short-\(UUID())")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let file=directory.appendingPathComponent("payload");try Data([1,2]).write(to:file)
        var iterator=DICOMwebPayloadBody([(nil,Data(),DICOMDataSetPayload(file:file,length:3))],trailer:Data([9])).stream().makeAsyncIterator()
        let first=try await iterator.next();XCTAssertEqual(first,Data([1,2]))
        do {_ = try await iterator.next();XCTFail("EOF before the declared payload length is an error")}
        catch {}
    }

    func testStoredNativeFramesUseRangeReadsAndRespectPayloadSlice() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dicomweb-lazy-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ds = DataSet()
        for (tag, value) in [("SOPClassUID", "1.2.840.10008.5.1.4.1.1.7"), ("SOPInstanceUID", "1.2.3.4"), ("PhotometricInterpretation", "MONOCHROME2"), ("NumberOfFrames", "3")] {
            _ = ds.set(value: value, forTagName: tag)
        }
        for (tag, value): (String, UInt16) in [("Rows", 2), ("Columns", 2), ("SamplesPerPixel", 1), ("BitsAllocated", 8), ("BitsStored", 8), ("HighBit", 7), ("PixelRepresentation", 0)] {
            _ = ds.set(value: value, forTagName: tag)
        }
        _ = ds.set(value: Data(0..<12), forTagName: "PixelData")
        let file = directory.appendingPathComponent("frames.dcm")
        var bytes = DICOMPart10Header.encodeMetaInformation(sopClassUID: "1.2.840.10008.5.1.4.1.1.7", sopInstanceUID: "1.2.3.4", transferSyntaxUID: TransferSyntax.explicitVRLittleEndian, sourceAETitle: "TEST")
        bytes.append(try DICOMDataSetCoding.encode(ds, transferSyntax: TransferSyntax.explicitVRLittleEndian))
        try bytes.write(to: file)
        let item = try DICOMRetrieveItem(file: file)
        let lazy = try DICOMwebTranscoding.dataSet(item)
        let pixels = try XCTUnwrap(lazy.element(forTagName: "PixelData"))
        XCTAssertNotNil(pixels.bulkDataReference)
        XCTAssertFalse(pixels.isDataLoaded)
        XCTAssertEqual(try DICOMNativePixelData(dataset: lazy).frameData(1), Data([4, 5, 6, 7]))
        XCTAssertFalse(pixels.isDataLoaded, "A frame read must not load all frames")
        let header = try DICOMPart10Header.read(file)
        let slice = DICOMDataSetPayload(file: file, offset: header.dataSetOffset + 1, length: header.dataSetLength - 1)
        XCTAssertNil(slice.part10File(transferSyntax: item.transferSyntaxUID))
    }
}
