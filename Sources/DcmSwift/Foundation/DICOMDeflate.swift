import CZlib
import Foundation

enum DICOMDeflate {
    private static let chunkSize = 64 * 1024

    static func compress(_ input:Data) throws -> Data {
        guard input.count <= Int(UInt32.max) else {
            throw StreamError.cannotWriteStream(message: "Raw Deflate input exceeds the current 4 GiB stream limit")
        }
        var stream = z_stream()
        let initialized = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            -MAX_WBITS,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initialized == Z_OK else {
            throw StreamError.cannotWriteStream(message: "Cannot initialize raw Deflate encoder")
        }
        defer { deflateEnd(&stream) }

        var output = Data()
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        try input.withUnsafeBytes { rawInput in
            stream.next_in = UnsafeMutablePointer<Bytef>(
                mutating: rawInput.bindMemory(to: Bytef.self).baseAddress
            )
            stream.avail_in = uInt(input.count)
            repeat {
                let status = buffer.withUnsafeMutableBufferPointer { pointer -> Int32 in
                    stream.next_out = pointer.baseAddress
                    stream.avail_out = uInt(pointer.count)
                    return deflate(&stream, Z_FINISH)
                }
                guard status == Z_OK || status == Z_STREAM_END else {
                    throw StreamError.cannotWriteStream(message: "Raw Deflate encoding failed (\(status))")
                }
                output.append(contentsOf: buffer.prefix(buffer.count - Int(stream.avail_out)))
                if status == Z_STREAM_END { break }
            } while true
        }
        if !output.count.isMultiple(of: 2) { output.append(0) }
        return output
    }

    static func decompress(_ input:Data, maximumOutputLength:Int) throws -> Data {
        guard input.count <= Int(UInt32.max) else {
            throw StreamError.cannotReadStream(message: "Raw Deflate input exceeds the current 4 GiB stream limit")
        }
        var stream = z_stream()
        let initialized = inflateInit2_(
            &stream,
            -MAX_WBITS,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initialized == Z_OK else {
            throw StreamError.cannotReadStream(message: "Cannot initialize raw Deflate decoder")
        }
        defer { inflateEnd(&stream) }

        var output = Data()
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        var reachedEnd = false
        try input.withUnsafeBytes { rawInput in
            stream.next_in = UnsafeMutablePointer<Bytef>(
                mutating: rawInput.bindMemory(to: Bytef.self).baseAddress
            )
            stream.avail_in = uInt(input.count)
            while !reachedEnd {
                let status = buffer.withUnsafeMutableBufferPointer { pointer -> Int32 in
                    stream.next_out = pointer.baseAddress
                    stream.avail_out = uInt(pointer.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                guard status == Z_OK || status == Z_STREAM_END else {
                    throw StreamError.cannotReadStream(message: "Raw Deflate decoding failed (\(status))")
                }
                let produced = buffer.count - Int(stream.avail_out)
                guard output.count <= maximumOutputLength - produced else {
                    throw StreamError.cannotReadStream(message: "Inflated Data Set exceeds configured maximum")
                }
                output.append(contentsOf: buffer.prefix(produced))
                reachedEnd = status == Z_STREAM_END
                if !reachedEnd && produced == 0 && stream.avail_in == 0 {
                    throw StreamError.cannotReadStream(message: "Truncated raw Deflate stream")
                }
            }
        }

        let remaining = Int(stream.avail_in)
        if remaining > 0 {
            guard remaining == 1, input.last == 0 else {
                throw StreamError.cannotReadStream(message: "Unexpected bytes after raw Deflate stream")
            }
        }
        return output
    }
}
