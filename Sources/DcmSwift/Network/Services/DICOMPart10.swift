import Foundation

/// The File Meta Information of a DICOM Part 10 file (PS3.10 7.1) and where
/// its data set starts, read without parsing the data set.
public struct DICOMPart10Header: Equatable, Sendable {
    public var sopClassUID: String
    public var sopInstanceUID: String
    public var transferSyntaxUID: String
    /// Byte offset of the data set in the file.
    public var dataSetOffset: UInt64
    /// Byte length of the data set.
    public var dataSetLength: Int

    /// Reads the header of a Part 10 file.
    public static func read(_ url: URL) throws -> DICOMPart10Header {
        let file = try DICOMPOSIXFile.open(reading: url)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0
        var head = Data()
        while head.count < 1 << 16 {
            let chunk = try file.read(upTo: (1 << 16) - head.count)
            if chunk.isEmpty { break }
            head.append(chunk)
        }
        let bytes = [UInt8](head)
        guard bytes.count >= 132, bytes[128..<132].elementsEqual(Array("DICM".utf8)) else {
            throw DICOMCommandError("\(url.lastPathComponent) is not a DICOM Part 10 file")
        }
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }

        var values: [UInt16: String] = [:]
        var position = 132
        var end: Int?
        // File Meta Information elements: Explicit VR Little Endian.
        while position + 8 <= bytes.count, u16(position) == 0x0002, end.map({ position < $0 }) ?? true {
            let element = UInt16(u16(position + 2))
            let vr = String(decoding: bytes[(position + 4)..<(position + 6)], as: UTF8.self)
            var length: Int
            var valueStart: Int
            if ["OB", "OW", "OF", "SQ", "UT", "UN", "OD", "OL", "OV", "UC", "UR", "SV", "UV"].contains(vr) {
                guard position + 12 <= bytes.count else { break }
                length = u32(position + 8)
                valueStart = position + 12
            } else {
                length = u16(position + 6)
                valueStart = position + 8
            }
            guard length >= 0, valueStart + length <= bytes.count else {
                throw DICOMCommandError("truncated File Meta Information in \(url.lastPathComponent)")
            }
            if element == 0x0000, length == 4 {
                end = valueStart + 4 + u32(valueStart)
            }
            if ["UI", "AE", "SH", "CS"].contains(vr) {
                values[element] = String(decoding: bytes[valueStart..<(valueStart + length)], as: UTF8.self)
                    .trimmingCharacters(in: [" ", "\0"])
            }
            position = valueStart + length
        }
        let offset = end ?? position
        guard let sopClass = values[0x0002], let sopInstance = values[0x0003], let syntax = values[0x0010] else {
            throw DICOMCommandError("incomplete File Meta Information in \(url.lastPathComponent)")
        }
        guard UInt64(offset) <= size else { throw DICOMCommandError("File Meta Information overruns \(url.lastPathComponent)") }
        return DICOMPart10Header(
            sopClassUID: sopClass, sopInstanceUID: sopInstance, transferSyntaxUID: syntax,
            dataSetOffset: UInt64(offset), dataSetLength: Int(size - UInt64(offset)))
    }

    /// The preamble and File Meta Information for a data set (PS3.10 7.1).
    public static func encodeMetaInformation(
        sopClassUID: String, sopInstanceUID: String, transferSyntaxUID: String, sourceAETitle: String?
    ) -> Data {
        var elements = Data()
        func element(_ number: UInt16, _ vr: String, _ value: [UInt8]) {
            elements.append(contentsOf: [0x02, 0x00, UInt8(number & 0xFF), UInt8(number >> 8)])
            elements.append(contentsOf: Array(vr.utf8))
            if vr == "OB" {
                elements.append(contentsOf: [0, 0])
                elements.append(contentsOf: withUnsafeBytes(of: UInt32(value.count).littleEndian, Array.init))
            } else {
                elements.append(contentsOf: withUnsafeBytes(of: UInt16(value.count).littleEndian, Array.init))
            }
            elements.append(contentsOf: value)
        }
        func text(_ value: String, pad: UInt8) -> [UInt8] {
            var bytes = Array(value.utf8)
            if bytes.count % 2 == 1 { bytes.append(pad) }
            return bytes
        }
        element(0x0001, "OB", [0x00, 0x01])
        element(0x0002, "UI", text(sopClassUID, pad: 0))
        element(0x0003, "UI", text(sopInstanceUID, pad: 0))
        element(0x0010, "UI", text(transferSyntaxUID, pad: 0))
        element(0x0012, "UI", text(DICOMImplementation.classUID, pad: 0))
        element(0x0013, "SH", text(DICOMImplementation.versionName, pad: 0x20))
        if let sourceAETitle { element(0x0016, "AE", text(sourceAETitle, pad: 0x20)) }

        var data = Data(count: 128)
        data.append(contentsOf: Array("DICM".utf8))
        data.append(contentsOf: [0x02, 0x00, 0x00, 0x00, 0x55, 0x4C, 0x04, 0x00])
        data.append(contentsOf: withUnsafeBytes(of: UInt32(elements.count).littleEndian, Array.init))
        data.append(elements)
        return data
    }
}
