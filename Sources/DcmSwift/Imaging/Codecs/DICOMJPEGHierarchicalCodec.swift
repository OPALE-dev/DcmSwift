import Foundation

/// The retired JPEG hierarchical Transfer Syntaxes (Processes 16 to 29),
/// decoded per ITU-T T.81 Annex J. The first frame is any non-differential
/// DCT or lossless frame; each following differential frame codes the
/// difference from the previous reconstruction, optionally expanded by two
/// horizontally and vertically (EXP marker, J.1.1.2).
///
/// Differential DCT frames are reconstructed without range limiting until
/// the last frame, and differential lossless frames modulo 2^16, as in the
/// ISO reference implementation (libjpeg by Thomas Richter). Color frames
/// with a DCT frame are converted from YCbCr to RGB like the non-hierarchical
/// DCT decoder; purely lossless streams keep their samples unchanged.
public struct DICOMJPEGHierarchicalCodec: DICOMPixelDataDecoder {
    /// Retired: Extended, Hierarchical (Process 16 & 18).
    public static let extendedHuffman = "1.2.840.10008.1.2.4.59"
    /// Retired: Extended, Hierarchical (Process 17 & 19).
    public static let extendedArithmetic = "1.2.840.10008.1.2.4.60"
    /// Retired: Spectral Selection, Hierarchical (Process 20 & 22).
    public static let spectralSelectionHuffman = "1.2.840.10008.1.2.4.61"
    /// Retired: Spectral Selection, Hierarchical (Process 21 & 23).
    public static let spectralSelectionArithmetic = "1.2.840.10008.1.2.4.62"
    /// Retired: Full Progression, Hierarchical (Process 24 & 26).
    public static let fullProgressionHuffman = "1.2.840.10008.1.2.4.63"
    /// Retired: Full Progression, Hierarchical (Process 25 & 27).
    public static let fullProgressionArithmetic = "1.2.840.10008.1.2.4.64"
    /// Retired: Lossless, Hierarchical (Process 28).
    public static let losslessHuffman = "1.2.840.10008.1.2.4.65"
    /// Retired: Lossless, Hierarchical (Process 29).
    public static let losslessArithmetic = "1.2.840.10008.1.2.4.66"
    public var transferSyntaxUIDs: Set<String> {
        [Self.extendedHuffman, Self.extendedArithmetic, Self.spectralSelectionHuffman,
         Self.spectralSelectionArithmetic, Self.fullProgressionHuffman, Self.fullProgressionArithmetic,
         Self.losslessHuffman, Self.losslessArithmetic]
    }

    public init() {}

    public func decode(_ encodedFrame: Data, description: DICOMPixelDescription) throws -> DICOMDecodedFrame {
        let bytes = [UInt8](encodedFrame)
        let stream = try JPEGStream(bytes)
        guard stream.hierarchy != nil else {
            // Some writers label single-frame streams with these syntaxes.
            if [3, 11].contains(stream.frame.process) {
                return try DICOMJPEGLosslessCodec().decode(encodedFrame, description: description)
            }
            return try DICOMJPEGBaselineCodec().decode(encodedFrame, description: description)
        }
        return try decode(stream, bytes: bytes, description: description)
    }

    /// One component's reconstruction, cropped to its own dimensions.
    private struct Plane {
        var width: Int
        var height: Int
        var samples: [Int]
    }

    private static func isLossless(_ process: UInt8) -> Bool { [3, 7, 11, 15].contains(process) }

    func decode(_ stream: JPEGStream, bytes: [UInt8], description: DICOMPixelDescription) throws -> DICOMDecodedFrame {
        guard let hierarchy = stream.hierarchy else {
            throw DICOMCodecError.corruptedData("JPEG stream has no DHP marker")
        }
        let precision = hierarchy.precision
        guard hierarchy.lines == description.rows, hierarchy.samplesPerLine == description.columns,
              hierarchy.components.count == description.samplesPerPixel,
              hierarchy.components.count == 1 || hierarchy.components.count == 3 else {
            throw DICOMCodecError.corruptedData(
                "JPEG hierarchy is \(hierarchy.samplesPerLine)x\(hierarchy.lines)x\(hierarchy.components.count), image is "
                    + "\(description.columns)x\(description.rows)x\(description.samplesPerPixel)")
        }
        let cellBytes = description.bitsAllocated / 8
        guard (2...16).contains(precision), cellBytes == 1 || cellBytes == 2, precision <= description.bitsAllocated else {
            throw DICOMCodecError.unsupportedImage("\(precision)-bit JPEG in \(description.bitsAllocated) bits allocated")
        }
        for level in stream.frames {
            let frame = level.frame
            guard frame.precision == precision,
                  frame.components.map(\.identifier) == hierarchy.components.map(\.identifier),
                  zip(frame.components, hierarchy.components).allSatisfy({
                      $0.horizontalSampling == $1.horizontalSampling && $0.verticalSampling == $1.verticalSampling
                  }) else {
                throw DICOMCodecError.corruptedData("JPEG hierarchical frame does not match the DHP marker")
            }
            guard frame.lines > 0, frame.samplesPerLine > 0 else {
                throw DICOMCodecError.corruptedData("JPEG frame dimensions are invalid")
            }
            guard Self.isLossless(frame.process) || precision == 8 || precision == 12 else {
                throw DICOMCodecError.corruptedData("JPEG DCT precision \(precision)")
            }
        }
        guard let last = stream.frames.last?.frame,
              last.lines == hierarchy.lines, last.samplesPerLine == hierarchy.samplesPerLine else {
            throw DICOMCodecError.corruptedData("JPEG last frame does not have the DHP dimensions")
        }

        var planes = try decodeFirst(stream.frames[0])
        for level in stream.frames.dropFirst() {
            planes = try decodeDifferential(level, reference: planes)
        }

        let maximum = (1 << precision) - 1
        let clamped = planes.map { plane in
            JPEGSamplePlane(
                width: plane.width, height: plane.height, stride: plane.width,
                samples: plane.samples.map { UInt16($0 < 0 ? 0 : ($0 > maximum ? maximum : $0)) })
        }

        var photometric = description.photometricInterpretation
        let output: [UInt16]
        if clamped.count == 1 {
            output = clamped[0].samples
        } else if stream.frames.allSatisfy({ Self.isLossless($0.frame.process) }) {
            guard clamped.allSatisfy({ $0.width == last.samplesPerLine && $0.height == last.lines }) else {
                throw DICOMCodecError.unsupportedImage("subsampled JPEG Lossless components")
            }
            let count = last.samplesPerLine * last.lines
            var interleaved = [UInt16](repeating: 0, count: count * 3)
            for pixel in 0..<count {
                for component in 0..<3 { interleaved[pixel * 3 + component] = clamped[component].samples[pixel] }
            }
            output = interleaved
        } else {
            let pixels = try JPEGDCTDecoder(frame: last).upsample(clamped)
            output = DICOMJPEGBaselineCodec.isYCbCr(bytes, frame: last)
                ? DICOMJPEGBaselineCodec.ycbcrToRGB(pixels, count: last.lines * last.samplesPerLine, precision: precision)
                : pixels
            photometric = .rgb
        }

        var data = [UInt8](repeating: 0, count: output.count * cellBytes)
        for (index, value) in output.enumerated() {
            data[index * cellBytes] = UInt8(value & 0xFF)
            if cellBytes == 2 { data[index * cellBytes + 1] = UInt8(value >> 8) }
        }
        return DICOMDecodedFrame(
            description: description.decodedFrame(photometricInterpretation: photometric, planarConfiguration: 0),
            data: Data(data))
    }

    /// Component dimensions of a frame (T.81 A.1.1).
    private static func componentSize(_ frame: JPEGStream.Frame, _ index: Int) -> (width: Int, height: Int) {
        let maxH = frame.components.map(\.horizontalSampling).max()!
        let maxV = frame.components.map(\.verticalSampling).max()!
        let component = frame.components[index]
        return ((frame.samplesPerLine * component.horizontalSampling + maxH - 1) / maxH,
                (frame.lines * component.verticalSampling + maxV - 1) / maxV)
    }

    /// The non-differential first frame, as reconstructed samples.
    private func decodeFirst(_ level: JPEGStream.HierarchicalFrame) throws -> [Plane] {
        let frame = level.frame
        switch frame.process {
        case 0, 1, 2, 9, 10:
            var decoder = try decodeCoefficients(level)
            decoder.differential = false
            let samples = try decoder.samplePlanes(quantization: level.scans.last!.quantizationTables)
            return samples.map { plane in
                Plane(width: plane.width, height: plane.height,
                      samples: plane.croppedSamples(width: plane.width, height: plane.height).map(Int.init))
            }
        case 3, 11:
            let (raw, shifts) = try decodeLossless(level, differential: false)
            return zip(raw, shifts).map { values, shift in
                Plane(width: frame.samplesPerLine, height: frame.lines, samples: values.map { $0 << shift })
            }
        default:
            throw DICOMCodecError.unsupportedImage("SOF\(frame.process) cannot start a hierarchical JPEG stream")
        }
    }

    /// Adds one differential frame to the expanded reference (T.81 J.2).
    private func decodeDifferential(_ level: JPEGStream.HierarchicalFrame, reference: [Plane]) throws -> [Plane] {
        let frame = level.frame
        var planes = try reference.indices.map { index -> Plane in
            let (width, height) = Self.componentSize(frame, index)
            return try Self.expand(
                reference[index], horizontally: level.expandHorizontally, vertically: level.expandVertically,
                to: width, height)
        }

        switch frame.process {
        case 5, 6, 13, 14:
            var decoder = try decodeCoefficients(level)
            decoder.differential = true
            let quantization = level.scans.last!.quantizationTables
            for (index, component) in frame.components.enumerated() {
                guard let zigzag = quantization[component.quantizationTable] else {
                    throw DICOMCodecError.corruptedData(
                        "JPEG quantization table \(component.quantizationTable) is missing")
                }
                var natural = [Int32](repeating: 0, count: 64)
                for k in 0..<64 { natural[JPEGIDCT.naturalOrder[k]] = Int32(zigzag[k]) }
                let perLine = decoder.blocksPerLine[index]
                let rows = decoder.coefficients[index].count / 64 / perLine
                let stride = perLine * 8
                var differences = [Int32](repeating: 0, count: stride * rows * 8)
                let block = UnsafeMutablePointer<Int32>.allocate(capacity: 64)
                let workspace = UnsafeMutablePointer<Int>.allocate(capacity: 64)
                defer { block.deallocate(); workspace.deallocate() }
                decoder.coefficients[index].withUnsafeBufferPointer { source in
                    differences.withUnsafeMutableBufferPointer { output in
                        for blockRow in 0..<rows {
                            for blockColumn in 0..<perLine {
                                let base = (blockRow * perLine + blockColumn) * 64
                                for i in 0..<64 { block[i] = source[base + i] &* natural[i] }
                                JPEGIDCT.inverseDifferential(
                                    block, precision: frame.precision,
                                    output: output.baseAddress! + blockRow * 8 * stride + blockColumn * 8,
                                    stride: stride, workspace: workspace)
                            }
                        }
                    }
                }
                let width = planes[index].width
                for y in 0..<planes[index].height {
                    for x in 0..<width {
                        planes[index].samples[y * width + x] += Int(differences[y * stride + x])
                    }
                }
            }
        case 7, 15:
            // Differences are modulo 2^16 (H.1.2.1). Below 16 bits, reading
            // them as signed gives the same samples for valid streams and
            // saturates, rather than wraps, on inconsistent ones.
            let (raw, shifts) = try decodeLossless(level, differential: true)
            let modular = frame.precision == 16
            for index in planes.indices {
                for pixel in planes[index].samples.indices {
                    let difference = (raw[index][pixel] << shifts[index]) & 0xFFFF
                    let reference = planes[index].samples[pixel]
                    planes[index].samples[pixel] = modular
                        ? (reference + difference) & 0xFFFF
                        : reference + (difference >= 0x8000 ? difference - 0x10000 : difference)
                }
            }
        default:
            throw DICOMCodecError.corruptedData("SOF\(frame.process) is not a differential frame")
        }
        return planes
    }

    /// Entropy decodes every scan of a DCT frame.
    private func decodeCoefficients(_ level: JPEGStream.HierarchicalFrame) throws -> JPEGDCTDecoder {
        let process = level.frame.process
        var decoder = try JPEGDCTDecoder(frame: level.frame)
        decoder.differential = level.isDifferential
        for scan in level.scans {
            if process >= 9 {
                try decoder.decodeArithmetic(scan, progressive: process == 10 || process == 14)
            } else {
                try decoder.decode(scan, progressive: process == 2 || process == 6)
            }
        }
        return decoder
    }

    /// Decodes a lossless frame's scans, returning the raw (point
    /// transformed) values and the point transform of each component.
    private func decodeLossless(
        _ level: JPEGStream.HierarchicalFrame, differential: Bool
    ) throws -> (planes: [[Int]], shifts: [Int]) {
        let frame = level.frame
        guard frame.components.allSatisfy({ $0.horizontalSampling == 1 && $0.verticalSampling == 1 }) else {
            throw DICOMCodecError.unsupportedImage("subsampled JPEG Lossless components")
        }
        let width = frame.samplesPerLine, height = frame.lines
        guard width * height <= 1 << 28 else { throw DICOMCodecError.corruptedData("JPEG dimensions are invalid") }
        let codec = DICOMJPEGLosslessCodec()
        var planes = [[Int]](repeating: [Int](repeating: 0, count: width * height), count: frame.components.count)
        var shifts = [Int](repeating: 0, count: frame.components.count)
        var decoded = Set<Int>()
        for scan in level.scans {
            if frame.process >= 11 {
                try codec.decodeArithmeticScan(
                    scan, precision: frame.precision, width: width, height: height, planes: &planes,
                    differential: differential)
            } else {
                try codec.decodeScan(
                    scan, precision: frame.precision, width: width, height: height, planes: &planes,
                    differential: differential)
            }
            for component in scan.components {
                decoded.insert(component.componentIndex)
                shifts[component.componentIndex] = scan.approximationLow
            }
        }
        guard decoded.count == frame.components.count else {
            throw DICOMCodecError.corruptedData("JPEG scans do not cover every component")
        }
        return (planes, shifts)
    }

    /// Upsamples a reference by two with the T.81 J.1.1.2 bilinear filter,
    /// horizontally then vertically, replicating the last column and row.
    private static func expand(
        _ plane: Plane, horizontally: Bool, vertically: Bool, to width: Int, _ height: Int
    ) throws -> Plane {
        let expectedWidth = horizontally ? (width + 1) / 2 : width
        let expectedHeight = vertically ? (height + 1) / 2 : height
        guard plane.width == expectedWidth, plane.height == expectedHeight else {
            throw DICOMCodecError.corruptedData(
                "JPEG reference is \(plane.width)x\(plane.height), differential frame expects "
                    + "\(expectedWidth)x\(expectedHeight)")
        }
        var current = plane
        if horizontally {
            var samples = [Int](repeating: 0, count: width * current.height)
            let w = current.width
            for y in 0..<current.height {
                let row = y * w
                for x in 0..<width {
                    let i = x >> 1
                    samples[y * width + x] = x & 1 == 0
                        ? current.samples[row + i]
                        : (current.samples[row + i] + current.samples[row + min(i + 1, w - 1)]) >> 1
                }
            }
            current = Plane(width: width, height: current.height, samples: samples)
        }
        if vertically {
            var samples = [Int](repeating: 0, count: current.width * height)
            let w = current.width, h = current.height
            for y in 0..<height {
                let i = y >> 1
                for x in 0..<w {
                    samples[y * w + x] = y & 1 == 0
                        ? current.samples[i * w + x]
                        : (current.samples[i * w + x] + current.samples[min(i + 1, h - 1) * w + x]) >> 1
                }
            }
            current = Plane(width: w, height: height, samples: samples)
        }
        return current
    }
}
