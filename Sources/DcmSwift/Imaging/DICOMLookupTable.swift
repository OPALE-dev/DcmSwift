import Foundation

/// A Modality, VOI, or Palette Color lookup table (PS3.3 C.11.1.1.1,
/// C.11.2.1.1, C.7.6.3.1.5).
public struct DICOMLookupTable: Equatable, Sendable {
    /// The input value mapped to the first entry.
    public let firstValueMapped: Int
    /// Third Value of the descriptor: the range of the entries is
    /// 0...2^bitsPerEntry - 1.
    public let bitsPerEntry: Int
    public let entries: [UInt16]

    public init(firstValueMapped: Int, bitsPerEntry: Int, entries: [UInt16]) {
        self.firstValueMapped = firstValueMapped
        self.bitsPerEntry = bitsPerEntry
        self.entries = entries
    }

    /// Input values below the first value mapped use the first entry and
    /// values past the table use the last entry.
    public func entry(for input: Int) -> UInt16 {
        let index = input - firstValueMapped
        if index <= 0 { return entries[0] }
        if index >= entries.count { return entries[entries.count - 1] }
        return entries[index]
    }

    public var maximumEntryValue: Int { (1 << bitsPerEntry) - 1 }

    /// Reads a descriptor and its LUT Data. `signedFirstValue` gives the VR of
    /// the second descriptor Value when the encoding does not (Implicit VR).
    init(
        descriptor descriptorElement: DataElement,
        data dataElement: DataElement?,
        segmentedData: DataElement? = nil,
        signedFirstValue: Bool,
        allowedBits: ClosedRange<Int> = 8...16,
        name: String
    ) throws {
        let scope = DICOMAttributeScope(elements: [])
        let descriptor = scope.words(of: descriptorElement)
        guard descriptor.count >= 3 else {
            throw DICOMPixelDataError.invalidLookupTable(name, "descriptor needs three Values")
        }
        let count = descriptor[0] == 0 ? 65536 : Int(descriptor[0])
        let signed = descriptorElement.vr == .SS || (descriptorElement.vr != .US && signedFirstValue)
        firstValueMapped = signed ? Int(Int16(bitPattern: descriptor[1])) : Int(descriptor[1])
        bitsPerEntry = Int(descriptor[2])
        guard allowedBits.contains(bitsPerEntry) else {
            throw DICOMPixelDataError.invalidLookupTable(name, "\(bitsPerEntry) bits per entry")
        }

        if let segmentedData {
            entries = try Self.expandSegments(scope.words(of: segmentedData), count: count, name: name)
            return
        }
        guard let dataElement, let data = try? dataElement.loadData() else {
            throw DICOMPixelDataError.invalidLookupTable(name, "LUT Data is missing")
        }
        let bytes = [UInt8](data)
        if bitsPerEntry <= 8 && bytes.count < count * 2 {
            // One byte per entry, possibly followed by a padding byte.
            guard bytes.count >= count else {
                throw DICOMPixelDataError.invalidLookupTable(name, "\(bytes.count) bytes for \(count) entries")
            }
            if dataElement.byteOrder == .BigEndian && dataElement.vr == .OW {
                var swapped = bytes
                var index = 0
                while index + 1 < swapped.count { swapped.swapAt(index, index + 1); index += 2 }
                entries = swapped.prefix(count).map(UInt16.init)
            } else {
                entries = bytes.prefix(count).map(UInt16.init)
            }
        } else {
            // 16-bit words. Entries declared as 8 bits but encoded in 16
            // bits allocated keep only their low byte (PS3.3 C.11.1.1.1).
            let words = scope.words(of: dataElement)
            guard words.count >= count else {
                throw DICOMPixelDataError.invalidLookupTable(name, "\(words.count) words for \(count) entries")
            }
            let mask: UInt16 = bitsPerEntry >= 16 ? .max : (1 << bitsPerEntry) - 1
            entries = words.prefix(count).map { $0 & mask }
        }
    }

    /// Expands Segmented Palette Color Lookup Table Data (PS3.3 C.7.9.2).
    static func expandSegments(_ words: [UInt16], count: Int, name: String) throws -> [UInt16] {
        var output: [UInt16] = []
        output.reserveCapacity(count)

        func fail(_ reason: String) -> DICOMPixelDataError {
            .invalidLookupTable(name, "segmented data \(reason)")
        }

        /// Expands the segment starting at `index`; returns the next index.
        func expandSegment(at index: Int, allowIndirect: Bool) throws -> Int {
            guard index + 1 < words.count else { throw fail("ends inside a segment header") }
            let opcode = words[index]
            let length = Int(words[index + 1])
            switch opcode {
            case 0:
                guard index + 2 + length <= words.count else { throw fail("discrete segment is truncated") }
                output.append(contentsOf: words[(index + 2)..<(index + 2 + length)])
                guard output.count <= count else { throw fail("exceeds \(count) entries") }
                return index + 2 + length
            case 1:
                guard index + 2 < words.count else { throw fail("linear segment is truncated") }
                guard let start = output.last else { throw fail("starts with a linear segment") }
                let y0 = Double(start)
                let y1 = Double(words[index + 2])
                guard output.count + length <= count else { throw fail("exceeds \(count) entries") }
                for step in stride(from: 1, through: length, by: 1) {
                    let value = y0 + (y1 - y0) * Double(step) / Double(length)
                    output.append(UInt16(value.rounded()))
                }
                return index + 3
            case 2:
                guard allowIndirect else { throw fail("indirect segment refers to an indirect segment") }
                guard index + 3 < words.count else { throw fail("indirect segment is truncated") }
                let segments = length
                let byteOffset = Int(words[index + 2]) | Int(words[index + 3]) << 16
                guard byteOffset % 2 == 0 else { throw fail("indirect offset is not word aligned") }
                var target = byteOffset / 2
                for _ in 0..<segments {
                    target = try expandSegment(at: target, allowIndirect: false)
                }
                return index + 4
            default:
                throw fail("uses reserved opcode \(opcode)")
            }
        }

        var index = 0
        while index < words.count && output.count < count {
            index = try expandSegment(at: index, allowIndirect: true)
        }
        guard output.count == count else { throw fail("expands to \(output.count) of \(count) entries") }
        return output
    }
}

extension DICOMAttributeScope {
    init(elements: [DataElement]) {
        self.elements = elements
    }
}
