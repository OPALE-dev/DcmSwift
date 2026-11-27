//
//  DcmSwiftCodestreamStructureTests.swift
//  DcmSwiftTests
//
//  The structure of compressed frames, checked against the encoders and
//  tools that wrote or read them independently: codestream-tiles.j2k was
//  encoded by OpenJPEG 2.5 (opj_compress -t 16,16 -TP R -n 3 -TLM), its
//  main header markers listed by opj_dump and its tile-parts by the TLM
//  marker OpenJPEG wrote; codestream-restart.jpg was encoded by
//  libjpeg-turbo 3.2 (cjpeg -restart 1), its markers listed by djpeg
//  -verbose.
//

import XCTest
@testable import DcmSwift

final class DcmSwiftCodestreamStructureTests: XCTestCase {
    private func resource(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext)))
    }

    /// Tile and Ptlm of each tile-part, in the order of the codestream, from the TLM marker.
    private let tileParts = [(0, 42), (0, 32), (0, 38), (1, 40), (1, 32), (1, 38), (2, 31), (2, 59), (2, 83),
                             (3, 42), (3, 30), (3, 37), (4, 43), (4, 59), (4, 82), (5, 31), (5, 44), (5, 55)]

    func testJPEG2000MarkersAndTilePartsMatchOpenJPEG() throws {
        let structure = DICOMCodestreamStructure(try resource("codestream-tiles", "j2k"))
        XCTAssertEqual(structure.format, .jpeg2000)
        XCTAssertEqual(structure.issues, [])
        // The main header, as opj_dump lists it: position and length with the marker.
        let main = structure.markers.prefix(6).map { ($0.name, $0.offset, $0.length) }
        let expected = [("SOC", 0, 2), ("SIZ", 2, 43), ("COD", 45, 14), ("QCD", 59, 12), ("TLM", 71, 96), ("COM", 167, 19)]
        XCTAssertEqual(main.map(\.0), expected.map(\.0))
        XCTAssertEqual(main.map(\.1), expected.map(\.1))
        XCTAssertEqual(main.map(\.2), expected.map(\.2))

        // The tile-parts follow one another from the end of the main header, as TLM gives them.
        let sots = structure.markers.filter { $0.name == "SOT" }
        XCTAssertEqual(sots.map { $0.tile ?? -1 }, tileParts.map(\.0))
        XCTAssertEqual(sots.map(\.length), tileParts.map(\.1))
        var start = 186
        for sot in sots {
            XCTAssertEqual(sot.offset, start)
            start += sot.length
        }
        XCTAssertEqual(structure.markers.last?.name, "EOC")
        XCTAssertEqual(structure.markers.last?.offset, start)
        // Each tile-part has its data, within it.
        let sods = structure.markers.filter { $0.name == "SOD" }
        XCTAssertEqual(sods.count, tileParts.count)
        for (sod, sot) in zip(sods, sots) { XCTAssertTrue(sot.range.contains(sod.offset) && sod.range.upperBound == sot.range.upperBound) }

        // 40 × 30 in tiles of 16: 3 × 2.
        let grid = try XCTUnwrap(structure.tiles)
        XCTAssertEqual(grid.columns, 3)
        XCTAssertEqual(grid.rows, 2)
        XCTAssertEqual(grid.tile(x: 0, y: 0), 0)
        XCTAssertEqual(grid.tile(x: 16, y: 0), 1)
        XCTAssertEqual(grid.tile(x: 39, y: 29), 5)
        XCTAssertNil(grid.tile(x: 48, y: 0))
        XCTAssertEqual(structure.ranges(ofTile: 4).map(\.count), [43, 59, 82])
        // A byte of coded data: its SOD rather than the SOT around it.
        XCTAssertEqual(structure.marker(at: sods[3].offset + 5)?.name, "SOD")

        let siz = try XCTUnwrap(structure.markers.first { $0.name == "SIZ" })
        XCTAssertTrue(siz.parameters.contains(.init(name: "Size", value: "40 × 30")))
        XCTAssertTrue(siz.parameters.contains(.init(name: "Depth", value: "12 bits, unsigned")))
        let cod = try XCTUnwrap(structure.markers.first { $0.name == "COD" })
        XCTAssertTrue(cod.parameters.contains(.init(name: "Levels", value: "2")))
        XCTAssertTrue(cod.parameters.contains(.init(name: "Wavelet", value: "5-3 reversible")))
        XCTAssertTrue(structure.markers.contains { $0.name == "COM" && $0.parameters.first?.value == "DcmSwift test" })
    }

    func testJPEGMarkersMatchDjpeg() throws {
        let data = try resource("codestream-restart", "jpg")
        let structure = DICOMCodestreamStructure(data)
        XCTAssertEqual(structure.format, .jpeg)
        XCTAssertEqual(structure.issues, [])
        XCTAssertEqual(structure.markers.map(\.name), ["SOI", "APP0", "DQT", "SOF0", "DHT", "DHT", "DRI", "SOS", "EOI"])
        let sof = try XCTUnwrap(structure.markers.first { $0.name == "SOF0" })
        XCTAssertTrue(sof.parameters.contains(.init(name: "Size", value: "23 × 17")))
        XCTAssertTrue(structure.markers.contains { $0.name == "DRI" && $0.parameters.first?.value == "3 MCU" })
        // 3 × 3 blocks of 8 × 8, a restart every 3: two RST markers, inside the scan.
        let scan = try XCTUnwrap(structure.markers.first { $0.name == "SOS" })
        XCTAssertTrue(scan.parameters.contains(.init(name: "Restarts", value: "2")))
        XCTAssertEqual(scan.range.upperBound, data.count - 2)
        XCTAssertNil(structure.tiles)
    }

    func testDeviantStreamsAreDescribedNotRefused() throws {
        let j2k = try resource("codestream-tiles", "j2k")
        // Cut in the middle of a tile-part: described up to there.
        let cut = DICOMCodestreamStructure(j2k.prefix(400))
        XCTAssertEqual(cut.format, .jpeg2000)
        XCTAssertFalse(cut.markers.isEmpty)
        XCTAssertTrue(cut.issues.contains { $0.text.contains("past the end") })
        XCTAssertTrue(cut.issues.contains { $0.text.contains("No EOC") })

        // An unknown marker segment in the main header.
        var unknown = Data(j2k.prefix(2))
        unknown.append(contentsOf: [0xFF, 0x7A, 0x00, 0x04, 0x01, 0x02])
        unknown.append(j2k.dropFirst(2))
        let strange = DICOMCodestreamStructure(unknown)
        XCTAssertEqual(strange.markers[1].name, "0xFF7A")
        XCTAssertTrue(strange.issues.contains { $0.text.contains("Unknown marker 0xFF7A") })
        XCTAssertEqual(strange.markers.filter { $0.name == "SOT" }.count, tileParts.count)

        // An even-length fragment: one padding byte after EOC is no issue.
        XCTAssertEqual(DICOMCodestreamStructure(j2k + Data([0])).issues, [])

        // A JP2 file where DICOM wants a codestream: read through its jp2c box, with the deviation said.
        let jp2 = DICOMCodestreamStructure(try resource("jpeg2000-jp2_rgb8_padded", "j2k"))
        XCTAssertEqual(jp2.format, .jpeg2000)
        XCTAssertGreaterThan(jp2.codestreamOffset, 0)
        XCTAssertEqual(jp2.markers.first?.name, "SOC")
        XCTAssertEqual(jp2.markers.first?.offset, jp2.codestreamOffset)
        XCTAssertTrue(jp2.issues.contains { $0.text.contains("JP2") })

        XCTAssertEqual(DICOMCodestreamStructure(Data([1, 2, 3])).format, .unknown)
        XCTAssertEqual(DICOMCodestreamStructure(Data()).issues.count, 1)
    }
}
