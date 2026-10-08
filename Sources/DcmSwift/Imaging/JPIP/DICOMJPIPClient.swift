import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1

/// Retrieves the Pixel Data of instances encoded in a JPIP Referenced
/// Transfer Syntax (PS3.5 8.4.1, A.6, A.7, A.11, A.12) from their Pixel Data
/// Provider URL (0028,7FE0), with JPIP over HTTP (ISO/IEC 15444-9).
///
/// Each frame is requested at full resolution and quality, then rebuilt as
/// a JPEG 2000 or HTJ2K codestream that the built-in codecs decode.
public final class DICOMJPIPClient: Sendable {
    private let httpClient: HTTPClient
    public let timeout: TimeAmount
    /// Header fields added to every request, such as Authorization.
    public let headers: [(name: String, value: String)]
    /// The most requests made for one frame when the server ends its
    /// responses early (byte or response limits).
    public let maximumRequestsPerFrame: Int
    /// The `len` request field: the most bytes asked for per response.
    public let maximumResponseLength: Int

    public init(httpClient: HTTPClient = .shared, timeout: TimeAmount = .seconds(60),
                headers: [(name: String, value: String)] = [], maximumRequestsPerFrame: Int = 64,
                maximumResponseLength: Int = 1 << 30) {
        self.httpClient = httpClient
        self.timeout = timeout
        self.headers = headers
        self.maximumRequestsPerFrame = maximumRequestsPerFrame
        self.maximumResponseLength = maximumResponseLength
    }

    // MARK: DICOM instances

    /// Whether a data set references its Pixel Data through JPIP.
    public static func isJPIPReferenced(_ dataSet: DataSet) -> Bool {
        guard let uid = dataSet.transferSyntax?.tsUID else { return false }
        return TransferSyntax.jpipReferencedSyntaxes.contains(uid)
    }

    /// The codestream of a frame, one-based. Multi-frame images address
    /// frame N as code stream N of the provider (PS3.5 8.4.1).
    public func codestream(of dataSet: DataSet, frame: Int = 1) async throws -> Data {
        guard let url = dataSet.string(forTag: "PixelDataProviderURL"), !url.isEmpty else {
            throw JPIPError("the data set has no Pixel Data Provider URL")
        }
        let description = try DICOMPixelDescription(dataset: dataSet)
        guard (1...description.numberOfFrames).contains(frame) else {
            throw DICOMPixelDataError.frameOutOfRange(frame, numberOfFrames: description.numberOfFrames)
        }
        let multiFrame = dataSet.element(forTagName: "NumberOfFrames") != nil
        return try await codestream(providerURL: url, width: description.columns, height: description.rows,
                                    stream: multiFrame ? frame : nil)
    }

    /// The decoded frames of an instance in a JPIP Referenced Transfer
    /// Syntax.
    public func decodedFrames(of dataSet: DataSet) async throws -> [DICOMDecodedFrame] {
        let description = try DICOMPixelDescription(dataset: dataSet)
        let (decoder, frameDescription) = try Self.decoder(for: dataSet, description: description)
        var frames: [DICOMDecodedFrame] = []
        for frame in 1...description.numberOfFrames {
            frames.append(try decoder.decode(try await codestream(of: dataSet, frame: frame), description: frameDescription))
        }
        return frames
    }

    /// A copy of the instance with its Pixel Data retrieved: the frames are
    /// encapsulated in the matching JPEG 2000 or HTJ2K Transfer Syntax, so
    /// that it renders, converts, and stores like any other instance.
    public func resolve(_ dataSet: DataSet) async throws -> DataSet {
        guard let uid = dataSet.transferSyntax?.tsUID, TransferSyntax.jpipReferencedSyntaxes.contains(uid) else {
            throw JPIPError("the data set is not in a JPIP Referenced Transfer Syntax")
        }
        let description = try DICOMPixelDescription(dataset: dataSet)
        var codestreams: [Data] = []
        for frame in 1...description.numberOfFrames {
            codestreams.append(try await codestream(of: dataSet, frame: frame))
        }
        let ht = uid == TransferSyntax.jpipHTJ2KReferenced || uid == TransferSyntax.jpipHTJ2KReferencedDeflate
        // Reversible codestreams are lossless (COD transformation 1).
        let reversible = codestreams.allSatisfy { Self.isReversible($0) }
        let target = ht ? (reversible ? DICOMJPEG2000Codec.htj2kLossless : DICOMJPEG2000Codec.htj2k)
            : (reversible ? DICOMJPEG2000Codec.lossless : DICOMJPEG2000Codec.lossy)

        let copy = try DICOMDataSetCoding.decode(
            try DICOMDataSetCoding.encode(dataSet, transferSyntax: TransferSyntax.explicitVRLittleEndian),
            transferSyntax: TransferSyntax.explicitVRLittleEndian)
        if let element = copy.element(forTagName: "PixelDataProviderURL") { _ = copy.remove(dataElement: element) }
        let sequence = PixelSequence(withTag: DataTag(withGroup: "7fe0", element: "0010"))
        sequence.vr = .OB
        sequence.length = -1
        sequence.dataset = copy
        var offsets = Data(), position = 0
        for codestream in codestreams {
            offsets += withUnsafeBytes(of: UInt32(position).littleEndian, Array.init)
            position += 8 + codestream.count + codestream.count % 2
        }
        for value in [offsets] + codestreams.map({ $0.count % 2 == 1 ? $0 + Data([0]) : $0 }) {
            let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
            item.data = value
            item.length = value.count
            sequence.items.append(item)
        }
        copy.add(element: sequence)
        copy.transferSyntax = TransferSyntax(target)
        if !reversible { _ = copy.set(value: "01", forTagName: "LossyImageCompression") }
        return copy
    }

    static func decoder(
        for dataSet: DataSet, description: DICOMPixelDescription
    ) throws -> (any DICOMPixelDataDecoder, DICOMPixelDescription) {
        let uid = dataSet.transferSyntax?.tsUID ?? ""
        let ht = uid == TransferSyntax.jpipHTJ2KReferenced || uid == TransferSyntax.jpipHTJ2KReferencedDeflate
        let codestreamSyntax = ht ? DICOMJPEG2000Codec.htj2k : DICOMJPEG2000Codec.lossy
        guard let decoder = DICOMCodecRegistry.decoder(for: codestreamSyntax) else {
            throw DICOMCodecError.unsupportedTransferSyntax(codestreamSyntax)
        }
        let frame = DICOMPixelDescription(
            rows: description.rows, columns: description.columns, samplesPerPixel: description.samplesPerPixel,
            photometricInterpretation: description.photometricInterpretation, bitsAllocated: description.bitsAllocated,
            bitsStored: description.bitsStored, highBit: description.highBit, isSigned: description.isSigned,
            planarConfiguration: description.planarConfiguration, numberOfFrames: 1, isEncapsulated: true)
        return (decoder, frame)
    }

    /// Whether the first COD of a codestream uses the reversible 5-3 wavelet.
    static func isReversible(_ codestream: Data) -> Bool {
        let bytes = [UInt8](codestream.prefix(1 << 16))
        var position = 2
        while position + 4 <= bytes.count, bytes[position] == 0xFF {
            let marker = bytes[position + 1], length = Int(bytes[position + 2]) << 8 | Int(bytes[position + 3])
            if marker == 0x52, position + 13 < bytes.count { return bytes[position + 13] == 1 }
            if marker == 0x90 { break }
            position += 2 + length
        }
        return false
    }

    // MARK: JPIP

    /// The full-resolution codestream of an image served by a JPIP server:
    /// `stream` selects a code stream of a multi-codestream target.
    public func codestream(providerURL: String, width: Int, height: Int, stream: Int? = nil) async throws -> Data {
        var cache = JPIPCache()
        var parser = JPIPStreamParser()
        var channel: (id: String, base: String)?
        let window = "fsiz=\(width),\(height)&rsiz=\(width),\(height)&roff=0,0&len=\(maximumResponseLength)"
            + (stream.map { "&stream=\($0)" } ?? "")
        defer {
            if let channel {
                // Closing the channel frees the server's session.
                let url = channel.base + Self.separator(channel.base) + "cclose=\(channel.id)&cid=\(channel.id)"
                let request = HTTPClientRequest(url: url)
                let client = httpClient, timeout = self.timeout
                Task { _ = try? await client.execute(request, timeout: timeout) }
            }
        }
        for attempt in 0..<maximumRequestsPerFrame {
            let url: String
            if let channel {
                url = channel.base + Self.separator(channel.base) + "cid=\(channel.id)&type=jpp-stream,jpt-stream&" + window
            } else {
                url = providerURL + Self.separator(providerURL) + "type=jpp-stream,jpt-stream&cnew=http&" + window
            }
            var request = HTTPClientRequest(url: url)
            for header in headers { request.headers.add(name: header.name, value: header.value) }
            let response = try await httpClient.execute(request, timeout: timeout)
            guard (200..<300).contains(Int(response.status.code)) else {
                let body = try await DICOMwebClient.collect(response.body)
                throw JPIPError("\(response.status.code) from \(url): \(String(decoding: body.prefix(500), as: UTF8.self))")
            }
            let type = response.headers["Content-Type"].first.flatMap(DICOMwebMediaType.init)?.essence ?? ""
            switch type {
            case "image/jp2", "image/jph", "image/jpx":
                return try Self.contiguousCodestream(try await DICOMwebClient.collect(response.body), index: stream ?? 0)
            case "image/jphc", "image/j2c", "image/jpc":
                return try await DICOMwebClient.collect(response.body)
            case "image/jpp-stream", "image/jpt-stream":
                break
            default:
                throw JPIPError("unsupported Content-Type \(type)")
            }
            if channel == nil, attempt == 0, let created = response.headers["JPIP-cnew"].first {
                channel = Self.channel(created, providerURL: providerURL)
            }
            var reason: UInt8?
            for try await buffer in response.body {
                for message in try parser.feed(buffer.readableBytesView) {
                    if case .endOfResponse(let code, _) = message { reason = code } else { try cache.add(message) }
                }
            }
            try parser.finish()
            let codestreamIndex = stream ?? cache.codestreams.first ?? 0
            // Image or window done: everything asked for was sent.
            if reason == JPIPEndOfResponseReason.imageDone.rawValue || reason == JPIPEndOfResponseReason.windowDone.rawValue
                || reason == nil {
                return try JPIPCodestream.build(from: cache, codestream: codestreamIndex)
            }
            guard channel != nil else {
                // Without a session, only a complete cache can be used.
                return try JPIPCodestream.build(from: cache, codestream: codestreamIndex)
            }
        }
        throw JPIPError("the server did not complete the image in \(maximumRequestsPerFrame) requests")
    }

    private static func separator(_ url: String) -> String { url.contains("?") ? "&" : "?" }

    /// The channel of a JPIP-cnew response header (ISO/IEC 15444-9 D.2.3):
    /// its identifier, and the URL for its requests.
    static func channel(_ value: String, providerURL: String) -> (id: String, base: String)? {
        var fields: [String: String] = [:]
        for field in value.split(separator: ",") {
            let pair = field.split(separator: "=", maxSplits: 1)
            if pair.count == 2 { fields[pair[0].trimmingCharacters(in: .whitespaces)] = String(pair[1]) }
        }
        guard let id = fields["cid"] else { return nil }
        // Later requests go to the channel's path on the same server, or to
        // the provider URL; the target stays implied by the channel.
        guard var components = URLComponents(string: providerURL) else { return nil }
        if let path = fields["path"] {
            components.path = path.hasPrefix("/") ? path : "/" + path
            components.query = nil
        }
        return (id, components.string ?? providerURL)
    }

    /// The contiguous codestream box of a JP2-family file (ISO/IEC 15444-1
    /// I.5.4); `index` selects one of several.
    static func contiguousCodestream(_ file: Data, index: Int) throws -> Data {
        let bytes = [UInt8](file)
        var position = 0, found = 0
        while position + 8 <= bytes.count {
            var length = Int(bytes[position]) << 24 | Int(bytes[position + 1]) << 16 | Int(bytes[position + 2]) << 8
                | Int(bytes[position + 3])
            let type = String(decoding: bytes[(position + 4)..<(position + 8)], as: UTF8.self)
            var header = 8
            if length == 1 {
                guard position + 16 <= bytes.count else { break }
                length = bytes[(position + 8)..<(position + 16)].reduce(0) { $0 << 8 | Int($1) }
                header = 16
            } else if length == 0 {
                length = bytes.count - position
            }
            guard length >= header, position + length <= bytes.count else { throw JPIPError("truncated JP2 box") }
            if type == "jp2c" {
                if found == index { return Data(bytes[(position + header)..<(position + length)]) }
                found += 1
            }
            position += length
        }
        throw JPIPError("no contiguous codestream \(index) in the file")
    }
}
