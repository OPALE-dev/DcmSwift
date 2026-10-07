import Foundation

/// The headers of a JPEG 2000 codestream as far as the JPEG 2000 Part 2
/// multiple component transformation needs them (ISO/IEC 15444-2 A.2, A.3.6
/// to A.3.9): image and tile geometry, codestream and output components, the
/// wavelet of each tile-component, and the MCT, MCC and MCO segments of the
/// main header and of each tile's first tile-part header.
///
/// `partOneBytes` is the same codestream rewritten so that a Part 1 decoder
/// returns the codestream components; every segment and tile-part keeps its
/// length:
/// - Rsiz becomes 0, and the COD multiple component transformation type
///   becomes 0 where it signals a Part 2 transform;
/// - the CBD, MCT, MCC and MCO marker codes become COM;
/// - with a multiple component transformation, SIZ declares the codestream
///   components signed and wider (`decodedComponents`), because Annex J
///   applies no DC level shift and a Part 1 decoder clamps to the declared
///   range. A reversible tile-component decodes to the same values; an
///   irreversible one decodes scaled by 2^(added bits), as its quantization
///   step sizes scale with the nominal dynamic range (ISO/IEC 15444-1 E.1.1),
///   which keeps fractional bits for the inverse transform.
struct JPEG2000Codestream {
    struct Component: Equatable {
        let precision: Int
        let isSigned: Bool
        let horizontalSeparation: Int
        let verticalSeparation: Int
    }

    /// The MCT arrays (keyed by the ten low bits of Imct), the MCC records
    /// (keyed by Imcc), and the MCO stage order of one header, with every
    /// series of segments concatenated in Zmct/Zmcc order (Annex J.2), and
    /// the coding style values that matter here.
    struct TransformSegments {
        var arrays: [Int: [Double]] = [:]
        var collections: [Int: (count: Int, records: [UInt8])] = [:]
        var stageOrder: [Int]?
        /// SGcod multiple component transformation type of a COD segment.
        var transformType: Int?
        /// SPcod wavelet transformation of a COD segment (0: 9-7, 1: 5-3).
        var wavelet: Int?
        /// SPcoc wavelet transformation of COC segments, by component.
        var componentWavelets: [Int: Int] = [:]

        var definesTransform: Bool { stageOrder != nil || !collections.isEmpty || !arrays.isEmpty }
    }

    static let partTwoCapability = 0x8000
    static let multipleComponentCapability = 0x0100

    let capabilities: Int
    let imageOrigin: (x: Int, y: Int)
    let imageEnd: (x: Int, y: Int)
    let tileSize: (width: Int, height: Int)
    let tileOrigin: (x: Int, y: Int)
    let components: [Component]
    /// The codestream components as `partOneBytes` declares them.
    let decodedComponents: [Component]
    /// Reconstructed image components (CBD), when a CBD segment is present.
    let outputComponents: [Component]?
    let main: TransformSegments
    /// First tile-part headers, by tile index.
    let tiles: [Int: TransformSegments]
    let partOneBytes: [UInt8]

    var tileColumns: Int { (imageEnd.x - tileOrigin.x + tileSize.width - 1) / tileSize.width }
    var tileRows: Int { (imageEnd.y - tileOrigin.y + tileSize.height - 1) / tileSize.height }

    var usesMultipleComponentTransformCapability: Bool {
        Self.usesMultipleComponentTransform(capabilities)
    }

    private static func usesMultipleComponentTransform(_ capabilities: Int) -> Bool {
        capabilities & (partTwoCapability | 0x4000) == partTwoCapability
            && capabilities & multipleComponentCapability != 0
    }

    /// The image area covered by a tile, relative to the image origin
    /// (ISO/IEC 15444-1 B.3).
    func tileArea(_ index: Int) -> (x: Range<Int>, y: Range<Int>) {
        let p = index % tileColumns, q = index / tileColumns
        let x0 = max(tileOrigin.x + p * tileSize.width, imageOrigin.x)
        let x1 = min(tileOrigin.x + (p + 1) * tileSize.width, imageEnd.x)
        let y0 = max(tileOrigin.y + q * tileSize.height, imageOrigin.y)
        let y1 = min(tileOrigin.y + (q + 1) * tileSize.height, imageEnd.y)
        return ((x0 - imageOrigin.x)..<(x1 - imageOrigin.x), (y0 - imageOrigin.y)..<(y1 - imageOrigin.y))
    }

    /// Whether a tile-component uses the reversible 5-3 wavelet.
    func isReversible(tile: Int, component: Int) -> Bool {
        let segments = tiles[tile]
        let wavelet = segments?.componentWavelets[component] ?? segments?.wavelet
            ?? main.componentWavelets[component] ?? main.wavelet ?? 1
        return wavelet == 1
    }

    /// The factor a Part 1 decoder of `partOneBytes` multiplies the samples
    /// of a tile-component by.
    func decodedScale(tile: Int, component: Int) -> Double {
        isReversible(tile: tile, component: component)
            ? 1 : Double(1 << (decodedComponents[component].precision - components[component].precision))
    }

    /// Parses a raw codestream starting with SOC.
    init(_ bytes: [UInt8]) throws {
        func fail(_ reason: String) -> DICOMCodecError { .corruptedData("JPEG 2000 codestream: \(reason)") }
        func u16(_ at: Int) -> Int { Int(bytes[at]) << 8 | Int(bytes[at + 1]) }
        func u32(_ at: Int) -> Int { u16(at) << 16 | u16(at + 2) }

        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0x4F, bytes[2] == 0xFF, bytes[3] == 0x51 else {
            throw fail("missing SOC and SIZ")
        }
        var output = bytes

        // SIZ (ISO/IEC 15444-1 A.5.1).
        let siz = 2
        guard siz + 40 <= bytes.count else { throw fail("truncated SIZ") }
        let sizLength = u16(siz + 2)
        let componentCount = u16(siz + 38)
        guard componentCount > 0, sizLength == 38 + 3 * componentCount, siz + 2 + sizLength <= bytes.count else {
            throw fail("invalid SIZ")
        }
        capabilities = u16(siz + 4)
        imageEnd = (u32(siz + 6), u32(siz + 10))
        imageOrigin = (u32(siz + 14), u32(siz + 18))
        tileSize = (u32(siz + 22), u32(siz + 26))
        tileOrigin = (u32(siz + 30), u32(siz + 34))
        guard imageEnd.x > imageOrigin.x, imageEnd.y > imageOrigin.y, tileSize.width > 0, tileSize.height > 0,
              tileOrigin.x <= imageOrigin.x, tileOrigin.y <= imageOrigin.y else {
            throw fail("invalid image or tile geometry")
        }
        components = (0..<componentCount).map { index in
            let at = siz + 40 + 3 * index
            return Component(
                precision: Int(bytes[at] & 0x7F) + 1, isSigned: bytes[at] & 0x80 != 0,
                horizontalSeparation: Int(bytes[at + 1]), verticalSeparation: Int(bytes[at + 2]))
        }
        guard components.allSatisfy({ $0.precision <= 30 }) else { throw fail("component precision above 30 bits") }
        if capabilities & (Self.partTwoCapability | 0x4000) == Self.partTwoCapability {
            output[siz + 4] = 0
            output[siz + 5] = 0
        }
        // The COC component index takes two bytes beyond 256 components.
        let componentIndexWidth = componentCount < 257 ? 1 : 2
        var position = siz + 2 + sizLength

        var mainParser = HeaderParser()
        var tiles: [Int: TransformSegments] = [:]
        var outputComponents: [Component]?
        var tile: (index: Int, first: Bool, end: Int)?
        var current = HeaderParser()

        while position + 2 <= bytes.count {
            guard bytes[position] == 0xFF else { throw fail("expected a marker at offset \(position)") }
            let marker = bytes[position + 1]
            if marker == 0xD9 { break }  // EOC
            if marker == 0x93 {  // SOD: skip the tile-part body.
                guard let open = tile else { throw fail("SOD outside a tile-part") }
                if open.first { tiles[open.index] = try current.segments() }
                tile = nil
                if open.end == 0 { break }
                position = open.end
                continue
            }
            guard position + 4 <= bytes.count else { throw fail("truncated marker segment") }
            let length = u16(position + 2)
            let body = position + 4
            let end = position + 2 + length
            guard length >= 2, end <= bytes.count else { throw fail("marker segment overruns the data") }
            let payload = bytes[body..<end]

            switch marker {
            case 0x90:  // SOT
                guard tile == nil, length == 10 else { throw fail("invalid SOT") }
                let psot = u32(body + 2)
                guard psot == 0 || (psot >= 14 && position + psot <= bytes.count) else {
                    throw fail("tile-part length \(psot) overruns the data")
                }
                tile = (u16(body), bytes[body + 6] == 0, psot == 0 ? 0 : position + psot)
                current = HeaderParser()
            case 0x52:  // COD: Scod, SGcod (order, layers, transform), SPcod.
                guard payload.count >= 10 else { throw fail("truncated COD") }
                let type = Int(bytes[body + 4]), wavelet = Int(bytes[body + 9])
                if tile == nil {
                    mainParser.transformType = type
                    mainParser.wavelet = wavelet
                } else {
                    current.transformType = type
                    current.wavelet = wavelet
                }
                if type & 0x06 != 0 { output[body + 4] = 0 }
            case 0x53:  // COC: Ccoc, Scoc, SPcoc.
                guard payload.count >= componentIndexWidth + 6 else { throw fail("truncated COC") }
                let component = componentIndexWidth == 1 ? Int(bytes[body]) : u16(body)
                let wavelet = Int(bytes[body + componentIndexWidth + 5])
                if tile == nil {
                    mainParser.componentWavelets[component] = wavelet
                } else {
                    current.componentWavelets[component] = wavelet
                }
            case 0x78:  // CBD
                guard tile == nil, payload.count >= 2 else { throw fail("CBD outside the main header") }
                let count = u16(body) & 0x7FFF
                let shared = u16(body) & 0x8000 != 0
                guard count > 0, payload.count == 2 + (shared ? 1 : count) else { throw fail("invalid CBD") }
                outputComponents = (0..<count).map { index in
                    let value = bytes[body + 2 + (shared ? 0 : index)]
                    return Component(
                        precision: Int(value & 0x7F) + 1, isSigned: value & 0x80 != 0,
                        horizontalSeparation: 1, verticalSeparation: 1)
                }
                output[position + 1] = 0x64
            case 0x74, 0x75, 0x77:  // MCT, MCC, MCO
                if tile == nil {
                    try mainParser.read(marker: marker, Array(payload))
                } else {
                    try current.read(marker: marker, Array(payload))
                }
                output[position + 1] = 0x64
            default:
                break
            }
            position = end
        }

        let main = try mainParser.segments()
        self.main = main
        self.tiles = tiles
        self.outputComponents = outputComponents

        // Signed and wider codestream components: 30 bits where every tile
        // uses the 5-3 wavelet, 8 more bits (scaling the samples) otherwise.
        if Self.usesMultipleComponentTransform(capabilities) {
            let headers = [main] + Array(tiles.values)
            decodedComponents = components.enumerated().map { index, component in
                let reversible = headers.allSatisfy { header -> Bool in
                    let tileWavelet: Int? = header.componentWavelets[index] ?? header.wavelet
                    let mainWavelet: Int = main.componentWavelets[index] ?? main.wavelet ?? 1
                    return (tileWavelet ?? mainWavelet) == 1
                }
                let precision = reversible ? 30 : min(component.precision + 8, 30)
                return Component(
                    precision: precision, isSigned: true, horizontalSeparation: component.horizontalSeparation,
                    verticalSeparation: component.verticalSeparation)
            }
            for (index, component) in decodedComponents.enumerated() {
                output[siz + 40 + 3 * index] = 0x80 | UInt8(component.precision - 1)
            }
        } else {
            decodedComponents = components
        }
        partOneBytes = output
    }
}

/// Collects the MCT, MCC and MCO segments of one header and concatenates
/// each series (Annex J.2).
private struct HeaderParser {
    var arrays: [Int: [(z: Int, data: ArraySlice<UInt8>)]] = [:]
    var collections: [Int: [(z: Int, data: ArraySlice<UInt8>)]] = [:]
    var collectionCounts: [Int: Int] = [:]
    var stageOrder: [Int]?
    var transformType: Int?
    var wavelet: Int?
    var componentWavelets: [Int: Int] = [:]

    mutating func read(marker: UInt8, _ payload: [UInt8]) throws {
        func fail(_ reason: String) -> DICOMCodecError { .corruptedData("JPEG 2000 codestream: \(reason)") }
        func u16(_ at: Int) -> Int { Int(payload[at]) << 8 | Int(payload[at + 1]) }
        switch marker {
        case 0x74:  // MCT: Zmct, Imct, Ymct (first segment only), SPmct.
            guard payload.count >= 4 else { throw fail("truncated MCT") }
            let z = u16(0)
            let start = z == 0 ? 6 : 4
            guard payload.count >= start else { throw fail("truncated MCT") }
            arrays[u16(2), default: []].append((z, payload[start...]))
        case 0x75:  // MCC: Zmcc, Imcc, Ymcc and Qmcc (first segment only), records.
            guard payload.count >= 3 else { throw fail("truncated MCC") }
            let z = u16(0)
            let index = Int(payload[2])
            if z == 0 {
                guard payload.count >= 7 else { throw fail("truncated MCC") }
                collectionCounts[index] = u16(5)
                collections[index, default: []].append((z, payload[7...]))
            } else {
                collections[index, default: []].append((z, payload[3...]))
            }
        case 0x77:  // MCO
            guard let count = payload.first, payload.count == 1 + Int(count) else { throw fail("invalid MCO") }
            stageOrder = payload.dropFirst().map(Int.init)
        default:
            break
        }
    }

    func segments() throws -> JPEG2000Codestream.TransformSegments {
        func fail(_ reason: String) -> DICOMCodecError { .corruptedData("JPEG 2000 codestream: \(reason)") }
        func joined(_ series: [(z: Int, data: ArraySlice<UInt8>)]) throws -> [UInt8] {
            let sorted = series.sorted { $0.z < $1.z }
            guard sorted.enumerated().allSatisfy({ $0.offset == $0.element.z }) else {
                throw fail("incomplete MCT or MCC series")
            }
            return sorted.flatMap { Array($0.data) }
        }

        var result = JPEG2000Codestream.TransformSegments()
        result.stageOrder = stageOrder
        result.transformType = transformType
        result.wavelet = wavelet
        result.componentWavelets = componentWavelets
        for (imct, series) in arrays {
            let data = try joined(series)
            let width = [2, 4, 4, 8][(imct >> 10) & 3]
            guard data.count % width == 0 else { throw fail("MCT array \(imct & 0xFF) has a partial element") }
            result.arrays[imct & 0x3FF] = stride(from: 0, to: data.count, by: width).map { at in
                let bits = (0..<width).reduce(UInt64(0)) { $0 << 8 | UInt64(data[at + $1]) }
                switch (imct >> 10) & 3 {
                case 0: return Double(Int16(truncatingIfNeeded: bits))
                case 1: return Double(Int32(truncatingIfNeeded: bits))
                case 2: return Double(Float(bitPattern: UInt32(truncatingIfNeeded: bits)))
                default: return Double(bitPattern: bits)
                }
            }
        }
        for (imcc, series) in collections {
            guard let count = collectionCounts[imcc] else { throw fail("MCC \(imcc) series lacks its first segment") }
            result.collections[imcc] = (count, try joined(series))
        }
        return result
    }
}
