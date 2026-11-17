import Foundation
import NIOPosix

/// Pull-driven response bodies. The lock protects iterator state if two consumers misuse
/// the same stream; blocking filesystem/codec work runs on the bounded NIO pool.
final class DICOMwebPayloadBody: @unchecked Sendable {
    private let lock = NSLock()
    private let parts: [(Data?, Data, DICOMDataSetPayload)]
    private let trailer: Data
    private var index = 0, phase = 0, remaining = 0
    private var chunks: (() throws -> Data?)?
    private var ended = false
    init(_ parts: [(Data?, Data, DICOMDataSetPayload)], trailer: Data) {
        self.parts = parts; self.trailer = trailer
    }
    func stream() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream(unfolding: {
            try Task.checkCancellation()
            return try await NIOThreadPool.singleton.runIfActive { try self.next() }
        })
    }
    private func next() throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        while index < parts.count {
            let (header, meta, payload) = parts[index]
            if phase == 0 { phase = 1; if let header, !header.isEmpty { return header } }
            if phase == 1 { phase = 2; if !meta.isEmpty { return meta } }
            if chunks == nil { chunks = try payload.chunkReader(of: 1 << 20); remaining = payload.length }
            if let chunk = try chunks?() { remaining -= chunk.count; return chunk }
            guard remaining == 0 else { throw DICOMCommandError("stored data set ended before its declared length") }
            chunks = nil; index += 1; phase = 0
        }
        guard !ended else { return nil }
        ended = true
        return trailer.isEmpty ? nil : trailer
    }
}

struct DICOMwebFrameSelection {
    enum Source {
        case native(DICOMNativePixelData)
        case encapsulated(DICOMEncapsulatedPixelData)
        func frame(_ number: Int, compressed: Bool) throws -> Data {
            switch self {
            case .native(let pixels): return try pixels.frameData(number - 1)
            case .encapsulated(let pixels):
                return compressed ? try pixels.encodedFrame(number - 1) : try pixels.decodedFrame(number - 1).data
            }
        }
    }
    let source: Source
    let numbers: [Int]
    let compressed: Bool
    let onePart: Bool
    let isFrameResource: Bool
    let headers: DICOMwebMultipart.Headers
    let instanceURL: String
}

/// One decoded/encoded frame at a time, including multi-frame Pixel Data responses.
final class DICOMwebFrameBody: @unchecked Sendable {
    private let lock = NSLock()
    private let selections: [DICOMwebFrameSelection]
    private var writer: DICOMwebMultipart.Writer
    private var selection = 0, frame = 0
    private var wroteHeader = false, ended = false
    private var pending: Data?
    init(_ selections: [DICOMwebFrameSelection], writer: DICOMwebMultipart.Writer) {
        self.selections = selections; self.writer = writer
    }
    func stream() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream(unfolding: {
            try Task.checkCancellation()
            return try await NIOThreadPool.singleton.runIfActive { try self.next() }
        })
    }
    private func next() throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        if let data = pending { pending = nil; return data }
        while selection < selections.count {
            let item = selections[selection]
            if item.onePart && !wroteHeader {
                wroteHeader = true
                var headers = item.headers; headers["Content-Location"] = item.instanceURL + "/pixeldata"
                return writer.partHeader(headers)
            }
            if frame < item.numbers.count {
                let number = item.numbers[frame]; frame += 1
                let data = try item.source.frame(number, compressed: item.compressed)
                if item.onePart { return data }
                var headers = item.headers
                headers["Content-Location"] = item.instanceURL + (item.isFrameResource ? "/frames/\(number)" : "/pixeldata")
                pending = data
                return writer.partHeader(headers, length: data.count)
            }
            selection += 1; frame = 0; wroteHeader = false
        }
        guard !ended else { return nil }; ended = true
        return writer.close()
    }
}
