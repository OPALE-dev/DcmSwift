import Foundation

/// Deflated Image Frame Compression (1.2.840.10008.1.2.8.1, PS3.5 A.4.13):
/// each frame's native byte stream is compressed with raw Deflate (RFC 1951)
/// in one Fragment, followed by a NUL byte when its length is odd.
public struct DICOMDeflatedFrameCodec: DICOMPixelDataDecoder {
    public static let transferSyntaxUID = "1.2.840.10008.1.2.8.1"
    public var transferSyntaxUIDs: Set<String> { [Self.transferSyntaxUID] }

    public init() {}

    public func decode(_ encodedFrame: Data, description: DICOMPixelDescription) throws -> DICOMDecodedFrame {
        let frameBytes = (description.bitsPerFrame + 7) / 8
        let data: Data
        do {
            data = try DICOMDeflate.decompress(encodedFrame, maximumOutputLength: frameBytes)
        } catch {
            throw DICOMCodecError.corruptedData("\(error)")
        }
        guard data.count == frameBytes else {
            throw DICOMCodecError.corruptedData("inflated frame holds \(data.count) of \(frameBytes) bytes")
        }
        return DICOMDecodedFrame(description: description.decodedFrame(), data: data)
    }

    /// Compresses one native frame, padding the stream to an even length.
    public func encode(_ frame: Data) throws -> Data {
        var encoded = try DICOMDeflate.compress(frame)
        if encoded.count % 2 == 1 { encoded.append(0) }
        return encoded
    }
}
