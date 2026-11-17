import Foundation

extension DICOMRenderedImage {
    /// Encodes the rendered 8-bit image as a baseline JPEG. `quality` is 1...100.
    public func jpegData(quality: Int = 90) throws -> Data {
        guard (1...100).contains(quality) else {
            throw DICOMPixelDataError.invalidAttribute("JPEG quality", "must be between 1 and 100")
        }
        let description = DICOMPixelDescription(
            rows: height, columns: width, samplesPerPixel: format.bytesPerPixel,
            photometricInterpretation: format == .gray8 ? .monochrome2 : .rgb,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false,
            planarConfiguration: 0, numberOfFrames: 1)
        var data = try DICOMJPEGBaselineCodec().encode(
            Data(pixels), description: description, quality: quality,
            subsampling: format == .gray8 ? .s444 : .s422).data
        // The DICOM codec pads odd-length fragments; a standalone JPEG ends
        // at EOI and does not need the DICOM Value Field padding byte.
        if data.count >= 3, data.suffix(3).elementsEqual([0xFF, 0xD9, 0x00]) {
            data.removeLast()
        }
        return data
    }

    /// Encodes an uncompressed, little-endian baseline TIFF with one strip.
    public func tiffData() -> Data {
        let samples = format.bytesPerPixel
        let entryCount: UInt16 = samples == 1 ? 9 : 10
        let ifdSize = 2 + Int(entryCount) * 12 + 4
        let bitsOffset = 8 + ifdSize
        let pixelOffset = bitsOffset + (samples == 1 ? 0 : 6)

        var data = Data([0x49, 0x49, 0x2A, 0x00])
        data.appendLE(UInt32(8))
        data.appendLE(entryCount)
        func entry(_ tag: UInt16, _ type: UInt16, _ count: UInt32, _ value: UInt32) {
            data.appendLE(tag); data.appendLE(type); data.appendLE(count); data.appendLE(value)
        }
        entry(256, 4, 1, UInt32(width))                 // ImageWidth
        entry(257, 4, 1, UInt32(height))                // ImageLength
        entry(258, 3, UInt32(samples), samples == 1 ? 8 : UInt32(bitsOffset))
        entry(259, 3, 1, 1)                             // Compression: none
        entry(262, 3, 1, samples == 1 ? 1 : 2)           // BlackIsZero / RGB
        entry(273, 4, 1, UInt32(pixelOffset))            // StripOffsets
        entry(277, 3, 1, UInt32(samples))                // SamplesPerPixel
        entry(278, 4, 1, UInt32(height))                 // RowsPerStrip
        entry(279, 4, 1, UInt32(pixels.count))           // StripByteCounts
        if samples == 3 { entry(284, 3, 1, 1) }          // Chunky RGB
        data.appendLE(UInt32(0))                         // next IFD
        if samples == 3 {
            data.appendLE(UInt16(8)); data.appendLE(UInt16(8)); data.appendLE(UInt16(8))
        }
        data.append(contentsOf: pixels)
        return data
    }

    /// Encodes Netpbm PGM (grayscale) or PPM (RGB), useful for lossless
    /// exchange with DCMTK, ImageMagick, and scientific imaging tools.
    public func pnmData() -> Data {
        var data = Data("P\(format == .gray8 ? 5 : 6)\n\(width) \(height)\n255\n".utf8)
        data.append(contentsOf: pixels)
        return data
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF)); append(UInt8(value >> 8))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF)); append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF)); append(UInt8(value >> 24))
    }
}
