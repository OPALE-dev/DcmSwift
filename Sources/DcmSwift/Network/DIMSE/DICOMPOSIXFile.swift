import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// A file opened with POSIX calls, which report errors instead of raising
/// exceptions, and closed with its last reference.
final class DICOMPOSIXFile {
    private var descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        if descriptor >= 0 { _ = closeDescriptor(descriptor) }
    }

    static func open(reading url: URL) throws -> DICOMPOSIXFile {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { openFile($0, O_RDONLY | O_CLOEXEC, 0) } ?? -1
        }
        guard descriptor >= 0 else { throw error("open \(url.path)") }
        return DICOMPOSIXFile(descriptor: descriptor)
    }

    /// Creates a new file readable and writable by the owner only.
    static func create(_ url: URL) throws -> DICOMPOSIXFile {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { openFile($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600) } ?? -1
        }
        guard descriptor >= 0 else { throw error("create \(url.path)") }
        return DICOMPOSIXFile(descriptor: descriptor)
    }

    func seek(to offset: UInt64) throws {
        guard lseek(descriptor, off_t(offset), SEEK_SET) >= 0 else { throw Self.error("seek") }
    }

    /// Reads up to `count` bytes; an empty result is the end of the file.
    func read(upTo count: Int) throws -> Data {
        var data = Data(count: count)
        let read = data.withUnsafeMutableBytes { buffer -> Int in
            while true {
                let result = readDescriptor(descriptor, buffer.baseAddress, count)
                if result < 0, errno == EINTR { continue }
                return result
            }
        }
        guard read >= 0 else { throw Self.error("read") }
        data.count = read
        return data
    }

    func write(_ data: Data) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = writeDescriptor(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw Self.error("write")
                }
                offset += written
            }
        }
    }

    func close() throws {
        guard descriptor >= 0 else { return }
        let result = closeDescriptor(descriptor)
        descriptor = -1
        guard result == 0 else { throw Self.error("close") }
    }

    private static func error(_ operation: String) -> DICOMCommandError {
        DICOMCommandError("cannot \(operation): \(String(cString: strerror(errno)))")
    }
}

private func openFile(_ path: UnsafePointer<CChar>, _ flags: Int32, _ mode: mode_t) -> Int32 {
    #if canImport(Darwin)
    return Darwin.open(path, flags, mode)
    #elseif canImport(Glibc)
    return Glibc.open(path, flags, mode)
    #else
    return Musl.open(path, flags, mode)
    #endif
}

private func readDescriptor(_ descriptor: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int) -> Int {
    #if canImport(Darwin)
    return Darwin.read(descriptor, buffer, count)
    #elseif canImport(Glibc)
    return Glibc.read(descriptor, buffer, count)
    #else
    return Musl.read(descriptor, buffer, count)
    #endif
}

private func writeDescriptor(_ descriptor: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
    #if canImport(Darwin)
    return Darwin.write(descriptor, buffer, count)
    #elseif canImport(Glibc)
    return Glibc.write(descriptor, buffer, count)
    #else
    return Musl.write(descriptor, buffer, count)
    #endif
}

private func closeDescriptor(_ descriptor: Int32) -> Int32 {
    #if canImport(Darwin)
    return Darwin.close(descriptor)
    #elseif canImport(Glibc)
    return Glibc.close(descriptor)
    #else
    return Musl.close(descriptor)
    #endif
}
