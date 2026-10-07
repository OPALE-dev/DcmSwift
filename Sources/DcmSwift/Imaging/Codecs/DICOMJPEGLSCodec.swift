import Foundation

/// JPEG-LS Lossless (1.2.840.10008.1.2.4.80) and Near-Lossless
/// (1.2.840.10008.1.2.4.81) Image Compression, ITU-T T.87 (ISO/IEC 14495-1),
/// implemented in Swift.
///
/// Decoding supports every interleave mode, near-lossless coding, LSE preset
/// parameters, restart intervals, and the HP color transforms that some
/// writers signal in an APP8 "mrfx" segment. Encoding writes 2 to 16-bit
/// monochrome or three-component frames with default parameters.
public struct DICOMJPEGLSCodec: DICOMPixelDataDecoder {
    public static let lossless = "1.2.840.10008.1.2.4.80"
    public static let nearLossless = "1.2.840.10008.1.2.4.81"
    public var transferSyntaxUIDs: Set<String> { [Self.lossless, Self.nearLossless] }

    /// How the components of a color frame are interleaved (T.87 B.2.3).
    public enum Interleave: Int, Sendable {
        /// One scan per component.
        case none = 0
        /// One scan, alternating component lines.
        case line = 1
        /// One scan, alternating component samples.
        case sample = 2
    }

    public init() {}

    public func decode(_ encodedFrame: Data, description: DICOMPixelDescription) throws -> DICOMDecodedFrame {
        let stream = try JPEGLSStream([UInt8](encodedFrame))
        let frame = stream.frame
        guard frame.lines == description.rows, frame.samplesPerLine == description.columns,
              frame.components.count == description.samplesPerPixel else {
            throw DICOMCodecError.corruptedData(
                "JPEG-LS frame is \(frame.samplesPerLine)x\(frame.lines)x\(frame.components.count), image is "
                    + "\(description.columns)x\(description.rows)x\(description.samplesPerPixel)")
        }
        guard frame.components.indices.allSatisfy({ frame.size(of: $0) == (frame.samplesPerLine, frame.lines) }) else {
            throw DICOMCodecError.unsupportedImage("subsampled JPEG-LS components")
        }
        let cellBytes = description.bitsAllocated / 8
        guard cellBytes == 1 || cellBytes == 2, frame.precision <= description.bitsAllocated else {
            throw DICOMCodecError.unsupportedImage(
                "\(frame.precision)-bit JPEG-LS in \(description.bitsAllocated) bits allocated")
        }

        var planes = try JPEGLSScanDecoder(stream: stream).decode()
        var photometric = description.photometricInterpretation
        if stream.colorTransform != .none {
            try Self.inverseColorTransform(stream.colorTransform, planes: &planes, frame: frame,
                                           interleave: stream.scans[0].interleave, near: stream.scans[0].parameters.near)
            photometric = .rgb
        }

        let count = frame.lines * frame.samplesPerLine
        let samples = planes.count
        var output = [UInt8](repeating: 0, count: count * samples * cellBytes)
        output.withUnsafeMutableBufferPointer { out in
            for (component, plane) in planes.enumerated() {
                for pixel in 0..<count {
                    let value = plane[pixel]
                    let offset = (pixel * samples + component) * cellBytes
                    out[offset] = UInt8(value & 0xFF)
                    if cellBytes == 2 { out[offset + 1] = UInt8(value >> 8) }
                }
            }
        }
        return DICOMDecodedFrame(
            description: description.decodedFrame(photometricInterpretation: photometric, planarConfiguration: 0),
            data: Data(output))
    }

    /// The HP inverse color transforms, as CharLS applies them: only to
    /// three-component, 8 or 16-bit, lossless, interleaved frames, modulo the
    /// sample type's range.
    private static func inverseColorTransform(
        _ transform: JPEGLSStream.ColorTransform, planes: inout [[UInt16]], frame: JPEGLSStream.Frame,
        interleave: JPEGLSStream.InterleaveMode, near: Int
    ) throws {
        guard planes.count == 3, frame.precision == 8 || frame.precision == 16, near == 0, interleave != .none else {
            throw DICOMCodecError.unsupportedImage("JPEG-LS color transform \(transform) for this frame")
        }
        let range = frame.precision == 8 ? 256 : 65536
        let mask = range - 1, bias = range / 2
        for pixel in planes[0].indices {
            let v1 = Int(planes[0][pixel]), v2 = Int(planes[1][pixel]), v3 = Int(planes[2][pixel])
            let r: Int, g: Int, b: Int
            switch transform {
            case .hp1:
                (r, g, b) = (v1 + v2 - bias, v2, v3 + v2 - bias)
            case .hp2:
                let red = (v1 + v2 - bias) & mask
                (r, g, b) = (red, v2, v3 + ((red + v2) >> 1) - bias)
            case .hp3:
                let green = v1 - ((v3 + v2) >> 2) + range / 4
                (r, g, b) = (v3 + green - bias, green, v2 + green - bias)
            case .none:
                return
            }
            planes[0][pixel] = UInt16(r & mask)
            planes[1][pixel] = UInt16(g & mask)
            planes[2][pixel] = UInt16(b & mask)
        }
    }

    /// Encodes one native little endian frame (as described) to a JPEG-LS
    /// interchange stream with default coding parameters.
    ///
    /// - Parameters:
    ///   - near: The maximum absolute error, 0 for lossless coding
    ///     (1.2.840.10008.1.2.4.80); positive values require
    ///     1.2.840.10008.1.2.4.81.
    ///   - interleave: The component interleaving of color frames.
    ///   - restartInterval: Lines per restart interval, 0 for none.
    public func encode(
        _ frame: Data, description: DICOMPixelDescription,
        near: Int = 0, interleave: Interleave = .line, restartInterval: Int = 0
    ) throws -> Data {
        let precision = description.bitsStored
        guard description.sampleFormat == .integer, (2...16).contains(precision),
              description.bitsAllocated == 8 || description.bitsAllocated == 16,
              description.samplesPerPixel == 1 || description.samplesPerPixel == 3,
              description.photometricInterpretation != .ybrFull422 else {
            throw DICOMCodecError.unsupportedImage(
                "JPEG-LS needs 2 to 16-bit integer samples in 8 or 16 bits, with one or three samples per pixel")
        }
        let width = description.columns, height = description.rows, samples = description.samplesPerPixel
        guard width <= 0xFFFF, height <= 0xFFFF, (0...0xFFFF).contains(restartInterval) else {
            throw DICOMCodecError.unsupportedImage("JPEG-LS dimensions or restart interval exceed 65535")
        }
        let parameters = try JPEGLSStream.CodingParameters(
            precision: precision, near: near, preset: JPEGLSStream.PresetParameters())

        let stored = try DICOMNativePixelData(description: description.decodedFrame(), decodedFrames: frame)
            .storedValues(frame: 0)
        let mask = (1 << precision) - 1
        let planes = (0..<samples).map { component in
            stride(from: component, to: stored.count, by: samples).map { Int(stored[$0]) & mask }
        }

        var stream: [UInt8] = [0xFF, 0xD8]
        func segment(_ marker: UInt8, _ payload: [UInt8]) {
            stream += [0xFF, marker, UInt8((payload.count + 2) >> 8), UInt8((payload.count + 2) & 0xFF)] + payload
        }
        var frameHeader: [UInt8] = [UInt8(precision), UInt8(height >> 8), UInt8(height & 0xFF),
                                    UInt8(width >> 8), UInt8(width & 0xFF), UInt8(samples)]
        for component in 1...samples { frameHeader += [UInt8(component), 0x11, 0] }
        segment(0xF7, frameHeader)
        if restartInterval > 0 {
            segment(0xDD, [UInt8(restartInterval >> 8), UInt8(restartInterval & 0xFF)])
        }

        let encoder = JPEGLSScanEncoder(
            width: width, height: height, parameters: parameters, restartInterval: restartInterval)
        let mode = samples == 1 ? .none : JPEGLSStream.InterleaveMode(rawValue: interleave.rawValue)!
        let groups: [[Int]] = mode == .none ? (0..<samples).map { [$0] } : [Array(0..<samples)]
        for group in groups {
            var header: [UInt8] = [UInt8(group.count)]
            for component in group { header += [UInt8(component + 1), 0] }
            header += [UInt8(near), UInt8(mode.rawValue), 0]
            segment(0xDA, header)
            stream += encoder.encodeScan(group.map { planes[$0] }, interleave: mode)
        }
        stream += [0xFF, 0xD9]
        // Fragments have an even length; padding follows EOI (PS3.5 A.4).
        if stream.count % 2 == 1 { stream.append(0) }
        return Data(stream)
    }
}
