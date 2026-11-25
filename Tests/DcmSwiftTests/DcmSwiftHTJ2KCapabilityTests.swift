import XCTest
@testable import DcmSwift

/// The HTJ2K capability switch: while disabled, HTJ2K is neither
/// decoded, encoded, rendered, nor transcoded, and no call reaches OpenJPEG
/// or OpenJPH for it; Pixel Data stays preserved as encoded.
final class DcmSwiftHTJ2KCapabilityTests: XCTestCase {
    private static let htj2kImageSyntaxes = [
        DICOMJPEG2000Codec.htj2kLossless, DICOMJPEG2000Codec.htj2kLosslessRPCL, DICOMJPEG2000Codec.htj2k,
    ]

    private var htj2kWasEnabled = false

    override func setUp() {
        super.setUp()
        htj2kWasEnabled = DICOMCapabilities.isHTJ2KEnabled
        DICOMCapabilities.isHTJ2KEnabled = false
    }

    override func tearDown() {
        DICOMCapabilities.isHTJ2KEnabled = htj2kWasEnabled
        super.tearDown()
    }

    private func resource(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "jpeg2000-\(name)", withExtension: "j2k")))
    }

    private func description(
        rows: Int, columns: Int, samples: Int = 1, bits: Int = 8,
        photometric: DICOMPhotometricInterpretation = .monochrome2, encapsulated: Bool = true
    ) -> DICOMPixelDescription {
        DICOMPixelDescription(
            rows: rows, columns: columns, samplesPerPixel: samples, photometricInterpretation: photometric,
            bitsAllocated: bits > 8 ? 16 : 8, bitsStored: bits, highBit: bits - 1, isSigned: false,
            planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: encapsulated)
    }

    /// A 4x4 8-bit codestream whose single tile holds invalid data, with HT
    /// code-blocks selected by the main COD, a main COC, or a tile-part COD.
    private func forgedCodestream(htIn location: String) -> Data {
        func u16(_ value: Int) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 0xFF)] }
        func u32(_ value: Int) -> [UInt8] { u16(value >> 16) + u16(value & 0xFFFF) }
        func cod(_ style: UInt8) -> [UInt8] {
            var bytes: [UInt8] = [0xFF, 0x52]
            bytes += u16(12)
            bytes += [0, 0]
            bytes += u16(1)
            bytes += [0, 0, 4, 4, style, 1]
            return bytes
        }
        // SIZ: 4x4 image and tile at the origin, one unsigned 8-bit component.
        var siz: [UInt8] = [0xFF, 0x51]
        siz += u16(41)
        siz += u16(0)
        for value in [4, 4, 0, 0, 4, 4, 0, 0] { siz += u32(value) }
        siz += u16(1)
        siz += [7, 1, 1]
        var coc: [UInt8] = [0xFF, 0x53]
        coc += u16(9)
        coc += [0, 0, 0, 4, 4, 0x40, 1]
        var qcd: [UInt8] = [0xFF, 0x5C]
        qcd += u16(4)
        qcd += [0x20, 0x40]
        let tileHeader: [UInt8] = location == "tile" ? cod(0x40) : []
        let data: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0x12, 0x34]
        var sot: [UInt8] = [0xFF, 0x90]
        sot += u16(10)
        sot += u16(0)
        sot += u32(12 + tileHeader.count + 2 + data.count)
        sot += [0, 1]
        var bytes: [UInt8] = [0xFF, 0x4F]
        bytes += siz
        bytes += cod(location == "main" ? 0x40 : 0)
        if location == "coc" { bytes += coc }
        bytes += qcd
        bytes += sot
        bytes += tileHeader
        bytes += [0xFF, 0x93]
        bytes += data
        bytes += [0xFF, 0xD9]
        return Data(bytes)
    }

    private func encapsulatedImage(_ frame: Data, rows: Int, columns: Int, transferSyntax: String) -> DataSet {
        let dataset = DataSet()
        dataset.transferSyntax = TransferSyntax(transferSyntax)
        _ = dataset.set(value: "1.2.840.10008.5.1.4.1.1.7", forTagName: "SOPClassUID")
        _ = dataset.set(value: "1.2.826.0.1.3680043.10.999.1", forTagName: "SOPInstanceUID")
        _ = dataset.set(value: UInt16(rows), forTagName: "Rows")
        _ = dataset.set(value: UInt16(columns), forTagName: "Columns")
        _ = dataset.set(value: UInt16(1), forTagName: "SamplesPerPixel")
        _ = dataset.set(value: "MONOCHROME2", forTagName: "PhotometricInterpretation")
        _ = dataset.set(value: UInt16(8), forTagName: "BitsAllocated")
        _ = dataset.set(value: UInt16(8), forTagName: "BitsStored")
        _ = dataset.set(value: UInt16(7), forTagName: "HighBit")
        _ = dataset.set(value: UInt16(0), forTagName: "PixelRepresentation")
        let sequence = PixelSequence(withTag: DataTag(withGroup: "7fe0", element: "0010"))
        sequence.vr = .OB
        sequence.length = -1
        for value in [Data(), frame.count % 2 == 1 ? frame + Data([0]) : frame] {
            let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
            item.data = value
            item.length = value.count
            sequence.items.append(item)
        }
        dataset.add(element: sequence)
        return dataset
    }

    private func assertUnsupported(
        _ expression: @autoclosure () throws -> some Any, _ uid: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) {
            XCTAssertEqual($0 as? DICOMCodecError, .unsupportedTransferSyntax(uid), "\($0)", file: file, line: line)
        }
    }

    // MARK: Capabilities

    func testHTJ2KIsDisabledByDefaultAndPreservedOnly() throws {
        // The switch starts at its single default.
        XCTAssertEqual(htj2kWasEnabled, DICOMCapabilities.isHTJ2KEnabledByDefault)
        XCTAssertEqual(DICOMCapabilities.htj2kTransferSyntaxUIDs, Set(Self.htj2kImageSyntaxes + [
            TransferSyntax.jpipHTJ2KReferenced, TransferSyntax.jpipHTJ2KReferencedDeflate,
        ]))
        for uid in DICOMCapabilities.htj2kTransferSyntaxUIDs {
            let capability = DICOMCapabilities.transferSyntax(uid)
            XCTAssertFalse(capability.canDecodePixelData, uid)
            XCTAssertFalse(capability.canEncodePixelData, uid)
            XCTAssertTrue(capability.canReadDataset, uid)
            XCTAssertTrue(capability.canWriteDataset, uid)
            XCTAssertTrue(capability.canPreservePixelData, uid)
            // Data sets are still exchanged as encoded over DIMSE.
            XCTAssertEqual(capability.canNegotiateForDIMSE, DICOMTransferSyntaxes.storage.contains(uid), uid)
            XCTAssertNil(DICOMCodecRegistry.decoder(for: uid), uid)
        }

        DICOMCapabilities.isHTJ2KEnabled = true
        for uid in Self.htj2kImageSyntaxes {
            let capability = DICOMCapabilities.transferSyntax(uid)
            XCTAssertTrue(capability.canDecodePixelData, uid)
            XCTAssertTrue(capability.canEncodePixelData, uid)
            XCTAssertTrue(DICOMCodecRegistry.decoder(for: uid) is DICOMJPEG2000Codec, uid)
        }
    }

    func testOtherCodecsAreUnchanged() throws {
        for uid in [DICOMJPEG2000Codec.lossless, DICOMJPEG2000Codec.lossy, DICOMJPEG2000Codec.partTwoLossless,
                    DICOMJPEG2000Codec.partTwo, DICOMJPEGLSCodec.lossless, DICOMJPEGLSCodec.nearLossless,
                    DICOMJPEGXLCodec.lossless, DICOMJPEGXLCodec.general, DICOMRLECodec.transferSyntaxUID,
                    DICOMJPEGBaselineCodec.baseline, DICOMJPEGLosslessCodec.firstOrderPrediction] {
            let capability = DICOMCapabilities.transferSyntax(uid)
            XCTAssertTrue(capability.canDecodePixelData, uid)
            XCTAssertTrue(capability.canEncodePixelData, uid)
            XCTAssertNotNil(DICOMCodecRegistry.decoder(for: uid), uid)
        }
        // JPEG 2000 Part 1, in a JP2 file, still decodes.
        let decoded = try DICOMJPEG2000Codec().decode(
            try resource("jp2_rgb8_padded"), description: description(rows: 20, columns: 24, samples: 3, photometric: .rgb))
        XCTAssertEqual(decoded.data.count, 20 * 24 * 3)
        // And encodes.
        let native = description(rows: 4, columns: 4, encapsulated: false)
        let (data, _) = try DICOMJPEG2000Codec().encode(Data((0..<16).map { UInt8($0 * 16) }), description: native)
        XCTAssertEqual(try DICOMJPEG2000Codec().decode(data, description: description(rows: 4, columns: 4)).data,
                       Data((0..<16).map { UInt8($0 * 16) }))
    }

    func testTheSwitchIsSafeAcrossThreads() {
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            DICOMCapabilities.isHTJ2KEnabled = index % 2 == 0
            _ = DICOMCapabilities.transferSyntax(DICOMJPEG2000Codec.htj2k)
        }
        DICOMCapabilities.isHTJ2KEnabled = false
        XCTAssertFalse(DICOMCapabilities.transferSyntax(DICOMJPEG2000Codec.htj2k).canDecodePixelData)
    }

    // MARK: Codec

    func testDecoderRefusesHTCodeBlocksBeforeOpenJPEG() throws {
        let codec = DICOMJPEG2000Codec()
        // A valid HTJ2K codestream.
        let gray = description(rows: 29, columns: 37)
        assertUnsupported(try codec.decode(try resource("ht_gray8"), description: gray), DICOMJPEG2000Codec.htj2k)
        assertUnsupported(try codec.decodeCollection(try resource("ht_gray8"), description: gray),
                          DICOMJPEG2000Codec.htj2k)
        // Invalid tile data: OpenJPEG would report a decoding error, the
        // capability check answers first, whichever segment selects HT.
        let small = description(rows: 4, columns: 4)
        for location in ["main", "coc", "tile"] {
            assertUnsupported(try codec.decode(forgedCodestream(htIn: location), description: small),
                              DICOMJPEG2000Codec.htj2k)
        }
        // Without HT code-blocks, the codestream reaches OpenJPEG.
        XCTAssertThrowsError(try codec.decode(forgedCodestream(htIn: "none"), description: small)) {
            XCTAssertNotEqual($0 as? DICOMCodecError, .unsupportedTransferSyntax(DICOMJPEG2000Codec.htj2k))
        }

        DICOMCapabilities.isHTJ2KEnabled = true
        XCTAssertEqual(try codec.decode(try resource("ht_gray8"), description: gray).data.count, 29 * 37)
        XCTAssertThrowsError(try codec.decode(forgedCodestream(htIn: "main"), description: small)) {
            XCTAssertNotEqual($0 as? DICOMCodecError, .unsupportedTransferSyntax(DICOMJPEG2000Codec.htj2k))
        }
    }

    func testEncoderRefusesHTJ2KBeforeOpenJPH() throws {
        let codec = DICOMJPEG2000Codec()
        let native = description(rows: 4, columns: 4, encapsulated: false)
        let frame = Data(repeating: 7, count: 16)
        for mode in [DICOMJPEG2000Codec.HTJ2KMode.lossless, .losslessRPCL, .irreversible(quantizationStep: 0.01)] {
            assertUnsupported(try codec.encodeHTJ2K(frame, description: native, mode: mode), mode.transferSyntaxUID)
        }
        // The check precedes the parameter checks.
        assertUnsupported(try codec.encodeHTJ2K(frame, description: native, mode: .irreversible(quantizationStep: 0)),
                          DICOMJPEG2000Codec.htj2k)

        DICOMCapabilities.isHTJ2KEnabled = true
        let (data, _) = try codec.encodeHTJ2K(frame, description: native)
        XCTAssertEqual(try codec.decode(data, description: description(rows: 4, columns: 4)).data, frame)
    }

    // MARK: Rendering, transcoding, and preservation

    func testHTJ2KInstancesArePreservedButNotDecoded() throws {
        let stream = try resource("ht_gray8")
        let uid = DICOMJPEG2000Codec.htj2kLossless
        let dataset = encapsulatedImage(stream, rows: 29, columns: 37, transferSyntax: uid)

        let encapsulated = try DICOMEncapsulatedPixelData(dataset: dataset)
        XCTAssertEqual(try encapsulated.encodedFrame(0).prefix(stream.count), stream)
        XCTAssertThrowsError(try encapsulated.decodedFrame(0)) {
            XCTAssertEqual($0 as? DICOMPixelDataError, .encapsulatedPixelData(transferSyntax: uid))
        }
        XCTAssertThrowsError(try DICOMImageRenderer(dataset: dataset)) {
            XCTAssertEqual($0 as? DICOMPixelDataError, .encapsulatedPixelData(transferSyntax: uid))
        }

        // DICOMweb returns the instance and its frames as stored only.
        let payload = DICOMDataSetPayload(data: try DICOMDataSetCoding.encode(dataset, transferSyntax: uid))
        let item = DICOMRetrieveItem(sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
                                     sopInstanceUID: "1.2.826.0.1.3680043.10.999.1",
                                     transferSyntaxUID: uid, payload: payload)
        XCTAssertEqual(DICOMwebTranscoding.availableTransferSyntaxes(of: item), [uid])
        XCTAssertFalse(DICOMwebTranscoding.losslessEncapsulated.contains(uid))
        XCTAssertEqual(try DICOMwebTranscoding.payload(item, in: uid).data(), try payload.data())
        XCTAssertThrowsError(try DICOMwebTranscoding.payload(item, in: TransferSyntax.explicitVRLittleEndian))
        XCTAssertEqual(DICOMwebMediaType.compressedBulkData(for: uid)?.essence, "image/jphc")
        let stored = try DICOMwebTranscoding.dataSet(item)
        XCTAssertEqual(try DICOMwebTranscoding.frames(stored, numbers: [1], compressed: true)[0].prefix(stream.count),
                       stream)
        XCTAssertThrowsError(try DICOMwebTranscoding.frames(stored, numbers: [1], compressed: false))

        DICOMCapabilities.isHTJ2KEnabled = true
        XCTAssertEqual(try DICOMImageRenderer(dataset: dataset).storedValues().count, 29 * 37)
        XCTAssertEqual(DICOMwebTranscoding.availableTransferSyntaxes(of: item), [uid, TransferSyntax.explicitVRLittleEndian])
        let decompressed = try DICOMDataSetCoding.decode(
            try DICOMwebTranscoding.payload(item, in: TransferSyntax.explicitVRLittleEndian).data(),
            transferSyntax: TransferSyntax.explicitVRLittleEndian)
        XCTAssertEqual(decompressed.element(forTagName: "PixelData")?.data?.count, 29 * 37 + 1)
    }

    func testJPIPHTJ2KIsNeitherResolvedNorDecoded() async throws {
        for uid in [TransferSyntax.jpipHTJ2KReferenced, TransferSyntax.jpipHTJ2KReferencedDeflate] {
            let dataset = DataSet()
            dataset.transferSyntax = TransferSyntax(uid)
            _ = dataset.set(value: UInt16(4), forTagName: "Rows")
            _ = dataset.set(value: UInt16(4), forTagName: "Columns")
            // Refused before any request: the provider URL is not even read.
            do {
                _ = try await DICOMJPIPClient().resolve(dataset)
                XCTFail("resolved \(uid)")
            } catch {
                XCTAssertEqual(error as? DICOMCodecError, .unsupportedTransferSyntax(uid))
            }
            let frame = description(rows: 4, columns: 4)
            XCTAssertThrowsError(try DICOMJPIPClient.decoder(for: dataset, description: frame)) {
                XCTAssertEqual($0 as? DICOMCodecError, .unsupportedTransferSyntax(DICOMJPEG2000Codec.htj2k))
            }
        }
    }
}
