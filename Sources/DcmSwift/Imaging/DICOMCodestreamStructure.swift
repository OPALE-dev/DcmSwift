//
//  DICOMCodestreamStructure.swift
//  DcmSwift
//
//  The structure of a compressed frame, read without decoding it: the
//  markers of a JPEG 2000 codestream (ISO/IEC 15444-1 annex A), its tiles
//  and their tile-parts, or the markers and scans of a JPEG or JPEG-LS
//  stream (ITU-T T.81 annex B, T.87). Each marker has its offset in the
//  frame, its length and its main parameters. A stream that does not
//  conform (unknown marker, length past the end, missing end marker, a
//  JP2 file where DICOM wants a bare codestream, PS3.5 A.4.4) is described
//  as far as it goes, with what is wrong, never refused.
//

import Foundation

/// The markers of a compressed frame and what they say.
public struct DICOMCodestreamStructure: Sendable, Equatable {
    public enum Format: String, Sendable, Equatable {
        /// A JPEG 2000 codestream (15444-1, also HTJ2K, 15444-15).
        case jpeg2000
        /// A JPEG or JPEG-LS stream (T.81, T.87).
        case jpeg
        /// Neither: no SOC nor SOI at the start.
        case unknown
    }

    /// A marker and its segment.
    public struct Marker: Sendable, Equatable {
        /// The marker code, 0xFF4F for SOC.
        public let code: UInt16
        /// Its short name, SOC, SIZ, SOS…; "0xFFxx" when unknown.
        public let name: String
        /// Where its first byte lies in the frame.
        public let offset: Int
        /// Its bytes: the marker, its segment, and for SOD and SOS the
        /// coded data that follows, up to the next marker.
        public let length: Int
        /// The tile of a tile-part marker, from SOT to the end of its data.
        public let tile: Int?
        /// Its main parameters, in the order of the segment.
        public let parameters: [Parameter]

        public var range: Range<Int> { offset..<(offset + length) }
    }

    public struct Parameter: Sendable, Equatable {
        public let name: String
        public let value: String
    }

    /// What departs from the standard, where.
    public struct Issue: Sendable, Equatable {
        public let offset: Int
        public let text: String
    }

    /// The tile grid of a JPEG 2000 image, from SIZ.
    public struct TileGrid: Sendable, Equatable {
        public let imageOffset: (x: Int, y: Int)
        public let tileSize: (width: Int, height: Int)
        public let tileOffset: (x: Int, y: Int)
        public let columns: Int
        public let rows: Int

        public var count: Int { columns * rows }

        /// The tile holding a pixel of the image, column and row from the top left.
        public func tile(x: Int, y: Int) -> Int? {
            guard tileSize.width > 0, tileSize.height > 0 else { return nil }
            let column = (x + imageOffset.x - tileOffset.x) / tileSize.width
            let row = (y + imageOffset.y - tileOffset.y) / tileSize.height
            guard (0..<columns).contains(column), (0..<rows).contains(row) else { return nil }
            return row * columns + column
        }

        public static func == (a: TileGrid, b: TileGrid) -> Bool {
            a.imageOffset == b.imageOffset && a.tileSize == b.tileSize && a.tileOffset == b.tileOffset
                && a.columns == b.columns && a.rows == b.rows
        }
    }

    public let format: Format
    public let markers: [Marker]
    public let issues: [Issue]
    /// The tiles of a JPEG 2000 image; nil for JPEG or without a valid SIZ.
    public let tiles: TileGrid?
    /// Where the codestream starts in the frame: after the boxes of a JP2 file.
    public let codestreamOffset: Int

    /// The bytes of a tile: its tile-parts, from their SOT to the end of their data.
    public func ranges(ofTile tile: Int) -> [Range<Int>] {
        markers.filter { $0.code == 0xFF90 && $0.tile == tile }.map(\.range)
    }

    /// The marker whose bytes hold an offset of the frame; within a
    /// tile-part, the marker of its header or its data rather than SOT.
    public func marker(at offset: Int) -> Marker? {
        markers.last { $0.range.contains(offset) && $0.code != 0xFF90 } ?? markers.last { $0.range.contains(offset) }
    }

    // MARK: - Reading

    /// The structure of a compressed frame.
    ///
    /// - Parameter data: the bytes of the frame, its fragments put together.
    public init(_ data: Data) {
        let bytes = [UInt8](data)
        var reader = Reader(bytes: bytes)
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0x4F {
            reader.readJPEG2000(from: 0)
        } else if bytes.count >= 12, Array(bytes[4..<8]) == Array("jP  ".utf8) {
            reader.readJP2()
        } else if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xD8 {
            reader.readJPEG()
        } else {
            reader.issue(0, "Neither a JPEG 2000 codestream (SOC) nor a JPEG stream (SOI) at the start")
        }
        format = reader.format
        markers = reader.markers
        issues = reader.issues
        tiles = reader.tiles
        codestreamOffset = reader.codestreamOffset
    }

    /// Reads markers one after the other.
    private struct Reader {
        let bytes: [UInt8]
        var format: Format = .unknown
        var markers: [Marker] = []
        var issues: [Issue] = []
        var tiles: TileGrid?
        var codestreamOffset = 0

        mutating func issue(_ offset: Int, _ text: String) { issues.append(Issue(offset: offset, text: text)) }

        func u8(_ at: Int) -> Int? { at < bytes.count ? Int(bytes[at]) : nil }
        func u16(_ at: Int) -> Int? { at + 1 < bytes.count ? Int(bytes[at]) << 8 | Int(bytes[at + 1]) : nil }
        func u32(_ at: Int) -> Int? {
            guard at + 3 < bytes.count else { return nil }
            return (0..<4).reduce(0) { $0 << 8 | Int(bytes[at + $1]) }
        }

        // MARK: JP2

        /// A JP2 file: its boxes, then the codestream of its jp2c box.
        mutating func readJP2() {
            issue(0, "A JP2 file: DICOM wants a bare codestream, without the JP2 boxes (PS3.5 A.4.4)")
            var at = 0
            while at + 8 <= bytes.count {
                guard var size = u32(at) else { break }
                let type = String(decoding: bytes[(at + 4)..<(at + 8)], as: UTF8.self)
                var header = 8
                if size == 1, let large = u32(at + 12) { size = large; header = 16 }
                if size == 0 { size = bytes.count - at }
                if type == "jp2c" {
                    readJPEG2000(from: at + header)
                    return
                }
                guard size >= header else { issue(at, "Box \(type) of \(size) bytes"); return }
                at += size
            }
            issue(at, "No jp2c box: the JP2 file holds no codestream")
        }

        // MARK: JPEG 2000

        mutating func readJPEG2000(from start: Int) {
            format = .jpeg2000
            codestreamOffset = start
            var at = start
            var tile: Int?
            var tilePartEnd: Int?
            var ended = false
            while at < bytes.count {
                guard bytes[at] == 0xFF, let code = u16(at) else {
                    issue(at, String(format: "0x%02X where a marker is expected", bytes[at]))
                    return
                }
                switch code {
                case 0xFF4F:
                    add(code, at: at, length: 2)
                    at += 2
                case 0xFFD9:
                    // The code of JPEG's EOI, named EOC in a codestream.
                    markers.append(Marker(code: 0xFFD9, name: "EOC", offset: at, length: 2, tile: nil, parameters: []))
                    at += 2
                    ended = true
                case 0xFF93:
                    // SOD: the coded data of the tile-part, to its end.
                    let end = min(tilePartEnd ?? bytes.count, bytes.count)
                    add(code, at: at, length: max(2, end - at), tile: tile,
                        parameters: [Parameter(name: "Data", value: "\(max(0, end - at - 2)) bytes")])
                    at = max(at + 2, end)
                    tile = nil
                    tilePartEnd = nil
                default:
                    guard let length = u16(at + 2), length >= 2 else {
                        issue(at, "Marker \(Self.name(code)) without a length")
                        return
                    }
                    guard at + 2 + length <= bytes.count else {
                        issue(at, "Marker \(Self.name(code)) of \(length) bytes past the end of the frame")
                        add(code, at: at, length: bytes.count - at)
                        return
                    }
                    let segment = (at + 4)..<(at + 2 + length)
                    if code == 0xFF90, let index = u16(at + 4), let psot = u32(at + 6) {
                        tile = index
                        // Psot 0: the last tile-part, up to EOC.
                        let end = psot == 0 ? max(at, bytes.count - 2) : at + psot
                        if end > bytes.count { issue(at, "Tile-part \(index) of \(psot) bytes past the end of the frame") }
                        tilePartEnd = min(end, bytes.count)
                        let parts = [Parameter(name: "Tile", value: "\(index)"), Parameter(name: "Length", value: "\(psot) bytes"),
                                     Parameter(name: "Part", value: "\(u8(at + 10) ?? 0) of \(u8(at + 11).map { $0 == 0 ? "?" : "\($0)" } ?? "?")")]
                        add(code, at: at, length: max(2 + length, (tilePartEnd ?? at) - at), tile: index, parameters: parts)
                        // The SOT marker covers the tile-part; its header markers follow inside.
                        at += 2 + length
                        continue
                    }
                    if Self.names[UInt16(code)] == nil { issue(at, "Unknown marker \(Self.name(code))") }
                    add(code, at: at, length: 2 + length, tile: tile, parameters: parameters(code, segment))
                    at += 2 + length
                }
                if ended { break }
            }
            if !ended { issue(bytes.count, "No EOC: the codestream ends without its end marker") }
            if ended, at < bytes.count, bytes[at...].contains(where: { $0 != 0 }) {
                issue(at, "\(bytes.count - at) bytes after EOC")
            }
        }

        mutating func add(_ code: UInt16, at: Int, length: Int, tile: Int? = nil, parameters: [Parameter] = []) {
            markers.append(Marker(code: code, name: Self.name(code), offset: at, length: length, tile: tile, parameters: parameters))
        }

        mutating func add(_ code: Int, at: Int, length: Int, tile: Int? = nil, parameters: [Parameter] = []) {
            add(UInt16(code), at: at, length: length, tile: tile, parameters: parameters)
        }

        /// The main parameters of a JPEG 2000 main or tile-part header segment.
        mutating func parameters(_ code: Int, _ segment: Range<Int>) -> [Parameter] {
            let s = segment.lowerBound
            switch code {
            case 0xFF51:
                guard let x = u32(s + 2), let y = u32(s + 6), let xo = u32(s + 10), let yo = u32(s + 14),
                      let tw = u32(s + 18), let th = u32(s + 22), let txo = u32(s + 26), let tyo = u32(s + 30),
                      let components = u16(s + 34) else { return [] }
                var parameters = [Parameter(name: "Size", value: "\(x - xo) × \(y - yo)"),
                                  Parameter(name: "Tiles", value: "\(tw) × \(th)"),
                                  Parameter(name: "Components", value: "\(components)")]
                if let rsiz = u16(s) { parameters.insert(Parameter(name: "Profile", value: String(format: "0x%04X", rsiz)), at: 0) }
                if let ssiz = u8(s + 36) {
                    parameters.append(Parameter(name: "Depth", value: "\((ssiz & 0x7F) + 1) bits, \(ssiz & 0x80 != 0 ? "signed" : "unsigned")"))
                }
                if xo > 0 || yo > 0 { parameters.append(Parameter(name: "Image Offset", value: "\(xo), \(yo)")) }
                if tw > 0, th > 0, x > txo, y > tyo {
                    let columns = (x - txo + tw - 1) / tw, rows = (y - tyo + th - 1) / th
                    tiles = TileGrid(imageOffset: (xo, yo), tileSize: (tw, th), tileOffset: (txo, tyo), columns: columns, rows: rows)
                    parameters.insert(Parameter(name: "Grid", value: "\(columns) × \(rows) = \(columns * rows)"), at: 3)
                } else {
                    issue(s - 4, "SIZ: no valid tile grid")
                }
                return parameters
            case 0xFF52:
                guard let scod = u8(s), let order = u8(s + 1), let layers = u16(s + 2), let mct = u8(s + 4),
                      let levels = u8(s + 5), let xcb = u8(s + 6), let ycb = u8(s + 7), let style = u8(s + 8),
                      let transform = u8(s + 9) else { return [] }
                let orders = ["LRCP", "RLCP", "RPCL", "PCRL", "CPRL"]
                return [Parameter(name: "Progression", value: order < orders.count ? orders[order] : "\(order)"),
                        Parameter(name: "Layers", value: "\(layers)"),
                        Parameter(name: "Levels", value: "\(levels)"),
                        Parameter(name: "Code-Blocks", value: "\(1 << (xcb + 2)) × \(1 << (ycb + 2))"),
                        Parameter(name: "Wavelet", value: transform == 1 ? "5-3 reversible" : transform == 0 ? "9-7 irreversible" : "\(transform)"),
                        Parameter(name: "Color Transform", value: mct == 1 ? "yes" : "no"),
                        Parameter(name: "Precincts", value: scod & 1 != 0 ? "defined" : "maximal"),
                        Parameter(name: "Style", value: String(format: "SOP %@, EPH %@, code-block 0x%02X",
                                                               scod & 2 != 0 ? "yes" : "no", scod & 4 != 0 ? "yes" : "no", style))]
            case 0xFF5C, 0xFF5D:
                let at = code == 0xFF5D ? s + 1 : s
                guard let sq = u8(at) else { return [] }
                let styles = ["none (reversible)", "scalar derived", "scalar expounded"]
                return [Parameter(name: "Quantization", value: (sq & 0x1F) < styles.count ? styles[sq & 0x1F] : "\(sq & 0x1F)"),
                        Parameter(name: "Guard Bits", value: "\(sq >> 5)")]
            case 0xFF64:
                guard let registration = u16(s) else { return [] }
                let text = registration == 1
                    ? String(decoding: bytes[(s + 2)..<segment.upperBound], as: UTF8.self)
                    : "\(segment.count - 2) bytes"
                return [Parameter(name: "Comment", value: text)]
            default:
                return [Parameter(name: "Segment", value: "\(segment.count + 2) bytes")]
            }
        }

        // MARK: JPEG

        mutating func readJPEG() {
            format = .jpeg
            var at = 0
            var ended = false
            while at < bytes.count {
                guard bytes[at] == 0xFF, let code = u16(at) else {
                    issue(at, String(format: "0x%02X where a marker is expected", bytes[at]))
                    return
                }
                // Fill bytes before a marker.
                if code == 0xFFFF { at += 1; continue }
                switch code {
                case 0xFFD8, 0xFFD9, 0xFF01:
                    add(code, at: at, length: 2)
                    at += 2
                    if code == 0xFFD9 { ended = true }
                case 0xFFD0...0xFFD7:
                    issue(at, "\(Self.name(code)) outside a scan")
                    add(code, at: at, length: 2)
                    at += 2
                default:
                    guard let length = u16(at + 2), length >= 2, at + 2 + length <= bytes.count else {
                        issue(at, "Marker \(Self.name(code)) with a length past the end of the frame")
                        add(code, at: at, length: bytes.count - at)
                        return
                    }
                    let segment = (at + 4)..<(at + 2 + length)
                    if code == 0xFFDA {
                        // The entropy-coded data, its restart markers inside, up to the next marker.
                        var end = segment.upperBound
                        var restarts = 0
                        while end + 1 < bytes.count {
                            if bytes[end] == 0xFF, bytes[end + 1] != 0x00 {
                                if (0xD0...0xD7).contains(bytes[end + 1]) { restarts += 1; end += 2; continue }
                                break
                            }
                            end += 1
                        }
                        if end + 1 >= bytes.count { end = bytes.count }
                        var parameters = jpegParameters(code, segment)
                        parameters.append(Parameter(name: "Data", value: "\(end - segment.upperBound) bytes"))
                        if restarts > 0 { parameters.append(Parameter(name: "Restarts", value: "\(restarts)")) }
                        add(code, at: at, length: end - at, parameters: parameters)
                        at = end
                        continue
                    }
                    if Self.name(code).hasPrefix("0x") { issue(at, "Unknown marker \(Self.name(code))") }
                    add(code, at: at, length: 2 + length, parameters: jpegParameters(code, segment))
                    at += 2 + length
                }
                if ended { break }
            }
            if !ended { issue(bytes.count, "No EOI: the stream ends without its end marker") }
        }

        func jpegParameters(_ code: Int, _ segment: Range<Int>) -> [Parameter] {
            let s = segment.lowerBound
            switch code {
            case 0xFFC0...0xFFCF where ![0xFFC4, 0xFFC8, 0xFFCC].contains(code), 0xFFF7:
                guard let precision = u8(s), let rows = u16(s + 1), let columns = u16(s + 3), let components = u8(s + 5) else { return [] }
                return [Parameter(name: "Size", value: "\(columns) × \(rows)"),
                        Parameter(name: "Precision", value: "\(precision) bits"),
                        Parameter(name: "Components", value: "\(components)")]
            case 0xFFDA:
                guard let components = u8(s) else { return [] }
                return [Parameter(name: "Components", value: "\(components)")]
            case 0xFFDD:
                return u16(s).map { [Parameter(name: "Restart Interval", value: "\($0) MCU")] } ?? []
            case 0xFFDB:
                return [Parameter(name: "Tables", value: "\(segment.count / 65)")]
            case 0xFFFE:
                return [Parameter(name: "Comment", value: String(decoding: bytes[segment], as: UTF8.self))]
            default:
                return [Parameter(name: "Segment", value: "\(segment.count + 2) bytes")]
            }
        }

        // MARK: Names

        static func name(_ code: Int) -> String { name(UInt16(code)) }

        static func name(_ code: UInt16) -> String {
            if let name = names[code] { return name }
            switch code {
            case 0xFFE0...0xFFEF: return "APP\(code - 0xFFE0)"
            case 0xFFD0...0xFFD7: return "RST\(code - 0xFFD0)"
            case 0xFFC0...0xFFCF where ![0xFFC4, 0xFFC8, 0xFFCC].contains(code): return "SOF\(code - 0xFFC0)"
            default: return String(format: "0x%04X", code)
            }
        }

        static let names: [UInt16: String] = [
            // JPEG 2000 (15444-1 table A.2; CAP and CPF of 15444-15)
            0xFF4F: "SOC", 0xFF50: "CAP", 0xFF51: "SIZ", 0xFF52: "COD", 0xFF53: "COC", 0xFF55: "TLM", 0xFF57: "PLM",
            0xFF58: "PLT", 0xFF59: "CPF", 0xFF5C: "QCD", 0xFF5D: "QCC", 0xFF5E: "RGN", 0xFF5F: "POC", 0xFF60: "PPM",
            0xFF61: "PPT", 0xFF63: "CRG", 0xFF64: "COM", 0xFF90: "SOT", 0xFF91: "SOP", 0xFF92: "EPH", 0xFF93: "SOD",
            // JPEG (T.81 table B.1) and JPEG-LS (T.87)
            0xFFD8: "SOI", 0xFFD9: "EOI", 0xFFC4: "DHT", 0xFFCC: "DAC", 0xFFDA: "SOS", 0xFFDB: "DQT", 0xFFDC: "DNL",
            0xFFDD: "DRI", 0xFFDE: "DHP", 0xFFDF: "EXP", 0xFFFE: "COM", 0xFF01: "TEM", 0xFFF7: "SOF55", 0xFFF8: "LSE",
        ]
    }
}
