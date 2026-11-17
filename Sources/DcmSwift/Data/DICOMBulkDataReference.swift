import Foundation

/// A file-backed DICOM Value Field that has not been loaded into memory.
public final class DICOMBulkDataReference {
    public let url:URL
    public let offset:Int
    public let length:Int

    public init(url:URL, offset:Int, length:Int) {
        self.url = url
        self.offset = offset
        self.length = length
    }

    public func load() throws -> Data {
        return try load(range: 0..<length)
    }

    /// Reads a subrange without materializing the complete Value Field.
    public func load(range:Range<Int>) throws -> Data {
        guard offset >= 0, length >= 0,
              range.lowerBound >= 0, range.upperBound <= length else {
            throw StreamError.cannotReadStream(message: "Invalid Bulk Data range")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        handle.seek(toFileOffset: UInt64(offset + range.lowerBound))
        let requestedLength = range.count
        let data = handle.readData(ofLength: requestedLength)
        guard data.count == requestedLength else {
            throw StreamError.cannotReadStream(
                message: "Truncated Bulk Data at offset \(offset + range.lowerBound): expected \(requestedLength), read \(data.count)"
            )
        }
        return data
    }
}

/// Controls whether eligible binary Value Fields are read immediately.
public enum DICOMBulkDataLoadingPolicy: Equatable {
    case eager
    case lazy(minimumLength:Int)
}
