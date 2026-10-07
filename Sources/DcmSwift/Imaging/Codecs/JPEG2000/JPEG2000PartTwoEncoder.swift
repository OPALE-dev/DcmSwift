import Foundation

extension DICOMJPEG2000Codec {
    /// A multi-frame image encoded with JPEG 2000 Part 2 (PS3.5 A.4.4).
    public struct PartTwoEncoding: Sendable {
        /// One codestream per component collection, of even length; each
        /// goes in one or more Fragments of its own.
        public let codestreams: [Data]
        /// 1.2.840.10008.1.2.4.92 when lossless, .93 otherwise.
        public let transferSyntaxUID: String
    }

    /// Encodes the frames of a grayscale image (native little endian frames,
    /// one after the other, as described) to JPEG 2000 Part 2 codestreams.
    ///
    /// Consecutive frames form component collections of `framesPerCollection`
    /// frames (all frames by default). Each collection is decorrelated across
    /// frames by a one-dimensional wavelet transform (ISO/IEC 15444-2 J.3.2)
    /// of `decompositionLevels` levels (by default as many as the collection
    /// allows, up to 4): the reversible 5-3 for `.lossless`, the irreversible
    /// 9-7 otherwise, after removing the DC offset of unsigned samples. The
    /// transformed components are then encoded as JPEG 2000 Part 1 tile-
    /// components by OpenJPEG. The compression ratio and PSNR targets refer to
    /// the codestream components; the PSNR one is therefore approximate.
    public func encodePartTwo(
        _ frames: Data, description: DICOMPixelDescription, quality: Quality = .lossless,
        decompositionLevels: Int? = nil, framesPerCollection: Int? = nil
    ) throws -> PartTwoEncoding {
        let precision = description.bitsStored
        let count = description.numberOfFrames
        guard description.sampleFormat == .integer, description.samplesPerPixel == 1, (1...16).contains(precision),
              description.bitsAllocated == 8 || description.bitsAllocated == 16, count >= 1 else {
            throw DICOMCodecError.unsupportedImage(
                "JPEG 2000 Part 2 encoding needs 1 to 16-bit grayscale integer frames in 8 or 16 bits")
        }
        let size = framesPerCollection ?? count
        guard size >= 1, size <= 16_384 else {
            throw DICOMCodecError.unsupportedImage("\(size) frames per component collection")
        }
        if let decompositionLevels, !(0...32).contains(decompositionLevels) {
            throw DICOMCodecError.unsupportedImage("\(decompositionLevels) decomposition levels")
        }
        let native = DICOMPixelDescription(
            rows: description.rows, columns: description.columns, samplesPerPixel: 1,
            photometricInterpretation: description.photometricInterpretation,
            bitsAllocated: description.bitsAllocated, bitsStored: precision, highBit: description.highBit,
            isSigned: description.isSigned, planarConfiguration: 0, numberOfFrames: count)
        let pixels = try DICOMNativePixelData(description: native, decodedFrames: frames)
        let reversible = quality == .lossless
        let width = description.columns, height = description.rows
        let mask = (Int64(1) << precision) - 1, signBit = Int64(1) << (precision - 1)
        let offset = description.isSigned ? 0 : 1 << (precision - 1)

        var codestreams: [Data] = []
        for start in stride(from: 0, to: count, by: size) {
            let frameRange = start..<min(start + size, count)
            let k = frameRange.count
            var natural = 0
            while natural < 4, 2 << natural <= k { natural += 1 }
            let levels = decompositionLevels ?? natural
            // Room for the growth of the 5-3 and 9-7 bands across frames.
            let codestreamPrecision = precision + 2 + (min(levels, 32) + 1) / 2
            guard codestreamPrecision <= 30 else {
                throw DICOMCodecError.unsupportedImage("\(levels) decomposition levels for \(precision)-bit frames")
            }

            // Native samples, then the forward transform location by location.
            let stored = try frameRange.map { try pixels.storedValues(frame: $0) }
            let planeSize = width * height
            var planes = [Int32](repeating: 0, count: k * planeSize)
            planes.withUnsafeMutableBufferPointer { output in
                let base = output.baseAddress!
                DispatchQueue.concurrentPerform(iterations: height) { y in
                    var wavelet = WaveletBuffers()
                    var input = [Double](repeating: 0, count: k)
                    var result: [Double] = []
                    for pixel in (y * width)..<((y + 1) * width) {
                        for frame in 0..<k {
                            var value = stored[frame][pixel] & mask
                            if description.isSigned, value & signBit != 0 { value -= mask + 1 }
                            input[frame] = Double(value - Int64(offset))
                        }
                        result.removeAll(keepingCapacity: true)
                        wavelet.forward(input, levels: levels, reversible: reversible, origin: 0, into: &result)
                        for component in 0..<k {
                            base[component * planeSize + pixel] = Int32(result[component].rounded())
                        }
                    }
                }
            }

            // Targets relative to the image samples rather than the wider
            // codestream components.
            let target: Quality
            switch quality {
            case .lossless:
                target = .lossless
            case .compressionRatio(let ratio):
                target = .compressionRatio(ratio * Double(codestreamPrecision) / Double(precision))
            case .peakSignalToNoiseRatio(let psnr):
                let gain = (pow(2, Double(codestreamPrecision)) - 1) / (pow(2, Double(precision)) - 1)
                target = .peakSignalToNoiseRatio(psnr + 20 * log10(gain))
            }
            let partOne = try Self.openJPEGEncode(
                planes, width: width, height: height,
                components: Array(repeating: (codestreamPrecision, true), count: k),
                quality: target, multipleComponentTransform: false)
            var bytes = try Self.addMultipleComponentTransform(
                to: partOne, components: k, precision: precision, isSigned: description.isSigned,
                levels: levels, reversible: reversible, offset: offset)
            // Fragments have an even length (PS3.5 A.4).
            if bytes.count % 2 == 1 { bytes.append(0) }
            codestreams.append(Data(bytes))
        }
        return PartTwoEncoding(
            codestreams: codestreams, transferSyntaxUID: reversible ? Self.partTwoLossless : Self.partTwo)
    }

    /// Turns a Part 1 codestream of transformed components into a Part 2
    /// one: Rsiz signals the multiple component transformation, COD the
    /// wavelet-based transform, and the main header gains the CBD, MCT
    /// (offsets), MCC (one wavelet collection), and MCO segments (A.2.1,
    /// A.3.6 to A.3.9).
    static func addMultipleComponentTransform(
        to bytes: [UInt8], components k: Int, precision: Int, isSigned: Bool,
        levels: Int, reversible: Bool, offset: Int
    ) throws -> [UInt8] {
        func u16(_ value: Int) -> [UInt8] { [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
        func u32(_ value: Int) -> [UInt8] { u16(value >> 16 & 0xFFFF) + u16(value & 0xFFFF) }
        func segment(_ marker: UInt8, _ payload: [UInt8]) -> [UInt8] {
            [0xFF, marker] + u16(payload.count + 2) + payload
        }
        /// A series of segments (J.2) whose data is split at `chunk` bytes.
        func series(
            _ marker: UInt8, data: [UInt8], chunk: Int, header: (_ z: Int, _ last: Int) -> [UInt8]
        ) -> [UInt8] {
            let parts = max(1, (data.count + chunk - 1) / chunk)
            return (0..<parts).flatMap { z in
                segment(marker, header(z, parts - 1)
                    + data[(z * chunk)..<min((z + 1) * chunk, data.count)])
            }
        }

        let wide = k > 256
        let indices = (0..<k).flatMap { wide ? u16($0) : [UInt8($0)] }
        let count = u16(k | (wide ? 0x8000 : 0))
        let offsetIndex = offset == 0 ? 0 : 1
        // Wavelet collection: Xmcc, Nmcc, Cmcc, Mmcc, Wmcc, Tmcc (levels,
        // offset array, kernel), Omcc.
        var record: [UInt8] = [0x03]
        record += count + indices + count + indices
        record += [UInt8(levels), UInt8(offsetIndex), reversible ? 1 : 0]
        record += u32(0)
        var segments = segment(0x78, u16(0x8000 | k) + [(isSigned ? 0x80 : 0) | UInt8(precision - 1)])
        if offset != 0 {
            // Array 1: offsets, 32-bit integers (Table A.33).
            let imct = 1 << 10 | 2 << 8 | 1
            segments += series(0x74, data: (0..<k).flatMap { _ in u32(offset) }, chunk: 65_000) { z, last in
                u16(z) + u16(imct) + (z == 0 ? u16(last) : [])
            }
        }
        segments += series(0x75, data: record, chunk: 65_000) { z, last in
            u16(z) + [0] + (z == 0 ? u16(last) + u16(1) : [])
        }
        segments += segment(0x77, [1, 0])

        guard bytes.count > 6, bytes.starts(with: [0xFF, 0x4F, 0xFF, 0x51]) else {
            throw DICOMCodecError.unsupportedImage("OpenJPEG wrote no codestream")
        }
        var output = bytes
        output[6] = 0x81
        output[7] = 0x00
        let headerStart = 4 + (Int(bytes[4]) << 8 | Int(bytes[5]))
        var position = headerStart
        var cod: Int?
        while position + 4 <= bytes.count, bytes[position] == 0xFF, bytes[position + 1] != 0x90 {
            if bytes[position + 1] == 0x52 { cod = position }
            position += 2 + (Int(bytes[position + 2]) << 8 | Int(bytes[position + 3]))
        }
        guard let cod else { throw DICOMCodecError.unsupportedImage("OpenJPEG wrote no COD segment") }
        // Wavelet-based multiple component transformation (Table A.8).
        output[cod + 8] = 0x04
        output.insert(contentsOf: segments, at: headerStart)
        return output
    }
}
