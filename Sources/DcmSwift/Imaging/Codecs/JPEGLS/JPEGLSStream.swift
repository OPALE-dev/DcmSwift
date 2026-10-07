import Foundation

/// The marker structure of an ITU-T T.87 (ISO/IEC 14495-1) JPEG-LS stream:
/// the SOF55 frame header, LSE preset parameters, APP8 color transform, and
/// the scans with their entropy-coded data.
struct JPEGLSStream {
    struct Component {
        let identifier: UInt8
        let horizontalSampling: Int
        let verticalSampling: Int
    }

    struct Frame {
        let precision: Int
        let lines: Int
        let samplesPerLine: Int
        let components: [Component]

        /// Component dimensions (T.87 relies on T.81 A.1.1).
        func size(of index: Int) -> (width: Int, height: Int) {
            let maxH = components.map(\.horizontalSampling).max()!
            let maxV = components.map(\.verticalSampling).max()!
            let component = components[index]
            return ((samplesPerLine * component.horizontalSampling + maxH - 1) / maxH,
                    (lines * component.verticalSampling + maxV - 1) / maxV)
        }
    }

    enum InterleaveMode: Int {
        case none = 0
        case line = 1
        case sample = 2
    }

    /// LSE preset coding parameters (C.2.4.1.1); zero selects the default.
    struct PresetParameters: Equatable {
        var maximumValue = 0
        var threshold1 = 0
        var threshold2 = 0
        var threshold3 = 0
        var reset = 0
    }

    /// The parameters in force for one scan, with defaults resolved.
    struct CodingParameters: Equatable {
        let maximumValue: Int
        let near: Int
        let threshold1: Int
        let threshold2: Int
        let threshold3: Int
        let reset: Int

        init(precision: Int, near: Int, preset: PresetParameters) throws {
            let maximum = preset.maximumValue != 0 ? preset.maximumValue : (1 << precision) - 1
            guard maximum >= 1, maximum < 1 << precision else {
                throw DICOMCodecError.corruptedData("JPEG-LS MAXVAL \(maximum)")
            }
            guard near >= 0, near <= min(255, maximum / 2) else {
                throw DICOMCodecError.corruptedData("JPEG-LS NEAR \(near)")
            }
            let defaults = Self.defaultThresholds(maximum: maximum, near: near)
            let t1 = preset.threshold1 != 0 ? preset.threshold1 : defaults.0
            let t2 = preset.threshold2 != 0 ? preset.threshold2 : defaults.1
            let t3 = preset.threshold3 != 0 ? preset.threshold3 : defaults.2
            let reset = preset.reset != 0 ? preset.reset : 64
            guard t1 >= near + 1, t1 <= maximum, t2 >= t1, t2 <= maximum, t3 >= t2, t3 <= maximum,
                  reset >= 3, reset <= max(255, maximum) else {
                throw DICOMCodecError.corruptedData("JPEG-LS preset parameters are invalid")
            }
            maximumValue = maximum
            self.near = near
            threshold1 = t1
            threshold2 = t2
            threshold3 = t3
            self.reset = reset
        }

        /// Default thresholds T1, T2, T3 (T.87 C.2.4.1.1.1).
        static func defaultThresholds(maximum: Int, near: Int) -> (Int, Int, Int) {
            func clamp(_ value: Int, _ low: Int) -> Int { value > maximum || value < low ? low : value }
            if maximum >= 128 {
                let factor = (min(maximum, 4095) + 128) / 256
                let t1 = clamp(factor * (3 - 2) + 2 + 3 * near, near + 1)
                let t2 = clamp(factor * (7 - 3) + 3 + 5 * near, t1)
                return (t1, t2, clamp(factor * (21 - 4) + 4 + 7 * near, t2))
            }
            let factor = 256 / (maximum + 1)
            let t1 = clamp(max(2, 3 / factor + 3 * near), near + 1)
            let t2 = clamp(max(3, 7 / factor + 5 * near), t1)
            return (t1, t2, clamp(max(4, 21 / factor + 7 * near), t2))
        }
    }

    struct Scan {
        /// Frame component indices, in scan order.
        let components: [Int]
        let interleave: InterleaveMode
        let parameters: CodingParameters
        /// Lines (or line groups) per restart interval, 0 for none.
        let restartInterval: Int
        /// The entropy-coded data, including RST markers.
        let data: Range<Int>
    }

    /// HP (APP8 "mrfx") inverse color transforms, outside T.87 proper.
    enum ColorTransform: Int {
        case none = 0
        case hp1 = 1
        case hp2 = 2
        case hp3 = 3
    }

    let bytes: [UInt8]
    let frame: Frame
    let scans: [Scan]
    let colorTransform: ColorTransform

    init(_ bytes: [UInt8]) throws {
        func fail(_ reason: String) -> DICOMCodecError { .corruptedData("JPEG-LS \(reason)") }

        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { throw fail("stream does not start with SOI") }
        self.bytes = bytes
        var position = 2
        var frame: Frame?
        var scans: [Scan] = []
        var preset = PresetParameters()
        var restartInterval = 0
        var colorTransform = ColorTransform.none

        func uint16(_ at: Int) -> Int { Int(bytes[at]) << 8 | Int(bytes[at + 1]) }

        markers: while true {
            while position + 1 < bytes.count, bytes[position] == 0xFF, bytes[position + 1] == 0xFF { position += 1 }
            guard position + 1 < bytes.count, bytes[position] == 0xFF else {
                throw fail("expected a marker at byte \(position)")
            }
            let marker = bytes[position + 1]
            position += 2
            if marker == 0xD9 { break markers }
            guard position + 2 <= bytes.count else { throw fail("marker segment is truncated") }
            let length = uint16(position)
            guard length >= 2, position + length <= bytes.count else { throw fail("marker segment length is invalid") }
            let segment = (position + 2)..<(position + length)
            position += length

            switch marker {
            case 0xF7:
                guard frame == nil else { throw fail("has several frame headers") }
                guard segment.count >= 6 else { throw fail("frame header is truncated") }
                let precision = Int(bytes[segment.lowerBound])
                let count = Int(bytes[segment.lowerBound + 5])
                guard (2...16).contains(precision), count >= 1, segment.count == 6 + 3 * count else {
                    throw fail("frame header is invalid")
                }
                let components = (0..<count).map { index -> Component in
                    let base = segment.lowerBound + 6 + 3 * index
                    return Component(
                        identifier: bytes[base],
                        horizontalSampling: Int(bytes[base + 1] >> 4),
                        verticalSampling: Int(bytes[base + 1] & 0x0F))
                }
                guard components.allSatisfy({ (1...4).contains($0.horizontalSampling) && (1...4).contains($0.verticalSampling) }),
                      Set(components.map(\.identifier)).count == count else {
                    throw fail("frame components are invalid")
                }
                let lines = uint16(segment.lowerBound + 1), samples = uint16(segment.lowerBound + 3)
                guard lines > 0, samples > 0 else {
                    throw DICOMCodecError.unsupportedImage("JPEG-LS frames without dimensions (DNL) are not supported")
                }
                frame = Frame(precision: precision, lines: lines, samplesPerLine: samples, components: components)

            case 0xC0...0xCF where marker != 0xC4 && marker != 0xC8 && marker != 0xCC:
                throw DICOMCodecError.unsupportedImage("SOF\(marker & 0x0F) is not a JPEG-LS frame")

            case 0xF8:
                // LSE (C.2.4.1): only preset coding parameters are supported.
                guard segment.count >= 1 else { throw fail("LSE segment is truncated") }
                switch bytes[segment.lowerBound] {
                case 1:
                    guard segment.count == 11 else { throw fail("LSE preset parameters are invalid") }
                    let base = segment.lowerBound + 1
                    preset = PresetParameters(
                        maximumValue: uint16(base), threshold1: uint16(base + 2), threshold2: uint16(base + 4),
                        threshold3: uint16(base + 6), reset: uint16(base + 8))
                case 2, 3:
                    // Mapping tables are only an error if a scan selects one.
                    break
                default:
                    throw DICOMCodecError.unsupportedImage("JPEG-LS LSE type \(bytes[segment.lowerBound])")
                }

            case 0xDD:
                guard segment.count == 2 || segment.count == 4 else { throw fail("restart interval is invalid") }
                restartInterval = segment.count == 2 ? uint16(segment.lowerBound)
                    : Int(uint16(segment.lowerBound)) << 16 | uint16(segment.lowerBound + 2)

            case 0xE8:
                let payload = Array(bytes[segment])
                if payload.count == 5, payload.starts(with: Array("mrfx".utf8)) {
                    guard let transform = ColorTransform(rawValue: Int(payload[4])) else {
                        throw DICOMCodecError.unsupportedImage("JPEG-LS color transform \(payload[4])")
                    }
                    colorTransform = transform
                }

            case 0xDA:
                guard let frame else { throw fail("scan precedes the frame header") }
                guard segment.count >= 1 else { throw fail("scan header is truncated") }
                let count = Int(bytes[segment.lowerBound])
                guard count >= 1, count <= 4, segment.count == 4 + 2 * count else { throw fail("scan header is invalid") }
                let components = try (0..<count).map { index -> Int in
                    let base = segment.lowerBound + 1 + 2 * index
                    guard let component = frame.components.firstIndex(where: { $0.identifier == bytes[base] }) else {
                        throw fail("scan refers to an unknown component")
                    }
                    guard bytes[base + 1] == 0 else {
                        throw DICOMCodecError.unsupportedImage("JPEG-LS mapping tables are not supported")
                    }
                    return component
                }
                guard Set(components).count == count else { throw fail("scan repeats a component") }
                let tail = segment.upperBound - 3
                guard let interleave = InterleaveMode(rawValue: Int(bytes[tail + 1])),
                      (interleave == .none) == (count == 1) else {
                    throw fail("interleave mode \(bytes[tail + 1]) does not match \(count) components")
                }
                guard bytes[tail + 2] == 0 else {
                    throw DICOMCodecError.unsupportedImage("JPEG-LS point transform \(bytes[tail + 2])")
                }
                if interleave == .sample {
                    let first = frame.components[components[0]]
                    guard components.allSatisfy({
                        frame.components[$0].horizontalSampling == first.horizontalSampling
                            && frame.components[$0].verticalSampling == first.verticalSampling
                    }) else {
                        throw DICOMCodecError.unsupportedImage("JPEG-LS sample interleaving of subsampled components")
                    }
                }
                let parameters = try CodingParameters(
                    precision: frame.precision, near: Int(bytes[tail]), preset: preset)
                let end = Self.endOfScan(in: bytes, from: position)
                scans.append(Scan(
                    components: components, interleave: interleave, parameters: parameters,
                    restartInterval: restartInterval, data: position..<end))
                position = end

            case 0xDC:
                throw DICOMCodecError.unsupportedImage("JPEG-LS DNL markers are not supported")

            default:
                break
            }

            if position >= bytes.count { break markers }
        }

        guard let frame else { throw fail("has no frame header") }
        guard !scans.isEmpty else { throw fail("has no scan") }
        let covered = scans.flatMap(\.components)
        guard covered.count == frame.components.count, Set(covered).count == covered.count else {
            throw fail("scans do not cover every component once")
        }
        self.frame = frame
        self.scans = scans
        self.colorTransform = colorTransform
    }

    /// The first marker after the scan data: FFH followed by a byte with its
    /// high bit set (T.87 9.1), other than RST.
    private static func endOfScan(in bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index + 1 < bytes.count {
            if bytes[index] == 0xFF, bytes[index + 1] >= 0x80, !(0xD0...0xD7).contains(bytes[index + 1]) {
                return index
            }
            index += 1
        }
        return bytes.count
    }
}
