//
//  DcmSwiftColorPaletteTests.swift
//  DcmSwiftTests
//
//  The well-known color palettes of PS3.6 annex B, checked twice: against
//  entries 0, 127 and 255 read in the tables of the standard (PS3.6 2026e),
//  and entry by entry against pydicom 3.0.2, which expands the palette
//  files it distributes on its own (palettes-pydicom.json, written by
//  pydicom.pixels.apply_color_lut on the inputs 0 to 255).
//

import XCTest
@testable import DcmSwift

final class DcmSwiftColorPaletteTests: XCTestCase {
    func testWellKnownPalettesMatchTheTablesOfPS36() {
        // Entries 0, 127 and 255 of the normal palettes, as tables
        // B.1.1.2-2 to B.1.4.2-2 give them.
        let standard: [DICOMColorPalette.WellKnown: [[UInt8]]] = [
            .hotIron: [[0, 0, 0], [254, 0, 0], [255, 255, 255]],
            .pet: [[0, 0, 0], [126, 1, 253], [255, 255, 255]],
            .hotMetalBlue: [[0, 0, 0], [114, 15, 103], [255, 255, 255]],
            .pet20Step: [[0, 0, 0], [48, 144, 48], [255, 255, 255]],
            // The segmented palettes of tables B.1.5.2-1 to B.1.8.2-1
            // expanded: a discrete first entry, then linear segments
            // (PS3.3 C.7.9.2).
            .spring: [[255, 0, 255], [255, 127, 128], [255, 255, 0]],
            .summer: [[0, 255, 0], [0, 192, 0], [0, 128, 254]],
            .fall: [[255, 255, 0], [255, 128, 0], [255, 0, 0]],
            .winter: [[0, 0, 255], [0, 127, 192], [127, 255, 128]],
        ]
        for palette in DICOMColorPalette.WellKnown.allCases {
            let table = DICOMColorPalette(palette)
            let found = [0, 127, 255].map { index -> [UInt8] in
                let color = table.color(at: index)
                return [color.red, color.green, color.blue]
            }
            XCTAssertEqual(found, standard[palette], palette.name)
            XCTAssertEqual(table.source, .wellKnown(palette))
        }
    }

    func testWellKnownPalettesMatchPydicomEntryByEntry() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "palettes-pydicom", withExtension: "json"))
        let reference = try JSONDecoder().decode([String: [[Int]]].self, from: Data(contentsOf: url))
        XCTAssertEqual(reference.count, 8)
        for palette in DICOMColorPalette.WellKnown.allCases {
            let channels = try XCTUnwrap(reference[palette.uid], palette.name)
            let table = DICOMColorPalette(palette)
            let found = [table.red, table.green, table.blue]
            for channel in 0..<3 {
                let differences = zip(found[channel], channels[channel]).map { abs(Int($0) - $1) }
                XCTAssertEqual(channels[channel].count, 256)
                // PS3.3 C.7.9.2 leaves the rounding of a linear segment
                // open: pydicom rounds a half to even, DcmSwift away from
                // zero. Normal palettes are equal; segmented ones may differ
                // by one at exact halves.
                XCTAssertLessThanOrEqual(differences.max() ?? 0, palette.isSegmented ? 1 : 0, palette.name)
            }
        }
    }

    func testPalettesByUID() {
        XCTAssertEqual(DICOMColorPalette(uid: "1.2.840.10008.1.5.1")?.source, .wellKnown(.hotIron))
        XCTAssertEqual(DICOMColorPalette(uid: "1.2.840.10008.1.5.8\0")?.source, .wellKnown(.winter))
        XCTAssertNil(DICOMColorPalette(uid: "1.2.840.10008.1.5.9"))
        XCTAssertEqual(DICOMColorPalette.WellKnown.pet20Step.contentLabel, "PET_20_STEP")
    }

    func testPaletteAndInversionFollowTheVOI() throws {
        // Identity VOI over 8 bits: stored values are the indices.
        let image = makeImage(photometric: "MONOCHROME2", pixels: [0, 127, 255])
        let hotIron = DICOMColorPalette(.hotIron)
        let colored = try DICOMImageRenderer(dataset: image).render(options: DICOMRenderingOptions(palette: hotIron))
        XCTAssertEqual(colored.format, .rgb8)
        XCTAssertEqual(colored.pixels, [0, 0, 0, 254, 0, 0, 255, 255, 255])

        // Inverted, then colored: 0 takes entry 255.
        let inverted = try DICOMImageRenderer(dataset: image).render(options: DICOMRenderingOptions(inverts: true))
        XCTAssertEqual(inverted.pixels, [255, 128, 0])
        let both = try DICOMImageRenderer(dataset: image).render(options: DICOMRenderingOptions(inverts: true, palette: hotIron))
        XCTAssertEqual(both.pixels, [255, 255, 255, 255, 0, 0, 0, 0, 0])

        // MONOCHROME1 inverted shows its minimum as black.
        let one = makeImage(photometric: "MONOCHROME1", pixels: [0, 255])
        XCTAssertEqual(try DICOMImageRenderer(dataset: one).render().pixels, [255, 0])
        XCTAssertEqual(try DICOMImageRenderer(dataset: one).render(options: DICOMRenderingOptions(inverts: true)).pixels, [0, 255])
    }

    func testColorImagesKeepTheirColors() throws {
        let image = makeImage(photometric: "RGB", pixels: [10, 20, 30], samples: 3)
        let rendered = try DICOMImageRenderer(dataset: image)
            .render(options: DICOMRenderingOptions(inverts: true, palette: DICOMColorPalette(.pet)))
        XCTAssertEqual(rendered.pixels, [10, 20, 30])
    }

    func testSupplementalPaletteOfAnImage() throws {
        let image = makeImage(photometric: "MONOCHROME2", pixels: [0, 1, 200])
        XCTAssertNil(try DICOMColorPalette(supplementalIn: image))
        // Three entries of 16 bits from the first value mapped 0; past the
        // table, the last entry.
        for (color, entries) in [("Red", [0x0000, 0xFFFF, 0x8000]), ("Green", [0x1200, 0x3400, 0x5600]),
                                 ("Blue", [0xFF00, 0x0000, 0x00FF])] {
            addElement("\(color)PaletteColorLookupTableDescriptor", vr: .US, value: [UInt16(3), 0, 16], to: image)
            addElement("\(color)PaletteColorLookupTableData", vr: .OW,
                       value: entries.reduce(into: Data()) { $0.append(contentsOf: [UInt8($1 & 0xFF), UInt8($1 >> 8)]) },
                       to: image)
        }
        let palette = try XCTUnwrap(try DICOMColorPalette(supplementalIn: image))
        XCTAssertEqual(palette.source, .supplemental)
        XCTAssertEqual(palette.red.prefix(4), [0, 0xFF, 0x80, 0x80])
        XCTAssertEqual(palette.green.prefix(3), [0x12, 0x34, 0x56])
        XCTAssertEqual(palette.blue[255], 0)

        // A descriptor without its other colors is reported.
        let broken = makeImage(photometric: "MONOCHROME2", pixels: [0])
        addElement("RedPaletteColorLookupTableDescriptor", vr: .US, value: [UInt16(3), 0, 8], to: broken)
        XCTAssertThrowsError(try DICOMColorPalette(supplementalIn: broken))
    }

    // MARK: Fixtures

    private func makeImage(photometric: String, pixels: [UInt8], samples: Int = 1) -> DataSet {
        let dataset = DataSet()
        _ = dataset.set(value: UInt16(1), forTagName: "Rows")
        _ = dataset.set(value: UInt16(pixels.count / samples), forTagName: "Columns")
        _ = dataset.set(value: UInt16(samples), forTagName: "SamplesPerPixel")
        _ = dataset.set(value: photometric, forTagName: "PhotometricInterpretation")
        _ = dataset.set(value: UInt16(8), forTagName: "BitsAllocated")
        _ = dataset.set(value: UInt16(8), forTagName: "BitsStored")
        _ = dataset.set(value: UInt16(7), forTagName: "HighBit")
        _ = dataset.set(value: UInt16(0), forTagName: "PixelRepresentation")
        if samples > 1 { _ = dataset.set(value: UInt16(0), forTagName: "PlanarConfiguration") }
        let element = DataElement(withTagName: "PixelData", dataset: dataset)!
        element.vr = .OB
        XCTAssertTrue(element.setValue(Data(pixels)))
        dataset.add(element: element)
        return dataset
    }

    private func addElement(_ name: String, vr: VR.VR, value: Any, to dataset: DataSet) {
        let element = DataElement(withTagName: name, dataset: dataset)!
        element.vr = vr
        XCTAssertTrue(element.setValue(value), name)
        dataset.add(element: element)
    }
}
