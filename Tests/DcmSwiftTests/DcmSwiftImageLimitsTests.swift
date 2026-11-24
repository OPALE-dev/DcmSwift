import XCTest
@testable import DcmSwift

/// Images whose attributes or encoded streams declare extreme dimensions are
/// refused before memory proportional to those dimensions is allocated.
final class DcmSwiftImageLimitsTests: XCTestCase {
    private let extremePixels = 65535 * 65535

    // MARK: Data Set attributes

    func testExtremeRLEImageIsRefusedBeforeDecoding() throws {
        // A few bytes of RLE declaring 65535 x 65535 pixels: replicate runs
        // would expand them to 4 GiB.
        let dataset = encapsulatedImage(
            rows: 65535, columns: 65535, fragment: rleFrame([[0x81, 0x00, 0x81, 0x00]]))
        XCTAssertThrowsError(try DICOMEncapsulatedPixelData(dataset: dataset)) {
            XCTAssertEqual($0 as? DICOMPixelDataError,
                           .limitExceeded("pixels per frame", value: extremePixels, limit: 268_435_456))
        }
        XCTAssertThrowsError(try DICOMImageRenderer(dataset: dataset)) {
            XCTAssertEqual($0 as? DICOMPixelDataError,
                           .limitExceeded("pixels per frame", value: extremePixels, limit: 268_435_456))
        }

        // With the pixel count allowed, the frame buffer is still bounded,
        // and the codec checks the description it is handed.
        let limits = DICOMImageLimits(maximumPixelsPerFrame: .max, maximumFrameBytes: 1 << 20)
        XCTAssertThrowsError(try DICOMImageRenderer(dataset: dataset, limits: limits)) {
            XCTAssertEqual($0 as? DICOMPixelDataError,
                           .limitExceeded("bytes per frame", value: extremePixels, limit: 1 << 20))
        }
        let unchecked = DICOMPixelDescription(
            rows: 65535, columns: 65535, samplesPerPixel: 1, photometricInterpretation: .monochrome2,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false, planarConfiguration: 0,
            numberOfFrames: 1)
        XCTAssertThrowsError(try DICOMRLECodec().decode(rleFrame([[0x81, 0x00]]), description: unchecked)) {
            XCTAssertEqual($0 as? DICOMPixelDataError,
                           .limitExceeded("pixels per frame", value: extremePixels, limit: 268_435_456))
        }
        XCTAssertThrowsError(try DICOMDeflatedFrameCodec().decode(Data([0x03, 0x00]), description: unchecked)) {
            XCTAssertEqual($0 as? DICOMPixelDataError,
                           .limitExceeded("pixels per frame", value: extremePixels, limit: 268_435_456))
        }
    }

    func testNumberOfFramesIsBoundedAndNeverOverflows() throws {
        let dataset = nativeImage(rows: 2, columns: 2, frames: "999999999999")
        XCTAssertThrowsError(try DICOMNativePixelData(dataset: dataset)) {
            XCTAssertEqual($0 as? DICOMPixelDataError,
                           .limitExceeded("NumberOfFrames", value: 999_999_999_999, limit: 1_000_000))
        }
        // Raised limits never let the Pixel Data size overflow.
        let limits = DICOMImageLimits(maximumNumberOfFrames: .max)
        let huge = nativeImage(rows: 65535, columns: 65535, bitsAllocated: 32, frames: "999999999999")
        XCTAssertThrowsError(try DICOMNativePixelData(
            dataset: huge, limits: DICOMImageLimits(maximumPixelsPerFrame: .max, maximumFrameBytes: .max,
                                                    maximumNumberOfFrames: .max))) {
            XCTAssertEqual($0 as? DICOMPixelDataError,
                           .invalidAttribute("NumberOfFrames", "the declared Pixel Data size overflows"))
        }
        XCTAssertThrowsError(try DICOMNativePixelData(dataset: dataset, limits: limits)) {
            XCTAssertEqual($0 as? DICOMPixelDataError, .truncatedPixelData(expectedBytes: 3_999_999_999_996, actualBytes: 4))
        }
    }

    func testWorkingBuffersAndRenderedImagesAreBounded() throws {
        // 64 x 64 one-bit pixels take 512 bytes of Pixel Data but 32 KiB of
        // stored values.
        let dataset = nativeImage(rows: 64, columns: 64, bitsAllocated: 1, pixelBytes: 512)
        let limits = DICOMImageLimits(maximumFrameBytes: 8192)
        let pixels = try DICOMNativePixelData(dataset: dataset, limits: limits)
        XCTAssertThrowsError(try pixels.storedValues(frame: 0)) {
            XCTAssertEqual($0 as? DICOMPixelDataError, .limitExceeded("bytes per frame", value: 32768, limit: 8192))
        }
        XCTAssertEqual(try DICOMNativePixelData(dataset: dataset).storedValues(frame: 0).count, 4096)
        XCTAssertEqual(try DICOMImageRenderer(dataset: dataset).render().pixels.count, 4096)
    }

    func testDefaultsAdmitLargeClinicalImages() throws {
        // Digital mammography, 16 bits, and a large RGB frame.
        XCTAssertNoThrow(try DICOMImageLimits().checkFrame(
            rows: 5355, columns: 4915, samplesPerPixel: 1, bytesPerSample: 8))
        XCTAssertNoThrow(try DICOMImageLimits().checkFrame(
            rows: 8192, columns: 8192, samplesPerPixel: 3, bytesPerSample: 8))
        XCTAssertNoThrow(try DICOMPixelDescription(dataset: nativeImage(
            rows: 16384, columns: 16384, bitsAllocated: 16, frames: "1000", pixelBytes: 0)))
        XCTAssertThrowsError(try DICOMImageLimits().checkFrame(
            rows: 65535, columns: 65535, samplesPerPixel: 3, bytesPerSample: .max)) {
            XCTAssertEqual($0 as? DICOMPixelDataError,
                           .limitExceeded("pixels per frame", value: self.extremePixels, limit: 268_435_456))
        }
        XCTAssertThrowsError(try DICOMImageLimits(maximumPixelsPerFrame: .max).checkFrame(
            rows: 65535, columns: 65535, samplesPerPixel: 3, bytesPerSample: .max)) {
            XCTAssertEqual($0 as? DICOMPixelDataError,
                           .limitExceeded("bytes per frame", value: .max, limit: 2_147_483_648))
            XCTAssertEqual(($0 as? DICOMPixelDataError)?.description,
                           "Image declares an overflowing number of bytes per frame, above the limit of 2147483648")
        }
    }

    func testRendererRefusesDecodedFramesOfAnotherSize() throws {
        struct OversizedDecoder: DICOMPixelDataDecoder {
            var transferSyntaxUIDs: Set<String> { ["1.2.840.10008.1.2.4.108"] }
            func decode(_ encodedFrame: Data, description: DICOMPixelDescription) throws -> DICOMDecodedFrame {
                let frame = DICOMPixelDescription(
                    rows: 4, columns: 4, samplesPerPixel: 1, photometricInterpretation: .monochrome2,
                    bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false, planarConfiguration: 0,
                    numberOfFrames: 1)
                return DICOMDecodedFrame(description: frame, data: Data(repeating: 1, count: 16))
            }
        }
        DICOMCodecRegistry.register(OversizedDecoder())
        let dataset = encapsulatedImage(
            rows: 1, columns: 2, fragment: Data([0, 0]), transferSyntax: "1.2.840.10008.1.2.4.108")
        XCTAssertThrowsError(try DICOMImageRenderer(dataset: dataset).render()) {
            XCTAssertEqual($0 as? DICOMCodecError, .corruptedData("decoded frame is 4x4, image is 2x1"))
        }
    }

    // MARK: Encoded streams

    func testJPEGStreamDimensionsAreCheckedBeforeDecoding() throws {
        let native = frameDescription(rows: 8, columns: 8)
        var jpeg = [UInt8](try DICOMJPEGBaselineCodec().encode(Data(repeating: 128, count: 64), description: native).data)
        let sof = try XCTUnwrap(markerOffset(0xC0, in: jpeg) ?? markerOffset(0xC1, in: jpeg))
        setUInt16(65535, at: sof + 5, in: &jpeg)
        setUInt16(65535, at: sof + 7, in: &jpeg)
        XCTAssertThrowsError(try DICOMJPEGBaselineCodec().decode(Data(jpeg), description: native)) {
            XCTAssertEqual($0 as? DICOMPixelDataError,
                           .limitExceeded("pixels per frame", value: self.extremePixels, limit: 268_435_456))
        }

        let lossless = frameDescription(rows: 8, columns: 8, bitsAllocated: 16, bitsStored: 12)
        var stream = [UInt8](try DICOMJPEGLosslessCodec().encode(
            Data(repeating: 1, count: 128), description: lossless))
        let sof3 = try XCTUnwrap(markerOffset(0xC3, in: stream))
        setUInt16(65535, at: sof3 + 5, in: &stream)
        setUInt16(65535, at: sof3 + 7, in: &stream)
        XCTAssertThrowsError(try DICOMJPEGLosslessCodec().decode(Data(stream), description: lossless)) {
            XCTAssertEqual($0 as? DICOMPixelDataError,
                           .limitExceeded("pixels per frame", value: self.extremePixels, limit: 268_435_456))
        }
    }

    func testJPEGLSStreamDimensionsAreCheckedBeforeDecoding() throws {
        let native = frameDescription(rows: 8, columns: 8)
        var stream = [UInt8](try DICOMJPEGLSCodec().encode(Data(repeating: 7, count: 64), description: native))
        let sof = try XCTUnwrap(markerOffset(0xF7, in: stream))
        setUInt16(65535, at: sof + 5, in: &stream)
        setUInt16(65535, at: sof + 7, in: &stream)
        XCTAssertThrowsError(try DICOMJPEGLSCodec().decode(Data(stream), description: native)) {
            XCTAssertEqual($0 as? DICOMPixelDataError,
                           .limitExceeded("pixels per frame", value: self.extremePixels, limit: 268_435_456))
        }
    }

    func testJPEG2000SizeIsCheckedBeforeOpenJPEGAllocates() throws {
        let native = frameDescription(rows: 8, columns: 8)
        let encoded = [UInt8](try DICOMJPEG2000Codec().encode(Data(repeating: 9, count: 64), description: native).data)
        XCTAssertEqual(try DICOMJPEG2000Codec().decode(Data(encoded), description: native).data.count, 64)

        // SIZ: Xsiz at byte 8 and Ysiz at byte 12 of a raw codestream.
        var extreme = encoded
        setUInt32(65535, at: 8, in: &extreme)
        setUInt32(65535, at: 12, in: &extreme)
        XCTAssertThrowsError(try DICOMJPEG2000Codec().decode(Data(extreme), description: native)) {
            XCTAssertEqual($0 as? DICOMPixelDataError,
                           .limitExceeded("pixels per frame", value: self.extremePixels, limit: 268_435_456))
        }

        // Within the limits but larger than the image: refused before decoding.
        var larger = encoded
        setUInt32(4096, at: 8, in: &larger)
        setUInt32(4096, at: 12, in: &larger)
        XCTAssertThrowsError(try DICOMJPEG2000Codec().decode(Data(larger), description: native)) {
            XCTAssertEqual($0 as? DICOMCodecError, .corruptedData("JPEG 2000 image is 4096x4096, image is 8x8"))
        }
        XCTAssertThrowsError(try DICOMJPEG2000Codec().decode(Data(encoded.prefix(20)), description: native)) {
            XCTAssertEqual($0 as? DICOMCodecError,
                           .corruptedData("JPEG 2000 data has no SIZ marker segment after SOC"))
        }
    }

    // MARK: Fixtures

    private func frameDescription(
        rows: Int, columns: Int, bitsAllocated: Int = 8, bitsStored: Int = 8
    ) -> DICOMPixelDescription {
        DICOMPixelDescription(
            rows: rows, columns: columns, samplesPerPixel: 1, photometricInterpretation: .monochrome2,
            bitsAllocated: bitsAllocated, bitsStored: bitsStored, highBit: bitsStored - 1, isSigned: false,
            planarConfiguration: 0, numberOfFrames: 1)
    }

    private func markerOffset(_ marker: UInt8, in bytes: [UInt8]) -> Int? {
        (0..<(bytes.count - 1)).first { bytes[$0] == 0xFF && bytes[$0 + 1] == marker }
    }

    private func setUInt16(_ value: Int, at offset: Int, in bytes: inout [UInt8]) {
        bytes[offset] = UInt8(value >> 8)
        bytes[offset + 1] = UInt8(value & 0xFF)
    }

    private func setUInt32(_ value: Int, at offset: Int, in bytes: inout [UInt8]) {
        for index in 0..<4 { bytes[offset + index] = UInt8((value >> (8 * (3 - index))) & 0xFF) }
    }

    private func setPixelModule(
        _ dataset: DataSet, rows: Int, columns: Int, bitsAllocated: Int, frames: String?
    ) {
        _ = dataset.set(value: UInt16(rows), forTagName: "Rows")
        _ = dataset.set(value: UInt16(columns), forTagName: "Columns")
        _ = dataset.set(value: UInt16(1), forTagName: "SamplesPerPixel")
        _ = dataset.set(value: "MONOCHROME2", forTagName: "PhotometricInterpretation")
        _ = dataset.set(value: UInt16(bitsAllocated), forTagName: "BitsAllocated")
        _ = dataset.set(value: UInt16(bitsAllocated), forTagName: "BitsStored")
        _ = dataset.set(value: UInt16(bitsAllocated - 1), forTagName: "HighBit")
        _ = dataset.set(value: UInt16(0), forTagName: "PixelRepresentation")
        if let frames { _ = dataset.set(value: frames, forTagName: "NumberOfFrames") }
    }

    private func nativeImage(
        rows: Int, columns: Int, bitsAllocated: Int = 8, frames: String? = nil, pixelBytes: Int = 4
    ) -> DataSet {
        let dataset = DataSet()
        dataset.transferSyntax = TransferSyntax(TransferSyntax.explicitVRLittleEndian)
        setPixelModule(dataset, rows: rows, columns: columns, bitsAllocated: bitsAllocated, frames: frames)
        let element = DataElement(withTagName: "PixelData", dataset: dataset)!
        element.vr = .OB
        element.data = Data((0..<pixelBytes).map { UInt8(truncatingIfNeeded: $0 &* 37) })
        element.length = pixelBytes
        dataset.add(element: element)
        return dataset
    }

    private func encapsulatedImage(
        rows: Int, columns: Int, fragment: Data, transferSyntax: String = DICOMRLECodec.transferSyntaxUID
    ) -> DataSet {
        let dataset = DataSet()
        dataset.transferSyntax = TransferSyntax(transferSyntax)
        setPixelModule(dataset, rows: rows, columns: columns, bitsAllocated: 8, frames: "1")
        let sequence = PixelSequence(withTag: DataTag(withGroup: "7fe0", element: "0010"))
        sequence.vr = .OB
        sequence.length = -1
        for value in [Data(), fragment] {
            let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
            item.data = value
            item.length = value.count
            sequence.items.append(item)
        }
        dataset.add(element: sequence)
        return dataset
    }

    private func rleFrame(_ segments: [[UInt8]]) -> Data {
        var header = [UInt8](repeating: 0, count: 64)
        func put(_ value: Int, at offset: Int) {
            for byte in 0..<4 { header[offset + byte] = UInt8((value >> (8 * byte)) & 0xFF) }
        }
        put(segments.count, at: 0)
        var offset = 64
        for (index, segment) in segments.enumerated() {
            put(offset, at: 4 * (index + 1))
            offset += segment.count
        }
        return Data(header + segments.flatMap { $0 })
    }
}
