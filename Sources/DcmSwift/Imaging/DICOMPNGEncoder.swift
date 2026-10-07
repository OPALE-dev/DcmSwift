import CZlib
import Foundation

extension DICOMRenderedImage {
    /// Encodes the image as an 8-bit grayscale or truecolor PNG (ISO/IEC
    /// 15948) using the system zlib, so PNG export works on every platform.
    public func pngData() throws -> Data {
        let colorType: UInt8 = format == .gray8 ? 0 : 2
        let rowLength = width * format.bytesPerPixel

        // Filter type 0 (None) before each row.
        var filtered = [UInt8]()
        filtered.reserveCapacity((rowLength + 1) * height)
        for row in 0..<height {
            filtered.append(0)
            filtered.append(contentsOf: pixels[(row * rowLength)..<((row + 1) * rowLength)])
        }

        var compressedLength = compressBound(uLong(filtered.count))
        var compressed = [UInt8](repeating: 0, count: Int(compressedLength))
        let status = compressed.withUnsafeMutableBufferPointer { output in
            filtered.withUnsafeBufferPointer { input in
                compress2(output.baseAddress, &compressedLength, input.baseAddress, uLong(input.count), Z_BEST_SPEED)
            }
        }
        guard status == Z_OK else {
            throw StreamError.cannotWriteStream(message: "Cannot compress PNG image data (zlib \(status))")
        }

        var header = [UInt8]()
        header.append(contentsOf: UInt32(width).bigEndianBytes)
        header.append(contentsOf: UInt32(height).bigEndianBytes)
        header.append(contentsOf: [8, colorType, 0, 0, 0])

        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        Self.appendChunk("IHDR", header, to: &png)
        Self.appendChunk("IDAT", Array(compressed.prefix(Int(compressedLength))), to: &png)
        Self.appendChunk("IEND", [], to: &png)
        return png
    }

    private static func appendChunk(_ type: String, _ payload: [UInt8], to png: inout Data) {
        let typeBytes = Array(type.utf8)
        png.append(contentsOf: UInt32(payload.count).bigEndianBytes)
        png.append(contentsOf: typeBytes)
        png.append(contentsOf: payload)
        let checksum = (typeBytes + payload).withUnsafeBufferPointer {
            crc32(crc32(0, nil, 0), $0.baseAddress, uInt($0.count))
        }
        png.append(contentsOf: UInt32(checksum).bigEndianBytes)
    }
}

private extension UInt32 {
    var bigEndianBytes: [UInt8] {
        [UInt8(self >> 24), UInt8((self >> 16) & 0xFF), UInt8((self >> 8) & 0xFF), UInt8(self & 0xFF)]
    }
}
