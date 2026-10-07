import CZlib
import XCTest
#if canImport(ImageIO)
import ImageIO
#endif
@testable import DcmSwift

/// Native Pixel Data decoding and the grayscale and color pipelines, checked
/// against values derived by hand from PS3.3 C.7.6.3, C.7.9.2, C.11.1,
/// C.11.2 and PS3.5 8.1.1.
final class DcmSwiftImagingTests: XCTestCase {

    // MARK: Stored values (PS3.5 8.1.1)

    func testStoredValuesIgnoreUnusedBitsAndSignExtend() throws {
        // Unused high bits may hold anything; they are not sign extension.
        let unsigned = makeImage(columns: 2, bitsAllocated: 16, bitsStored: 12, pixelData: words([0xF123, 0x0FFF]))
        XCTAssertEqual(try DICOMNativePixelData(dataset: unsigned).storedValues(frame: 0), [0x123, 0xFFF])

        let signed = makeImage(columns: 3, bitsAllocated: 16, bitsStored: 12, signed: true,
                               pixelData: words([0xF800, 0x07FF, 0xAFFF, 0]))
        XCTAssertEqual(try DICOMNativePixelData(dataset: signed).storedValues(frame: 0), [-2048, 2047, -1])
    }

    func testLegacyHighBitAboveBitsStored() throws {
        // Earlier editions allowed the stored bits anywhere below High Bit.
        let image = makeImage(columns: 2, bitsAllocated: 16, bitsStored: 12, highBit: 15,
                              pixelData: words([0xABC5, 0x0010]))
        XCTAssertEqual(try DICOMNativePixelData(dataset: image).storedValues(frame: 0), [0xABC, 0x001])
    }

    func testOneBitFramesAreNotPaddedAndMayStartInsideAByte() throws {
        // Two 3x3 frames: 18 bits, packed from the least significant bit.
        let frame0: [UInt8] = [1, 0, 1, 0, 1, 0, 1, 0, 1]
        let frame1: [UInt8] = [0, 1, 1, 0, 0, 1, 1, 1, 0]
        var bytes = [UInt8](repeating: 0, count: 4)
        for (index, bit) in (frame0 + frame1).enumerated() where bit == 1 {
            bytes[index / 8] |= 1 << (index % 8)
        }
        let image = makeImage(rows: 3, columns: 3, bitsAllocated: 1, bitsStored: 1, frames: 2, pixelData: Data(bytes))
        let pixels = try DICOMNativePixelData(dataset: image)
        XCTAssertEqual(try pixels.storedValues(frame: 0), frame0.map(Int64.init))
        XCTAssertEqual(try pixels.storedValues(frame: 1), frame1.map(Int64.init))
    }

    func testThirtyTwoBitUnsignedValuesKeepTheirFullRange() throws {
        let image = makeImage(columns: 1, bitsAllocated: 32, bitsStored: 32, pixelData: Data([0xFF, 0xFF, 0xFF, 0xFF]))
        XCTAssertEqual(try DICOMNativePixelData(dataset: image).storedValues(frame: 0), [4_294_967_295])
    }

    func testPlanarConfigurationOneIsReturnedPixelByPixel() throws {
        let image = makeImage(columns: 2, samples: 3, photometric: "RGB", planar: 1,
                              pixelData: Data([10, 11, 20, 21, 30, 31]))
        XCTAssertEqual(try DICOMNativePixelData(dataset: image).storedValues(frame: 0), [10, 20, 30, 11, 21, 31])
    }

    func testYBRFull422SharesChromaBetweenPixelPairs() throws {
        let image = makeImage(columns: 2, samples: 3, photometric: "YBR_FULL_422", pixelData: Data([10, 20, 30, 40]))
        XCTAssertEqual(try DICOMNativePixelData(dataset: image).storedValues(frame: 0), [10, 30, 40, 20, 30, 40])
    }

    func testBigEndianPixelDataIsNormalized() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: url) }

        for (bitsAllocated, pixelData, expected) in [
            (16, words([0x0102, 0xFFFE]), [Int64(0x0102), 0xFFFE]),
            (8, Data([1, 2, 3, 4]), [Int64(1), 2, 3, 4]),
        ] {
            let source = makeImage(columns: pixelData.count * 8 / bitsAllocated, bitsAllocated: bitsAllocated,
                                   bitsStored: bitsAllocated, pixelData: pixelData)
            source.hasPreamble = true
            source.transferSyntax = try XCTUnwrap(TransferSyntax(TransferSyntax.explicitVRBigEndian))
            _ = source.set(value: "1.2.826.0.1.3680043.10.999", forTagName: "ImplementationClassUID")
            XCTAssertTrue(try DicomOutputStream(url: url).write(dataset: source))

            let decoded = try XCTUnwrap(try DicomInputStream(url: url).readDataset())
            XCTAssertEqual(try DICOMNativePixelData(dataset: decoded).storedValues(frame: 0), expected, "\(bitsAllocated)")
        }
    }

    // MARK: Window functions (PS3.3 C.11.2.1.2 and C.11.2.1.3)

    func testLinearWindowMatchesTheNormativeExamples() {
        let full = DICOMWindow(center: 2048, width: 4096)
        XCTAssertEqual(full.apply(0), 0)
        XCTAssertEqual(full.apply(4096), 255)
        XCTAssertEqual(full.apply(2048), (0.5 / 4095 + 0.5) * 255, accuracy: 1e-9)

        let threshold = DICOMWindow(center: 2048, width: 1)
        XCTAssertEqual(threshold.apply(2047), 0)
        XCTAssertEqual(threshold.apply(2048), 255)

        let narrow = DICOMWindow(center: 0, width: 100)
        XCTAssertEqual(narrow.apply(-50), 0)
        XCTAssertEqual(narrow.apply(50), 255)
        XCTAssertEqual(narrow.apply(0), (0.5 / 99 + 0.5) * 255, accuracy: 1e-9)

        let zero = DICOMWindow(center: 0, width: 1)
        XCTAssertEqual(zero.apply(-1), 0)
        XCTAssertEqual(zero.apply(0), 255)
    }

    func testSigmoidAndLinearExactFunctions() {
        let sigmoid = DICOMWindow(center: 0, width: 4, function: .sigmoid)
        XCTAssertEqual(sigmoid.apply(0), 127.5, accuracy: 1e-9)
        XCTAssertEqual(sigmoid.apply(4), 255 / (1 + exp(-4)), accuracy: 1e-9)

        let exact = DICOMWindow(center: 0.5, width: 1, function: .linearExact)
        XCTAssertEqual(exact.apply(0), 0)
        XCTAssertEqual(exact.apply(1), 255)
        XCTAssertEqual(exact.apply(0.25), 63.75, accuracy: 1e-9)
    }

    func testLinearExactIdentityExampleThroughThePipeline() throws {
        // PS3.3 C.11.2.1.3.2: 16-bit unsigned values, Rescale Slope 1/65535,
        // Window Center 0.5 and Width 1 select the entire range.
        let image = makeImage(columns: 3, bitsAllocated: 16, bitsStored: 16, pixelData: words([0, 32768, 65535]),
                              extra: ["RescaleSlope": "1.52590219e-05", "RescaleIntercept": "0",
                                      "WindowCenter": "0.5", "WindowWidth": "1", "VOILUTFunction": "LINEAR_EXACT"])
        XCTAssertEqual(try DICOMImageRenderer(dataset: image).render().pixels, [0, 128, 255])
    }

    // MARK: Grayscale pipeline

    func testRescaleThenWindowForCTValues() throws {
        // Stored 0, 1004, 1024, 1224 with intercept -1024 are -1024, -20, 0,
        // 200 HU; a 40/400 window spans -160 to 240.
        let image = makeImage(columns: 4, bitsAllocated: 16, bitsStored: 12, pixelData: words([0, 1004, 1024, 1224]),
                              extra: ["RescaleSlope": "1", "RescaleIntercept": "-1024",
                                      "WindowCenter": "40\\600", "WindowWidth": "400\\1600"])
        let renderer = try DICOMImageRenderer(dataset: image)
        XCTAssertEqual(try renderer.modalityValues(), [-1024, -20, 0, 200])
        XCTAssertEqual(try renderer.windows().count, 2)
        let expected = [-1024.0, -20, 0, 200].map {
            UInt8(min(max(DICOMWindow(center: 40, width: 400).apply($0), 0), 255).rounded())
        }
        XCTAssertEqual(try renderer.render().pixels, expected)
        XCTAssertEqual(expected.first, 0)
    }

    func testIdentityVOIUsesThePossibleRangeAndMonochrome1IsInverted() throws {
        let image = makeImage(columns: 3, photometric: "MONOCHROME1", pixelData: Data([0, 51, 255]))
        let renderer = try DICOMImageRenderer(dataset: image)
        XCTAssertEqual(try renderer.render().pixels, [255, 204, 0])
        XCTAssertEqual(try renderer.render(options: DICOMRenderingOptions(honorsMonochrome1: false)).pixels, [0, 51, 255])
    }

    func testModalityLUTSequence() throws {
        let image = makeImage(columns: 4, bitsAllocated: 16, bitsStored: 12, pixelData: words([5, 11, 12, 99]))
        addLUT(named: "ModalityLUTSequence", descriptor: [4, 10, 16],
               data: words([0, 1000, 2000, 65535]), to: image)
        let renderer = try DICOMImageRenderer(dataset: image)
        // Values below the first mapped use the first entry; above, the last.
        XCTAssertEqual(try renderer.modalityValues(), [0, 1000, 2000, 65535])
        // Identity VOI over the 16-bit LUT output range.
        XCTAssertEqual(try renderer.render().pixels, [0, 4, 8, 255])
    }

    func testVOILUTWithEightBitEntriesEncodedInSixteenBits() throws {
        let image = makeImage(columns: 3, pixelData: Data([0, 1, 2, 0]))
        addLUT(named: "VOILUTSequence", descriptor: [3, 0, 8], data: words([0x0000, 0x0080, 0x00FF]), to: image)
        let renderer = try DICOMImageRenderer(dataset: image)
        XCTAssertEqual(try renderer.render().pixels, [0, 128, 255])
    }

    func testFunctionalGroupsOverrideTopLevelValuesPerFrame() throws {
        let image = makeImage(columns: 1, frames: 2, pixelData: Data([10, 10]),
                              extra: ["RescaleSlope": "5", "WindowCenter": "1", "WindowWidth": "1"])
        addFunctionalGroups(to: image, shared: [
            "PixelValueTransformationSequence": ["RescaleSlope": "2", "RescaleIntercept": "0"],
        ], perFrame: [
            [:],
            ["PixelValueTransformationSequence": ["RescaleSlope": "1", "RescaleIntercept": "100"],
             "FrameVOILUTSequence": ["WindowCenter": "110", "WindowWidth": "21"]],
        ])
        let renderer = try DICOMImageRenderer(dataset: image)
        XCTAssertEqual(try renderer.modalityValues(frame: 0), [20])
        XCTAssertEqual(try renderer.modalityValues(frame: 1), [110])
        XCTAssertEqual(try renderer.windows(frame: 0), [DICOMWindow(center: 1, width: 1)])
        XCTAssertEqual(try renderer.windows(frame: 1), [DICOMWindow(center: 110, width: 21)])
    }

    func testFloatPixelDataUsesTheValueRange() throws {
        var floats = Data()
        for value: Float in [-1.5, 0, 2.5] {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { floats.append(contentsOf: $0) }
        }
        let image = makeImage(columns: 3, bitsAllocated: 32, bitsStored: nil, pixelData: floats,
                              pixelDataKeyword: "FloatPixelData")
        let renderer = try DICOMImageRenderer(dataset: image)
        XCTAssertEqual(renderer.description.sampleFormat, .float32)
        XCTAssertEqual(try renderer.modalityValues(), [-1.5, 0, 2.5])
        XCTAssertEqual(try renderer.render().pixels, [0, 96, 255])
    }

    // MARK: Color (PS3.3 C.7.6.3.1.2, C.7.6.3.1.5, C.7.9.2)

    func testYBRFullConvertsWithCCIR601Coefficients() throws {
        // Pure red is Y 76, CB 85, CR 255 with the C.7.6.3.1.2 equations.
        let image = makeImage(columns: 2, samples: 3, photometric: "YBR_FULL",
                              pixelData: Data([76, 85, 255, 255, 128, 128]))
        let rendered = try DICOMImageRenderer(dataset: image).render()
        XCTAssertEqual(rendered.format, .rgb8)
        XCTAssertEqual(rendered.pixels, [254, 0, 0, 255, 255, 255])
    }

    func testPaletteColorClampsAndScalesSixteenBitEntries() throws {
        let image = makeImage(columns: 4, photometric: "PALETTE COLOR", pixelData: Data([0, 2, 3, 9]))
        for (color, entries) in [("Red", [0x0000, 0xFFFF, 0x8000]), ("Green", [0x1200, 0x3400, 0x5600]),
                                 ("Blue", [0xFF00, 0x0000, 0x00FF])] {
            addElement("\(color)PaletteColorLookupTableDescriptor", vr: .US, value: [UInt16(3), 2, 16], to: image)
            addElement("\(color)PaletteColorLookupTableData", vr: .OW, value: words(entries.map(UInt16.init)), to: image)
        }
        // First value mapped is 2: input 0 uses entry 0, 9 the last entry.
        XCTAssertEqual(try DICOMImageRenderer(dataset: image).render().pixels,
                       [0, 0x12, 0xFF, 0, 0x12, 0xFF, 0xFF, 0x34, 0, 0x80, 0x56, 0])
    }

    func testSegmentedPaletteSegmentsExpand() throws {
        // Discrete 0, 100; linear to 200 over 2 entries; indirect copy of
        // the first segment (byte offset 0).
        let words: [UInt16] = [0, 2, 0, 100, 1, 2, 200, 2, 1, 0, 0]
        XCTAssertEqual(try DICOMLookupTable.expandSegments(words, count: 6, name: "test"),
                       [0, 100, 150, 200, 0, 100])
        XCTAssertThrowsError(try DICOMLookupTable.expandSegments([1, 2, 200], count: 2, name: "test"))
        XCTAssertThrowsError(try DICOMLookupTable.expandSegments([0, 2, 1, 2], count: 3, name: "test"))
        XCTAssertThrowsError(try DICOMLookupTable.expandSegments([3, 1, 0], count: 1, name: "test"))
    }

    // MARK: Errors

    func testInvalidImagesAreReported() throws {
        XCTAssertThrowsError(try DICOMNativePixelData(dataset: makeImage(columns: 4, pixelData: Data([1, 2])))) {
            XCTAssertEqual($0 as? DICOMPixelDataError, .truncatedPixelData(expectedBytes: 4, actualBytes: 2))
        }
        XCTAssertThrowsError(try DICOMPixelDescription(dataset: makeImage(columns: 2, bitsStored: 12, pixelData: Data([1, 2])))) {
            XCTAssertEqual($0 as? DICOMPixelDataError, .invalidAttribute("BitsStored", "12 is not within 1...8"))
        }
        let argb = makeImage(columns: 2, photometric: "ARGB", pixelData: Data([1, 2]))
        XCTAssertThrowsError(try DICOMImageRenderer(dataset: argb).render()) {
            XCTAssertEqual($0 as? DICOMPixelDataError, .unsupportedPhotometricInterpretation("ARGB"))
        }
        let renderer = try DICOMImageRenderer(dataset: makeImage(columns: 2, pixelData: Data([1, 2])))
        XCTAssertThrowsError(try renderer.render(frame: 1)) {
            XCTAssertEqual($0 as? DICOMPixelDataError, .frameOutOfRange(1, numberOfFrames: 1))
        }
        let windows = makeImage(columns: 2, pixelData: Data([1, 2]),
                                extra: ["WindowCenter": "1\\2", "WindowWidth": "10"])
        XCTAssertThrowsError(try DICOMImageRenderer(dataset: windows).render())

        let encapsulated = makeImage(columns: 2, pixelData: Data([1, 2]))
        _ = encapsulated.remove(elementForTagName: "PixelData")
        let sequence = DataSequence(withTag: DataTag(withGroup: "7fe0", element: "0010"))
        sequence.vr = .OB
        encapsulated.add(element: sequence)
        XCTAssertThrowsError(try DICOMNativePixelData(dataset: encapsulated)) {
            guard case .encapsulatedPixelData? = $0 as? DICOMPixelDataError else {
                return XCTFail("\($0)")
            }
        }
    }

    // MARK: PNG

    func testPNGEncodingIsValidAndLossless() throws {
        let image = DICOMRenderedImage(width: 3, height: 2, format: .rgb8, pixels: Array(0..<18).map(UInt8.init))
        let png = [UInt8](try image.pngData())
        XCTAssertEqual(Array(png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        var chunks: [String: [UInt8]] = [:]
        var offset = 8
        while offset < png.count {
            let length = Int(png[offset]) << 24 | Int(png[offset + 1]) << 16 | Int(png[offset + 2]) << 8 | Int(png[offset + 3])
            let type = String(decoding: png[(offset + 4)..<(offset + 8)], as: UTF8.self)
            let payload = Array(png[(offset + 8)..<(offset + 8 + length)])
            let stored = png[(offset + 8 + length)..<(offset + 12 + length)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            let computed = Array(png[(offset + 4)..<(offset + 8 + length)]).withUnsafeBufferPointer {
                UInt32(crc32(0, $0.baseAddress, uInt($0.count)))
            }
            XCTAssertEqual(stored, computed, type)
            chunks[type] = payload
            offset += 12 + length
        }
        XCTAssertEqual(chunks["IHDR"], [0, 0, 0, 3, 0, 0, 0, 2, 8, 2, 0, 0, 0])
        XCTAssertEqual(chunks["IEND"], [])

        let compressed = try XCTUnwrap(chunks["IDAT"])
        var inflated = [UInt8](repeating: 0, count: 64)
        var inflatedLength = uLong(inflated.count)
        XCTAssertEqual(uncompress(&inflated, &inflatedLength, compressed, uLong(compressed.count)), Z_OK)
        // Filter type 0 precedes each 9-byte row.
        let rows: [[UInt8]] = [[0, 0, 1, 2, 3, 4, 5, 6, 7, 8], [0, 9, 10, 11, 12, 13, 14, 15, 16, 17]]
        XCTAssertEqual(Array(inflated.prefix(Int(inflatedLength))), rows.flatMap { $0 })
    }

#if canImport(ImageIO)
    func testPNGDecodesWithImageIO() throws {
        let image = DICOMRenderedImage(width: 2, height: 2, format: .gray8, pixels: [0, 85, 170, 255])
        let source = try XCTUnwrap(CGImageSourceCreateWithData(try image.pngData() as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 2)
        XCTAssertEqual(decoded.bitsPerPixel, 8)
        let bytes = try XCTUnwrap(decoded.dataProvider?.data as Data?)
        XCTAssertEqual(Array(bytes.prefix(2)) + Array(bytes.dropFirst(decoded.bytesPerRow).prefix(2)), [0, 85, 170, 255])
    }
#endif

    // MARK: Fixtures

    private func makeImage(
        rows: Int = 1,
        columns: Int,
        bitsAllocated: Int = 8,
        bitsStored: Int? = 8,
        highBit: Int? = nil,
        signed: Bool = false,
        samples: Int = 1,
        photometric: String = "MONOCHROME2",
        planar: Int? = nil,
        frames: Int? = nil,
        pixelData: Data,
        pixelDataKeyword: String = "PixelData",
        extra: [String: String] = [:]
    ) -> DataSet {
        let dataset = DataSet()
        _ = dataset.set(value: UInt16(rows), forTagName: "Rows")
        _ = dataset.set(value: UInt16(columns), forTagName: "Columns")
        _ = dataset.set(value: UInt16(samples), forTagName: "SamplesPerPixel")
        _ = dataset.set(value: photometric, forTagName: "PhotometricInterpretation")
        _ = dataset.set(value: UInt16(bitsAllocated), forTagName: "BitsAllocated")
        if let bitsStored {
            _ = dataset.set(value: UInt16(bitsStored), forTagName: "BitsStored")
            _ = dataset.set(value: UInt16(highBit ?? bitsStored - 1), forTagName: "HighBit")
            _ = dataset.set(value: UInt16(signed ? 1 : 0), forTagName: "PixelRepresentation")
        }
        if samples > 1 {
            _ = dataset.set(value: UInt16(planar ?? 0), forTagName: "PlanarConfiguration")
        }
        if let frames {
            _ = dataset.set(value: String(frames), forTagName: "NumberOfFrames")
        }
        for (name, value) in extra {
            XCTAssertNotNil(dataset.set(value: value, forTagName: name), name)
        }
        let element = DataElement(withTagName: pixelDataKeyword, dataset: dataset)!
        element.vr = pixelDataKeyword == "PixelData" ? (bitsAllocated > 8 ? .OW : .OB)
            : (pixelDataKeyword == "FloatPixelData" ? .OF : .OD)
        XCTAssertTrue(element.setValue(pixelData))
        dataset.add(element: element)
        return dataset
    }

    private func words(_ values: [UInt16]) -> Data {
        values.reduce(into: Data()) { $0.append(contentsOf: [UInt8($1 & 0xFF), UInt8($1 >> 8)]) }
    }

    private func addElement(_ name: String, vr: VR.VR, value: Any, to dataset: DataSet) {
        let element = DataElement(withTagName: name, dataset: dataset)!
        element.vr = vr
        XCTAssertTrue(element.setValue(value), name)
        dataset.add(element: element)
    }

    private func newItem(in sequence: DataSequence) -> DataItem {
        let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
        item.length = -1
        sequence.items.append(item)
        return item
    }

    private func newSequence(_ name: String) -> DataSequence {
        let sequence = DataSequence(withTag: DicomSpec.shared.dataTag(forName: name)!)
        sequence.vr = .SQ
        sequence.length = -1
        return sequence
    }

    private func addLUT(named name: String, descriptor: [UInt16], data: Data, to dataset: DataSet) {
        let sequence = newSequence(name)
        let item = newItem(in: sequence)
        let descriptorElement = DataElement(withTagName: "LUTDescriptor", dataset: dataset, parent: item)!
        descriptorElement.vr = .US
        XCTAssertTrue(descriptorElement.setValue(descriptor))
        let dataElement = DataElement(withTagName: "LUTData", dataset: dataset, parent: item)!
        dataElement.vr = .OW
        XCTAssertTrue(dataElement.setValue(data))
        item.elements += [descriptorElement, dataElement]
        dataset.add(element: sequence)
    }

    private func addFunctionalGroups(
        to dataset: DataSet,
        shared: [String: [String: String]],
        perFrame: [[String: [String: String]]]
    ) {
        func fill(_ item: DataItem, with macros: [String: [String: String]]) {
            for (macro, values) in macros {
                let sequence = newSequence(macro)
                let macroItem = newItem(in: sequence)
                for (name, value) in values {
                    let element = DataElement(withTagName: name, dataset: dataset, parent: macroItem)!
                    XCTAssertTrue(element.setValue(value))
                    macroItem.elements.append(element)
                }
                item.elements.append(sequence)
            }
        }
        let sharedSequence = newSequence("SharedFunctionalGroupsSequence")
        fill(newItem(in: sharedSequence), with: shared)
        dataset.add(element: sharedSequence)
        let perFrameSequence = newSequence("PerFrameFunctionalGroupsSequence")
        for macros in perFrame {
            fill(newItem(in: perFrameSequence), with: macros)
        }
        dataset.add(element: perFrameSequence)
    }
}
