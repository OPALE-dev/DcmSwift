import Foundation

/// Rebuilds a JPEG 2000 codestream (ISO/IEC 15444-1) from the data-bins of
/// a JPIP cache, so that an ordinary decoder can read it.
///
/// A JPT-stream holds tiles, which are concatenated after the main header.
/// A JPP-stream holds precincts: each tile is written in the RPCL
/// progression, in which the packets of one precinct are contiguous, so
/// every precinct data-bin is copied whole (ISO/IEC 15444-9 Annex C,
/// ISO/IEC 15444-1 B.12.1.3).
public enum JPIPCodestream {
    /// The codestream `codestream` of the cache. Every data-bin of the
    /// image must be complete: the result is the full-quality codestream.
    public static func build(from cache: JPIPCache, codestream: Int = 0) throws -> Data {
        guard let main = cache.dataBin(.mainHeader, codestream: codestream, id: 0), main.isComplete else {
            throw JPIPError("the main header of codestream \(codestream) is incomplete")
        }
        let header = try MainHeader(main.data)
        if cache.hasTiles(codestream: codestream) {
            return try fromTiles(cache, codestream: codestream, header: header)
        }
        return try fromPrecincts(cache, codestream: codestream, header: header)
    }

    // MARK: Tiles (JPT-stream)

    private static func fromTiles(_ cache: JPIPCache, codestream: Int, header: MainHeader) throws -> Data {
        var output = Data(header.bytes)
        for tile in 0..<header.siz.tileCount {
            guard let bin = cache.dataBin(.tile, codestream: codestream, id: tile), bin.isComplete else {
                throw JPIPError("tile \(tile) is incomplete")
            }
            // A tile data-bin holds the tile's tile-parts, SOT included.
            output += bin.data
        }
        output += [0xFF, 0xD9]
        return output
    }

    // MARK: Precincts (JPP-stream)

    private static func fromPrecincts(_ cache: JPIPCache, codestream: Int, header: MainHeader) throws -> Data {
        let siz = header.siz
        guard header.packedHeaders == false else { throw JPIPError("packed packet headers (PPM) are not supported") }
        var output = Data(try header.rewritten())
        for tile in 0..<siz.tileCount {
            let tileHeader = cache.dataBin(.tileHeader, codestream: codestream, id: tile)
            guard tileHeader?.isComplete ?? true else { throw JPIPError("the header of tile \(tile) is incomplete") }
            let markers = try TileHeader(tileHeader?.data ?? Data(), components: siz.components.count)
            guard !markers.packedHeaders else { throw JPIPError("packed packet headers (PPT) are not supported") }
            let coding = (0..<siz.components.count).map { markers.coding(component: $0, main: header) }
            let layers = markers.cod?.layers ?? header.cod.layers
            // An empty packet is a zero bit, then EPH when the style uses it.
            let usesEPH = ((markers.cod?.flags ?? header.cod.flags) & 0x04) != 0
            let emptyPacket: [UInt8] = usesEPH ? [0x00, 0xFF, 0x92] : [0x00]

            var body = Data(try markers.rewritten())
            body += [0xFF, 0x93]
            let geometry = TileGeometry(siz: siz, tile: tile, coding: coding)
            for (component, resolution, precinct) in geometry.rpcl() {
                let sequence = geometry.precinctSequence(component: component, resolution: resolution, precinct: precinct)
                let id = tile + (component + sequence * siz.components.count) * siz.tileCount
                if let bin = cache.dataBin(.precinct, codestream: codestream, id: id) {
                    guard bin.isComplete else { throw JPIPError("precinct \(id) is incomplete") }
                    if !bin.data.isEmpty {
                        body += bin.data
                        continue
                    }
                }
                // A precinct without data: one empty packet per layer.
                for _ in 0..<layers { body += emptyPacket }
            }
            // SOT: Lsot 10, Isot, Psot (the whole tile-part), TPsot 0, TNsot 1.
            var sot = Data([0xFF, 0x90, 0x00, 0x0A])
            sot.append(UInt8(tile >> 8))
            sot.append(UInt8(tile & 0xFF))
            let length = UInt32(12 + body.count)
            sot += [UInt8(length >> 24), UInt8((length >> 16) & 0xFF), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]
            sot += [0x00, 0x01]
            output += sot + body
        }
        output += [0xFF, 0xD9]
        return output
    }

    // MARK: Marker segments

    struct Component {
        let precision: Int
        let dx: Int
        let dy: Int
    }

    /// The SIZ marker segment (ISO/IEC 15444-1 A.5.1).
    struct SIZ {
        let width: Int, height: Int, x0: Int, y0: Int
        let tileWidth: Int, tileHeight: Int, tileX0: Int, tileY0: Int
        let components: [Component]

        var tilesAcross: Int { (width - tileX0 + tileWidth - 1) / tileWidth }
        var tilesDown: Int { (height - tileY0 + tileHeight - 1) / tileHeight }
        var tileCount: Int { tilesAcross * tilesDown }

        init(_ body: [UInt8]) throws {
            guard body.count >= 36 else { throw JPIPError("truncated SIZ") }
            func u32(_ i: Int) -> Int { Int(body[i]) << 24 | Int(body[i + 1]) << 16 | Int(body[i + 2]) << 8 | Int(body[i + 3]) }
            width = u32(2); height = u32(6); x0 = u32(10); y0 = u32(14)
            tileWidth = u32(18); tileHeight = u32(22); tileX0 = u32(26); tileY0 = u32(30)
            let count = Int(body[34]) << 8 | Int(body[35])
            guard count > 0, body.count >= 36 + 3 * count, tileWidth > 0, tileHeight > 0,
                  width > x0, height > y0 else { throw JPIPError("invalid SIZ") }
            components = (0..<count).map {
                Component(precision: Int(body[36 + 3 * $0] & 0x7F) + 1, dx: Int(body[37 + 3 * $0]), dy: Int(body[38 + 3 * $0]))
            }
            guard components.allSatisfy({ $0.dx > 0 && $0.dy > 0 }) else { throw JPIPError("invalid SIZ subsampling") }
        }
    }

    /// Coding style parameters of COD or COC (A.6.1, A.6.2) that decide the
    /// precinct partition.
    struct Coding {
        var levels: Int
        /// log2 of the precinct width and height, per resolution.
        var precincts: [(x: Int, y: Int)]

        init(levels: Int, precincts: [(x: Int, y: Int)]) {
            self.levels = levels
            self.precincts = precincts
        }

        /// Reads SPcod or SPcoc; `hasPrecincts` comes from Scod or Scoc.
        init(_ bytes: ArraySlice<UInt8>, hasPrecincts: Bool) throws {
            let start = bytes.startIndex
            guard bytes.count >= 5 else { throw JPIPError("truncated coding style") }
            levels = Int(bytes[start])
            guard levels <= 32 else { throw JPIPError("invalid number of decomposition levels") }
            if hasPrecincts {
                guard bytes.count >= 5 + levels + 1 else { throw JPIPError("truncated precinct sizes") }
                precincts = (0...levels).map {
                    let value = bytes[start + 5 + $0]
                    return (Int(value & 0x0F), Int(value >> 4))
                }
            } else {
                precincts = Array(repeating: (15, 15), count: levels + 1)
            }
        }
    }

    struct COD {
        let flags: UInt8
        let layers: Int
        let coding: Coding
    }

    /// Marker segments of a header, with their positions for rewriting.
    struct Segments {
        var segments: [(marker: UInt8, body: [UInt8])] = []

        /// Reads marker segments until the end of `bytes` or `stop`.
        init(_ bytes: [UInt8], from start: Int) throws {
            var position = start
            while position + 4 <= bytes.count {
                guard bytes[position] == 0xFF else { throw JPIPError("marker expected at \(position)") }
                let marker = bytes[position + 1]
                let length = Int(bytes[position + 2]) << 8 | Int(bytes[position + 3])
                guard length >= 2, position + 2 + length <= bytes.count else { throw JPIPError("truncated marker segment") }
                segments.append((marker, Array(bytes[(position + 4)..<(position + 2 + length)])))
                position += 2 + length
            }
            guard position == bytes.count else { throw JPIPError("trailing bytes in a header data-bin") }
        }

        func first(_ marker: UInt8) -> [UInt8]? { segments.first { $0.marker == marker }?.body }

        static func cod(_ body: [UInt8]) throws -> COD {
            guard body.count >= 10 else { throw JPIPError("truncated COD") }
            let flags = body[0]
            return COD(flags: flags, layers: Int(body[2]) << 8 | Int(body[3]),
                       coding: try Coding(body[5...], hasPrecincts: flags & 1 != 0))
        }

        static func coc(_ body: [UInt8], components: Int) throws -> (component: Int, coding: Coding) {
            let wide = components >= 257
            guard body.count >= (wide ? 8 : 7) else { throw JPIPError("truncated COC") }
            let component = wide ? Int(body[0]) << 8 | Int(body[1]) : Int(body[0])
            let flags = body[wide ? 2 : 1]
            return (component, try Coding(body[(wide ? 3 : 2)...], hasPrecincts: flags & 1 != 0))
        }

        /// The segments as bytes, without those that become invalid once the
        /// packets are reordered, and with COD set to RPCL without SOP markers.
        func rewritten() -> [UInt8] {
            var output: [UInt8] = []
            for (marker, body) in segments {
                // TLM, PLM, PLT (packet and tile-part lengths) and POC
                // (progression changes) no longer describe the new layout.
                if [0x55, 0x57, 0x58, 0x5F].contains(marker) { continue }
                var body = body
                if marker == 0x52, body.count >= 2 {
                    body[0] &= ~0x02  // precinct data-bins hold no SOP marker segments
                    body[1] = 2       // RPCL
                }
                output += [0xFF, marker, UInt8((body.count + 2) >> 8), UInt8((body.count + 2) & 0xFF)] + body
            }
            return output
        }
    }

    /// The main header data-bin: SOC then marker segments.
    struct MainHeader {
        let bytes: [UInt8]
        let segments: Segments
        let siz: SIZ
        let cod: COD
        let coc: [Int: Coding]
        let packedHeaders: Bool

        init(_ data: Data) throws {
            bytes = [UInt8](data)
            guard bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0x4F else { throw JPIPError("the main header has no SOC") }
            segments = try Segments(bytes, from: 2)
            guard let sizBody = segments.first(0x51) else { throw JPIPError("no SIZ") }
            siz = try SIZ(sizBody)
            guard let codBody = segments.first(0x52) else { throw JPIPError("no COD") }
            cod = try Segments.cod(codBody)
            var coc: [Int: Coding] = [:]
            for segment in segments.segments where segment.marker == 0x53 {
                let (component, coding) = try Segments.coc(segment.body, components: siz.components.count)
                coc[component] = coding
            }
            self.coc = coc
            packedHeaders = segments.segments.contains { $0.marker == 0x60 }
        }

        func rewritten() throws -> [UInt8] { [0xFF, 0x4F] + segments.rewritten() }
    }

    /// The tile header data-bin: the markers of the tile-part headers, without
    /// SOT and SOD.
    struct TileHeader {
        let segments: Segments
        let cod: COD?
        let coc: [Int: Coding]
        let packedHeaders: Bool

        init(_ data: Data, components: Int) throws {
            segments = try Segments([UInt8](data), from: 0)
            cod = try segments.first(0x52).map(Segments.cod)
            var coc: [Int: Coding] = [:]
            for segment in segments.segments where segment.marker == 0x53 {
                let (component, coding) = try Segments.coc(segment.body, components: components)
                coc[component] = coding
            }
            self.coc = coc
            packedHeaders = segments.segments.contains { $0.marker == 0x61 }
        }

        /// The precedence of A.6: tile COC, tile COD, main COC, main COD.
        func coding(component: Int, main: MainHeader) -> Coding {
            coc[component] ?? cod?.coding ?? main.coc[component] ?? main.cod.coding
        }

        func rewritten() throws -> [UInt8] { segments.rewritten() }
    }

    /// The precinct partition of one tile (ISO/IEC 15444-1 B.5, B.6).
    struct TileGeometry {
        let siz: SIZ
        let coding: [Coding]
        let x0: Int, y0: Int, x1: Int, y1: Int

        init(siz: SIZ, tile: Int, coding: [Coding]) {
            self.siz = siz
            self.coding = coding
            let p = tile % siz.tilesAcross, q = tile / siz.tilesAcross
            x0 = max(siz.tileX0 + p * siz.tileWidth, siz.x0)
            y0 = max(siz.tileY0 + q * siz.tileHeight, siz.y0)
            x1 = min(siz.tileX0 + (p + 1) * siz.tileWidth, siz.width)
            y1 = min(siz.tileY0 + (q + 1) * siz.tileHeight, siz.height)
        }

        static func ceilDiv(_ a: Int, _ b: Int) -> Int { (a + b - 1) / b }

        /// The bounds of resolution `r` of component `c`, in its own grid.
        func bounds(_ c: Int, _ r: Int) -> (x0: Int, y0: Int, x1: Int, y1: Int) {
            let component = siz.components[c], scale = 1 << (coding[c].levels - r)
            let tcx0 = Self.ceilDiv(x0, component.dx), tcy0 = Self.ceilDiv(y0, component.dy)
            let tcx1 = Self.ceilDiv(x1, component.dx), tcy1 = Self.ceilDiv(y1, component.dy)
            return (Self.ceilDiv(tcx0, scale), Self.ceilDiv(tcy0, scale), Self.ceilDiv(tcx1, scale), Self.ceilDiv(tcy1, scale))
        }

        /// Precincts across and down at resolution `r` of component `c`.
        func precinctCounts(_ c: Int, _ r: Int) -> (across: Int, down: Int) {
            let (rx0, ry0, rx1, ry1) = bounds(c, r)
            let px = coding[c].precincts[r].x, py = coding[c].precincts[r].y
            let across = rx1 > rx0 ? Self.ceilDiv(rx1, 1 << px) - (rx0 >> px) : 0
            let down = ry1 > ry0 ? Self.ceilDiv(ry1, 1 << py) - (ry0 >> py) : 0
            return (across, down)
        }

        /// The sequence number of a precinct within its tile-component,
        /// counted from the lowest resolution (ISO/IEC 15444-9 A.3.2.1).
        func precinctSequence(component c: Int, resolution r: Int, precinct: Int) -> Int {
            var sequence = precinct
            for lower in 0..<r {
                let counts = precinctCounts(c, lower)
                sequence += counts.across * counts.down
            }
            return sequence
        }

        /// The precincts in the order of the RPCL progression (B.12.1.3).
        func rpcl() -> [(component: Int, resolution: Int, precinct: Int)] {
            var order: [(Int, Int, Int)] = []
            let maxLevels = coding.map(\.levels).max() ?? 0
            // The steps are the smallest precinct sizes on the reference grid.
            var dx = Int.max, dy = Int.max
            for c in coding.indices {
                for r in 0...coding[c].levels {
                    let level = coding[c].levels - r
                    dx = min(dx, siz.components[c].dx << (coding[c].precincts[r].x + level))
                    dy = min(dy, siz.components[c].dy << (coding[c].precincts[r].y + level))
                }
            }
            for r in 0...maxLevels {
                var y = y0
                while y < y1 {
                    var x = x0
                    while x < x1 {
                        for c in coding.indices where r <= coding[c].levels {
                            let level = coding[c].levels - r
                            let component = siz.components[c]
                            let (rx0, ry0, rx1, ry1) = bounds(c, r)
                            guard rx1 > rx0, ry1 > ry0 else { continue }
                            let px = coding[c].precincts[r].x, py = coding[c].precincts[r].y
                            let rpx = px + level, rpy = py + level
                            let onRow = y % (component.dy << rpy) == 0 || (y == y0 && ((ry0 << level) % (1 << rpy)) != 0)
                            let onColumn = x % (component.dx << rpx) == 0 || (x == x0 && ((rx0 << level) % (1 << rpx)) != 0)
                            guard onRow, onColumn else { continue }
                            let i = (Self.ceilDiv(x, component.dx << level) >> px) - (rx0 >> px)
                            let j = (Self.ceilDiv(y, component.dy << level) >> py) - (ry0 >> py)
                            let across = precinctCounts(c, r).across
                            order.append((c, r, i + j * across))
                        }
                        x += dx - (x % dx)
                    }
                    y += dy - (y % dy)
                }
            }
            return order
        }
    }
}
