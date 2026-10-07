import Foundation

/// JPEG Lossless, Non-Hierarchical (Process 14): 1.2.840.10008.1.2.4.57 and
/// its first-order prediction subset 1.2.840.10008.1.2.4.70 (PS3.5 A.4.1),
/// decoded per ITU-T T.81 Annex H with Huffman coding.
public struct DICOMJPEGLosslessCodec: DICOMPixelDataDecoder {
    public static let processFourteen = "1.2.840.10008.1.2.4.57"
    public static let firstOrderPrediction = "1.2.840.10008.1.2.4.70"
    public var transferSyntaxUIDs: Set<String> { [Self.processFourteen, Self.firstOrderPrediction] }

    public init() {}

    public func decode(_ encodedFrame: Data, description: DICOMPixelDescription) throws -> DICOMDecodedFrame {
        let stream = try JPEGStream([UInt8](encodedFrame))
        let frame = stream.frame
        guard frame.process == 3 else {
            throw DICOMCodecError.unsupportedImage("SOF\(frame.process) is not JPEG Lossless with Huffman coding")
        }
        guard (2...16).contains(frame.precision) else {
            throw DICOMCodecError.corruptedData("JPEG Lossless precision \(frame.precision)")
        }
        guard frame.lines == description.rows, frame.samplesPerLine == description.columns,
              frame.components.count == description.samplesPerPixel else {
            throw DICOMCodecError.corruptedData(
                "JPEG frame is \(frame.samplesPerLine)x\(frame.lines)x\(frame.components.count), image is "
                    + "\(description.columns)x\(description.rows)x\(description.samplesPerPixel)")
        }
        guard frame.components.allSatisfy({ $0.horizontalSampling == 1 && $0.verticalSampling == 1 }) else {
            throw DICOMCodecError.unsupportedImage("subsampled JPEG Lossless components")
        }
        let cellBytes = description.bitsAllocated / 8
        guard cellBytes == 1 || cellBytes == 2, frame.precision <= description.bitsAllocated else {
            throw DICOMCodecError.unsupportedImage(
                "\(frame.precision)-bit JPEG Lossless in \(description.bitsAllocated) bits allocated")
        }

        let width = frame.samplesPerLine
        let height = frame.lines
        var planes = [[Int]](repeating: [Int](repeating: 0, count: width * height), count: frame.components.count)
        var shifts = [Int](repeating: 0, count: frame.components.count)
        var decoded = Set<Int>()

        for scan in stream.scans {
            try decodeScan(scan, precision: frame.precision, width: width, height: height, planes: &planes)
            for component in scan.components {
                decoded.insert(component.componentIndex)
                shifts[component.componentIndex] = scan.approximationLow
            }
        }
        guard decoded.count == frame.components.count else {
            throw DICOMCodecError.corruptedData("JPEG scans do not cover every component")
        }

        // Interleave samples into little endian cells, undoing the point
        // transform.
        let samples = frame.components.count
        var output = [UInt8](repeating: 0, count: width * height * samples * cellBytes)
        for pixel in 0..<(width * height) {
            for component in 0..<samples {
                let value = planes[component][pixel] << shifts[component]
                let offset = (pixel * samples + component) * cellBytes
                output[offset] = UInt8(value & 0xFF)
                if cellBytes == 2 { output[offset + 1] = UInt8((value >> 8) & 0xFF) }
            }
        }
        return DICOMDecodedFrame(
            description: description.decodedFrame(planarConfiguration: 0), data: Data(output))
    }

    // MARK: Encoding

    /// Encodes one native little endian frame (as described) to a JPEG
    /// Lossless interchange stream with one interleaved scan and an
    /// optimized Huffman table (T.81 Annex K.2).
    ///
    /// - Parameters:
    ///   - predictor: Selection Value 1...7; 1 is required for
    ///     1.2.840.10008.1.2.4.70.
    ///   - pointTransform: Low bits discarded before coding; 0 keeps the
    ///     encoding lossless.
    ///   - restartLines: Lines per restart interval, 0 for none.
    public func encode(
        _ frame: Data, description: DICOMPixelDescription,
        predictor: Int = 1, pointTransform: Int = 0, restartLines: Int = 0
    ) throws -> Data {
        let precision = description.bitsStored
        guard description.sampleFormat == .integer, (2...16).contains(precision),
              description.bitsAllocated == 8 || description.bitsAllocated == 16,
              (1...4).contains(description.samplesPerPixel),
              description.photometricInterpretation != .ybrFull422 else {
            throw DICOMCodecError.unsupportedImage("JPEG Lossless needs 2 to 16 bit integer samples in 8 or 16 bits")
        }
        guard (1...7).contains(predictor), (0..<precision).contains(pointTransform) else {
            throw DICOMCodecError.unsupportedImage("predictor \(predictor) or point transform \(pointTransform)")
        }
        let width = description.columns
        let height = description.rows
        let samples = description.samplesPerPixel
        let restartInterval = restartLines * width
        guard restartLines >= 0, restartInterval <= 0xFFFF, width <= 0xFFFF, height <= 0xFFFF else {
            throw DICOMCodecError.unsupportedImage("JPEG dimensions or restart interval exceed 65535")
        }

        // Stored values as P-bit patterns (2's complement for signed data),
        // reduced by the point transform, one plane per component.
        let stored = try DICOMNativePixelData(description: description.decodedFrame(), decodedFrames: frame)
            .storedValues(frame: 0)
        let mask = (1 << precision) - 1
        var planes = [[Int]](repeating: [], count: samples)
        for component in 0..<samples {
            planes[component] = stride(from: component, to: stored.count, by: samples).map {
                (Int(stored[$0]) & mask) >> pointTransform
            }
        }

        // Differences in coding order (H.1.2), modulo 2^16.
        let initial = 1 << (precision - pointTransform - 1)
        var differences = [Int]()
        differences.reserveCapacity(stored.count)
        var frequencies = [Int](repeating: 0, count: 256)
        var firstLine = 0
        for y in 0..<height {
            if restartInterval > 0 && y > 0 && y % restartLines == 0 { firstLine = y }
            for x in 0..<width {
                let index = y * width + x
                for component in 0..<samples {
                    let plane = planes[component]
                    let prediction: Int
                    if y == firstLine {
                        prediction = x == 0 ? initial : plane[index - 1]
                    } else if x == 0 {
                        prediction = plane[index - width]
                    } else {
                        let a = plane[index - 1], b = plane[index - width], c = plane[index - width - 1]
                        switch predictor {
                        case 1: prediction = a
                        case 2: prediction = b
                        case 3: prediction = c
                        case 4: prediction = a + b - c
                        case 5: prediction = a + ((b - c) >> 1)
                        case 6: prediction = b + ((a - c) >> 1)
                        default: prediction = (a + b) >> 1
                        }
                    }
                    var difference = (plane[index] - prediction) & 0xFFFF
                    if difference > 32768 { difference -= 65536 }
                    differences.append(difference)
                    frequencies[Self.category(of: difference)] += 1
                }
            }
        }

        let table = JPEGHuffmanEncoder(frequencies: frequencies)
        var writer = JPEGBitWriter()
        let mcusPerInterval = restartInterval
        var restartIndex = 0
        for (index, difference) in differences.enumerated() {
            let mcu = index / samples
            if mcusPerInterval > 0 && mcu > 0 && index % samples == 0 && mcu % mcusPerInterval == 0 {
                writer.restartMarker(restartIndex)
                restartIndex += 1
            }
            let category = Self.category(of: difference)
            table.write(category, to: &writer)
            // Category 16 (difference 32768) has no additional bits.
            if category > 0 && category < 16 {
                writer.write(difference < 0 ? difference - 1 : difference, bits: category)
            }
        }
        writer.flush()

        var stream: [UInt8] = [0xFF, 0xD8]
        func segment(_ marker: UInt8, _ payload: [UInt8]) {
            stream += [0xFF, marker, UInt8((payload.count + 2) >> 8), UInt8((payload.count + 2) & 0xFF)] + payload
        }
        var frameHeader: [UInt8] = [UInt8(precision), UInt8(height >> 8), UInt8(height & 0xFF),
                                    UInt8(width >> 8), UInt8(width & 0xFF), UInt8(samples)]
        var scanHeader: [UInt8] = [UInt8(samples)]
        for component in 1...samples {
            frameHeader += [UInt8(component), 0x11, 0]
            scanHeader += [UInt8(component), 0x00]
        }
        scanHeader += [UInt8(predictor), 0, UInt8(pointTransform)]
        segment(0xC3, frameHeader)
        segment(0xC4, table.specification(tableClass: 0, identifier: 0))
        if restartInterval > 0 {
            segment(0xDD, [UInt8(restartInterval >> 8), UInt8(restartInterval & 0xFF)])
        }
        segment(0xDA, scanHeader)
        stream += writer.bytes
        stream += [0xFF, 0xD9]
        // Fragments have an even length; padding follows EOI (PS3.5 A.4).
        if stream.count % 2 == 1 { stream.append(0) }
        return Data(stream)
    }

    /// SSSS: the number of bits of a difference's magnitude (H.1.2.2).
    private static func category(of difference: Int) -> Int {
        if difference == 32768 { return 16 }
        var magnitude = abs(difference)
        var bits = 0
        while magnitude > 0 {
            bits += 1
            magnitude >>= 1
        }
        return bits
    }

    /// Decodes one scan (T.81 H.1.2): prediction from the reconstructed
    /// neighbours Ra (left), Rb (above), and Rc (above left), modulo 2^16.
    private func decodeScan(
        _ scan: JPEGStream.Scan, precision: Int, width: Int, height: Int, planes: inout [[Int]]
    ) throws {
        let predictor = scan.spectralStart
        let pointTransform = scan.approximationLow
        guard (1...7).contains(predictor) else {
            throw DICOMCodecError.unsupportedImage("JPEG Lossless predictor \(predictor)")
        }
        guard pointTransform < precision else {
            throw DICOMCodecError.corruptedData("JPEG point transform \(pointTransform)")
        }
        let tables = try scan.components.map { component -> JPEGHuffmanTable in
            guard let table = scan.dcTables[component.dcTable] else {
                throw DICOMCodecError.corruptedData("JPEG Huffman table \(component.dcTable) is missing")
            }
            return table
        }
        let initial = 1 << (precision - pointTransform - 1)
        var reader = JPEGBitReader(scan.entropyCodedData)
        let restartInterval = scan.restartInterval
        var untilRestart = restartInterval
        var restartIndex = 0
        // The first line of the image and of each restart interval predicts
        // from the left only (H.1.2.1).
        var firstLine = 0

        for y in 0..<height {
            for x in 0..<width {
                if restartInterval > 0 && untilRestart == 0 {
                    guard x == 0 else {
                        throw DICOMCodecError.unsupportedImage("JPEG Lossless restart interval inside a line")
                    }
                    try reader.restart(expecting: restartIndex)
                    restartIndex += 1
                    untilRestart = restartInterval
                    firstLine = y
                }
                let index = y * width + x
                for (scanIndex, component) in scan.components.enumerated() {
                    let prediction: Int
                    let plane = component.componentIndex
                    if y == firstLine {
                        prediction = x == 0 ? initial : planes[plane][index - 1]
                    } else if x == 0 {
                        prediction = planes[plane][index - width]
                    } else {
                        let a = planes[plane][index - 1]
                        let b = planes[plane][index - width]
                        let c = planes[plane][index - width - 1]
                        switch predictor {
                        case 1: prediction = a
                        case 2: prediction = b
                        case 3: prediction = c
                        case 4: prediction = a + b - c
                        case 5: prediction = a + ((b - c) >> 1)
                        case 6: prediction = b + ((a - c) >> 1)
                        default: prediction = (a + b) >> 1
                        }
                    }
                    let category = try tables[scanIndex].decode(&reader)
                    guard category <= 16 else {
                        throw DICOMCodecError.corruptedData("JPEG Lossless difference category \(category)")
                    }
                    // Category 16 is the difference 32768 without extra bits.
                    let difference = category == 16 ? 32768 : reader.receiveExtend(category)
                    planes[plane][index] = (prediction + difference) & 0xFFFF
                }
                if restartInterval > 0 { untilRestart -= 1 }
            }
        }
    }
}
