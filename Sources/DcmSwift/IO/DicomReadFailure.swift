import Foundation

/// Where and why reading a data set stopped before the end of its stream.
///
/// Returned by ``DicomInputStream/readPartialDataset(headerOnly:withoutPixelData:enforceVR:)``
/// and kept by a ``DicomFile`` read with ``DicomFile/init(tolerantlyReadingPath:transferSyntax:bulkDataLoadingPolicy:)``.
public struct DicomReadFailure: Error, Sendable, Equatable, CustomStringConvertible {
    /// The byte offset, from the start of the stream, at which the reader
    /// stopped: the bytes before it were consumed, those after it were not read.
    public let offset: Int
    /// The tag of the element being read, as eight lowercase hexadecimal
    /// digits, or nil when no tag could be read.
    public let tag: String?
    /// What could not be read, in English.
    public let message: String
    /// What could not be read, to translate.
    public let diagnostic: DICOMDiagnostic

    /// Creates a read failure.
    ///
    /// - Parameters:
    ///   - offset: the byte offset at which the reader stopped.
    ///   - tag: the tag of the element being read, as eight hexadecimal digits.
    ///   - message: what could not be read.
    public init(offset: Int, tag: String?, message: String) {
        self.init(offset: offset, tag: tag, diagnostic: .parsing(message))
    }

    /// Creates a read failure from its diagnostic.
    public init(offset: Int, tag: String?, diagnostic: DICOMDiagnostic) {
        self.offset = offset
        self.tag = tag?.lowercased()
        self.diagnostic = diagnostic
        self.message = diagnostic.description
    }

    public var description: String {
        "\(message) (reading stopped at offset \(offset))"
    }
}
