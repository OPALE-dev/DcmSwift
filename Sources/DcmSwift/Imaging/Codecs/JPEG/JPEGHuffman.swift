import Foundation

/// A Huffman table built from its DHT specification (ITU-T T.81 Annex C),
/// decoded with a 9-bit lookup table and the MAXCODE/VALPTR procedure of
/// F.2.2.3 for longer codes.
struct JPEGHuffmanTable {
    private static let lookupBits = 9

    private let values: [UInt8]
    private var maximumCode = [Int](repeating: -1, count: 18)
    private var valuePointer = [Int](repeating: 0, count: 17)
    private var minimumCode = [Int](repeating: 0, count: 17)
    /// (code length << 8 | value) for every 9-bit prefix, 0 when longer.
    private var lookup = [UInt16](repeating: 0, count: 1 << lookupBits)

    init(counts: [UInt8], values: [UInt8]) throws {
        guard counts.count == 16 else { throw DICOMCodecError.corruptedData("Huffman table needs 16 counts") }
        self.values = values
        var code = 0
        var index = 0
        for length in 1...16 {
            let count = Int(counts[length - 1])
            if count > 0 {
                valuePointer[length] = index
                minimumCode[length] = code
                for _ in 0..<count {
                    if length <= Self.lookupBits {
                        let shift = Self.lookupBits - length
                        for suffix in 0..<(1 << shift) {
                            lookup[(code << shift) | suffix] = UInt16(length << 8) | UInt16(values[index])
                        }
                    }
                    code += 1
                    index += 1
                }
                maximumCode[length] = code - 1
            }
            // Codes are canonical: every code must fit in its length.
            guard code <= 1 << length else { throw DICOMCodecError.corruptedData("Huffman table is over-subscribed") }
            code <<= 1
        }
        maximumCode[17] = Int.max
    }

    /// Decodes one value, or throws on an invalid code.
    func decode(_ reader: inout JPEGBitReader) throws -> Int {
        let entry = lookup[reader.peek(Self.lookupBits)]
        if entry != 0 {
            reader.skip(Int(entry >> 8))
            return Int(entry & 0xFF)
        }
        var code = reader.bits(Self.lookupBits)
        var length = Self.lookupBits
        while code > maximumCode[length] {
            code = (code << 1) | reader.bits(1)
            length += 1
            guard length <= 16 else { throw DICOMCodecError.corruptedData("JPEG Huffman code is invalid") }
        }
        let index = valuePointer[length] + code - minimumCode[length]
        guard index < values.count else { throw DICOMCodecError.corruptedData("JPEG Huffman code is invalid") }
        return Int(values[index])
    }
}

/// Reads entropy-coded bits, removing stuffed 00H bytes after FFH. A marker
/// stops the input: further reads return zero bits until the decoder
/// consumes a restart marker.
struct JPEGBitReader {
    private let data: ArraySlice<UInt8>
    private var position: Int
    private var buffer: UInt64 = 0
    private var count = 0
    /// The marker reached, if any (D0H-D7H for restart markers).
    private(set) var marker: UInt8?

    init(_ data: ArraySlice<UInt8>) {
        self.data = data
        self.position = data.startIndex
    }

    private mutating func fill() {
        while count <= 56 {
            var byte: UInt8 = 0
            if marker == nil && position < data.endIndex {
                byte = data[position]
                if byte == 0xFF {
                    // FFH fill bytes may precede a marker (T.81 B.1.1.2).
                    var last = position
                    while last + 1 < data.endIndex && data[last + 1] == 0xFF { last += 1 }
                    let next = last + 1 < data.endIndex ? data[last + 1] : 0xD9
                    if next == 0x00 && last == position {
                        position += 2
                    } else {
                        position = last
                        marker = next
                        byte = 0
                    }
                } else {
                    position += 1
                }
            }
            buffer |= UInt64(byte) << UInt64(56 - count)
            count += 8
        }
    }

    mutating func peek(_ bits: Int) -> Int {
        if count < bits { fill() }
        return Int(buffer >> UInt64(64 - bits))
    }

    mutating func skip(_ bits: Int) {
        if count < bits { fill() }
        buffer <<= UInt64(bits)
        count -= bits
    }

    mutating func bits(_ bits: Int) -> Int {
        guard bits > 0 else { return 0 }
        let value = peek(bits)
        skip(bits)
        return value
    }

    /// Receives `size` bits and extends them to a signed difference
    /// (T.81 F.2.2.1, RECEIVE and EXTEND).
    mutating func receiveExtend(_ size: Int) -> Int {
        guard size > 0 else { return 0 }
        let value = bits(size)
        return value < 1 << (size - 1) ? value - (1 << size) + 1 : value
    }

    /// Consumes the expected restart marker and resets the bit buffer.
    mutating func restart(expecting index: Int) throws {
        // Discard the bits left before the marker.
        buffer = 0
        count = 0
        if marker == nil {
            while position + 1 < data.endIndex && !(data[position] == 0xFF && data[position + 1] != 0x00) {
                position += 1
            }
            if position + 1 < data.endIndex { marker = data[position + 1] }
        }
        guard let marker, marker == 0xD0 + UInt8(index & 7) else {
            throw DICOMCodecError.corruptedData("JPEG restart marker RST\(index & 7) is missing")
        }
        position += 2
        self.marker = nil
    }
}
