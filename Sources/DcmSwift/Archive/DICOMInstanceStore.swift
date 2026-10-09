import Foundation

/// Where an archive keeps the bytes of its composite instances, apart from
/// their index: a directory, object storage, or a database's large objects.
/// A location is an opaque string the store chooses.
public protocol DICOMInstanceStore: Sendable {
    /// Writes a received instance as a Part 10 file, or the store's
    /// equivalent; returns its location.
    func write(_ instance: DICOMReceivedInstance) async throws -> String

    /// The instance at a location, to send by C-STORE or over DICOMweb.
    func item(at location: String) async throws -> DICOMRetrieveItem

    /// Whether the instance at a location still exists.
    func exists(_ location: String) async -> Bool

    /// Removes the instance at a location.
    func remove(_ location: String) async throws
}

/// Instances as Part 10 files in a directory, named
/// `<SOP Instance UID>.dcm`; a location is the file's path.
public struct DICOMFileInstanceStore: DICOMInstanceStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func write(_ instance: DICOMReceivedInstance) async throws -> String {
        guard DICOMUniqueIdentifier.isValid(instance.sopInstanceUID) else {
            throw DICOMCommandError("invalid SOP Instance UID")
        }
        let url = directory.appendingPathComponent(instance.sopInstanceUID + ".dcm")
        try instance.write(to: url)
        return url.path
    }

    public func item(at location: String) async throws -> DICOMRetrieveItem {
        try DICOMRetrieveItem(file: URL(fileURLWithPath: location))
    }

    public func exists(_ location: String) async -> Bool {
        FileManager.default.fileExists(atPath: location)
    }

    public func remove(_ location: String) async throws {
        try FileManager.default.removeItem(atPath: location)
    }

    /// The Part 10 files of the directory, searched recursively.
    public func files() -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var urls: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { urls.append(url) }
        }
        return urls.sorted { $0.path < $1.path }
    }
}
