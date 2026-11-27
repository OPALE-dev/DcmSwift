import Foundation

/// Native (uncompressed) Pixel Data, Float Pixel Data, or Double Float Pixel
/// Data decoded frame by frame (PS3.5 8.1.1 and Annex D).
///
/// Frames are read with ranged access, so file-backed Bulk Data stays on
/// disk. Samples are returned pixel by pixel whatever the Planar
/// Configuration, and YBR_FULL_422 chrominance is expanded to three samples
/// per pixel.
public struct DICOMNativePixelData {
    public let description: DICOMPixelDescription
    private let storage: Storage
    private let byteLayout: ByteLayout

    private enum Storage {
        /// A Data Element, read by range so Bulk Data may stay on disk.
        case element(DataElement)
        /// Frames produced by a codec, in little endian native layout.
        case bytes(Data)

        var count: Int {
            switch self {
            case .element(let element): return element.bulkDataReference?.length ?? element.length
            case .bytes(let data): return data.count
            }
        }

        func load(_ range: Range<Int>) throws -> Data {
            switch self {
            case .element(let element):
                return try element.loadData(range: range)
            case .bytes(let data):
                guard range.lowerBound >= 0, range.upperBound <= data.count else {
                    throw DICOMPixelDataError.truncatedPixelData(expectedBytes: range.upperBound, actualBytes: data.count)
                }
                return data.subdata(in: (data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound))
            }
        }
    }

    /// How samples are laid out in the Value Field.
    private enum ByteLayout {
        case littleEndian
        /// Big Endian OW holding 8-bit or 1-bit cells: bytes are swapped
        /// within each 16-bit word.
        case bigEndianWords
        /// Big Endian with multi-byte cells: each cell is big endian.
        case bigEndianCells
    }

    /// Reads the native Pixel Data of a Data Set with the default
    /// ``DICOMImageLimits``.
    ///
    /// - Parameter dataset: The Data Set holding the Image Pixel Module and
    ///   native Pixel Data.
    public init(dataset: DataSet) throws {
        try self.init(dataset: dataset, limits: DICOMImageLimits())
    }

    /// Reads the native Pixel Data of a Data Set.
    ///
    /// - Parameters:
    ///   - dataset: The Data Set holding the Image Pixel Module and native
    ///     Pixel Data.
    ///   - limits: The dimensions, buffer size, and frame count accepted
    ///     before any pixel is decoded.
    public init(dataset: DataSet, limits: DICOMImageLimits) throws {
        try self.init(dataset: dataset, description: DICOMPixelDescription(dataset: dataset, limits: limits))
    }

    public init(dataset: DataSet, description: DICOMPixelDescription) throws {
        let scope = DICOMAttributeScope(dataset: dataset)
        let keyword: String
        switch description.sampleFormat {
        case .integer: keyword = "PixelData"
        case .float32: keyword = "FloatPixelData"
        case .float64: keyword = "DoubleFloatPixelData"
        }
        guard let element = scope.element(keyword) else { throw DICOMPixelDataError.missingPixelData }
        if element is DataSequence {
            throw DICOMPixelDataError.encapsulatedPixelData(
                transferSyntax: dataset.transferSyntax?.tsUID ?? "unknown")
        }

        let bigEndian = element.byteOrder == .BigEndian
        let byteLayout: ByteLayout
        if !bigEndian || (description.bitsAllocated == 8 && element.vr == .OB) {
            byteLayout = .littleEndian
        } else if description.bitsAllocated <= 8 {
            byteLayout = .bigEndianWords
        } else {
            byteLayout = .bigEndianCells
        }

        try self.init(description: description, storage: .element(element), byteLayout: byteLayout)
    }

    /// Decoded frames in little endian native layout, as produced by a codec.
    public init(description: DICOMPixelDescription, decodedFrames data: Data) throws {
        try self.init(description: description, storage: .bytes(data), byteLayout: .littleEndian)
    }

    private init(description: DICOMPixelDescription, storage: Storage, byteLayout: ByteLayout) throws {
        let requiredBits = DICOMImageLimits.product(
            DICOMImageLimits.product(description.encodedSamplesPerFrame, description.bitsAllocated),
            description.numberOfFrames)
        guard requiredBits < .max else {
            throw DICOMPixelDataError.invalidAttribute("NumberOfFrames", "the declared Pixel Data size overflows")
        }
        let requiredBytes = (requiredBits + 7) / 8
        guard storage.count >= requiredBytes else {
            throw DICOMPixelDataError.truncatedPixelData(expectedBytes: requiredBytes, actualBytes: storage.count)
        }
        self.description = description
        self.storage = storage
        self.byteLayout = byteLayout
    }

    // MARK: Frames

    /// The encoded bytes of one frame, normalized to little endian cells. With
    /// one bit allocated the first pixel may start inside the first byte; see
    /// `frameBitOffset(_:)`.
    public func frameData(_ frame: Int) throws -> Data {
        let (range, _) = try byteRange(of: frame)
        return Data(try normalizedBytes(in: range))
    }

    private func byteRange(of frame: Int) throws -> (Range<Int>, bitOffset: Int) {
        guard (0..<description.numberOfFrames).contains(frame) else {
            throw DICOMPixelDataError.frameOutOfRange(frame, numberOfFrames: description.numberOfFrames)
        }
        let firstBit = frame * description.bitsPerFrame
        let lower = firstBit / 8
        let upper = (firstBit + description.bitsPerFrame + 7) / 8
        return (lower..<upper, firstBit % 8)
    }

    // MARK: Locating a pixel

    /// Where the samples of one pixel lie in the Value Field of the Pixel
    /// Data, as encoded: one range of bytes a sample, in the order of
    /// `storedValues(frame:)`. The range of a 1-bit cell is the byte that
    /// holds it; in a Big Endian OW of 8-bit or 1-bit cells, the byte as
    /// stored, each 16-bit word being swapped. The two pixels of a
    /// YBR_FULL_422 pair share their CB and CR (PS3.3 C.7.6.3.1.2). For
    /// frames decoded by a codec, the ranges are in the decoded frames.
    ///
    /// - Parameters:
    ///   - pixel: The pixel, row by row from the top left: `row × Columns + column`.
    ///   - frame: The frame, from 0.
    public func valueFieldRanges(ofPixel pixel: Int, frame: Int) throws -> [Range<Int>] {
        guard (0..<description.pixelsPerFrame).contains(pixel) else {
            throw DICOMPixelDataError.invalidAttribute("pixel", "\(pixel) is outside the \(description.pixelsPerFrame) pixels of a frame")
        }
        _ = try byteRange(of: frame)
        let firstBit = frame * description.bitsPerFrame
        let width = max(1, description.bitsAllocated / 8)
        return encodedCells(ofPixel: pixel).map { cell in
            var lower = (firstBit + cell * description.bitsAllocated) / 8
            if byteLayout == .bigEndianWords { lower ^= 1 }
            return lower..<(lower + width)
        }
    }

    /// The cells of a pixel among the encoded samples of a frame.
    private func encodedCells(ofPixel pixel: Int) -> [Int] {
        let pixels = description.pixelsPerFrame
        let samplesPerPixel = description.samplesPerPixel
        if description.photometricInterpretation == .ybrFull422 {
            let pair = (pixel / 2) * 4
            return [pair + pixel % 2, pair + 2, pair + 3]
        }
        if samplesPerPixel > 1, description.planarConfiguration == 1 {
            return (0..<samplesPerPixel).map { $0 * pixels + pixel }
        }
        return (0..<samplesPerPixel).map { pixel * samplesPerPixel + $0 }
    }

    /// Reads a byte range, undoing the Big Endian word swap when needed.
    private func normalizedBytes(in range: Range<Int>) throws -> [UInt8] {
        guard byteLayout == .bigEndianWords else {
            return [UInt8](try storage.load(range))
        }
        let lower = range.lowerBound & ~1
        let upper = min((range.upperBound + 1) & ~1, storage.count)
        var words = [UInt8](try storage.load(lower..<upper))
        var index = 0
        while index + 1 < words.count {
            words.swapAt(index, index + 1)
            index += 2
        }
        let start = range.lowerBound - lower
        return Array(words[start..<(start + range.count)])
    }

    // MARK: Stored values

    /// Stored integer sample values of one frame, `samplesPerPixel` values per
    /// pixel in row-major pixel order. Unused high and low bits are masked
    /// and signed values are sign-extended from the High Bit.
    public func storedValues(frame: Int) throws -> [Int64] {
        guard description.sampleFormat == .integer else {
            throw DICOMPixelDataError.invalidAttribute("PixelData", "floating point samples have no stored integer values")
        }
        let (range, bitOffset) = try byteRange(of: frame)
        try checkSampleBuffer(of: Int64.self)
        let bytes = try normalizedBytes(in: range)
        let encoded = description.encodedSamplesPerFrame
        var samples = [Int64](repeating: 0, count: encoded)

        let shift = description.highBit - description.bitsStored + 1
        let mask: UInt64 = description.bitsStored == 64 ? .max : (UInt64(1) << description.bitsStored) - 1
        let signBit = UInt64(1) << (description.bitsStored - 1)

        func value(of cell: UInt64) -> Int64 {
            let raw = (cell >> UInt64(shift)) & mask
            if description.isSigned && raw & signBit != 0 {
                return Int64(bitPattern: raw | ~mask)
            }
            return Int64(raw)
        }

        if description.bitsAllocated == 1 {
            // Bits are packed from the least significant bit of each byte.
            for index in 0..<encoded {
                let bit = bitOffset + index
                samples[index] = value(of: UInt64((bytes[bit >> 3] >> UInt8(bit & 7)) & 1))
            }
        } else {
            let width = description.bitsAllocated / 8
            let bigEndianCells = byteLayout == .bigEndianCells
            for index in 0..<encoded {
                let base = index * width
                var cell: UInt64 = 0
                for byte in 0..<width {
                    let source = bigEndianCells ? bytes[base + byte] : bytes[base + width - 1 - byte]
                    cell = cell << 8 | UInt64(source)
                }
                samples[index] = value(of: cell)
            }
        }
        return arrangeByPixel(samples)
    }

    /// Floating point sample values of one frame (Float or Double Float Pixel
    /// Data), in the same order as `storedValues(frame:)`.
    public func floatingPointValues(frame: Int) throws -> [Double] {
        guard description.sampleFormat != .integer else {
            return try storedValues(frame: frame).map(Double.init)
        }
        let (range, _) = try byteRange(of: frame)
        try checkSampleBuffer(of: Double.self)
        let bytes = try normalizedBytes(in: range)
        let width = description.bitsAllocated / 8
        let bigEndian = byteLayout == .bigEndianCells
        var values = [Double](repeating: 0, count: description.encodedSamplesPerFrame)
        for index in values.indices {
            var bits: UInt64 = 0
            for byte in 0..<width {
                let source = bigEndian ? bytes[index * width + byte] : bytes[index * width + width - 1 - byte]
                bits = bits << 8 | UInt64(source)
            }
            values[index] = width == 4 ? Double(Float(bitPattern: UInt32(bits))) : Double(bitPattern: bits)
        }
        return arrangeByPixel(values)
    }

    /// Checks the per-sample buffers of one frame, which hold up to
    /// `samplesPerPixel` values per pixel, against the description's limits.
    private func checkSampleBuffer<T>(of _: T.Type) throws {
        try description.limits.checkBuffer(
            count: DICOMImageLimits.product(description.pixelsPerFrame, description.samplesPerPixel),
            bytesPerElement: MemoryLayout<T>.stride)
    }

    /// Reorders encoded samples into `samplesPerPixel` values per pixel.
    private func arrangeByPixel<T>(_ encoded: [T]) -> [T] {
        let pixels = description.pixelsPerFrame
        let samplesPerPixel = description.samplesPerPixel
        if description.photometricInterpretation == .ybrFull422 {
            // Y1 Y2 CB CR for each horizontal pair; CB and CR are sited on
            // the first pixel and shared by both (PS3.3 C.7.6.3.1.2).
            var result: [T] = []
            result.reserveCapacity(pixels * 3)
            for pair in 0..<(pixels / 2) {
                let base = pair * 4
                result.append(contentsOf: [encoded[base], encoded[base + 2], encoded[base + 3]])
                result.append(contentsOf: [encoded[base + 1], encoded[base + 2], encoded[base + 3]])
            }
            return result
        }
        guard samplesPerPixel > 1, description.planarConfiguration == 1 else { return encoded }
        var result: [T] = []
        result.reserveCapacity(encoded.count)
        for pixel in 0..<pixels {
            for sample in 0..<samplesPerPixel {
                result.append(encoded[sample * pixels + pixel])
            }
        }
        return result
    }
}
