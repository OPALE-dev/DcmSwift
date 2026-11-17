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
                    // Codes are canonical: each must fit in its length, which
                    // also keeps lookup indices in range.
                    guard code < 1 << length else {
                        throw DICOMCodecError.corruptedData("Huffman table is over-subscribed")
                    }
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

/// A Huffman code optimized for observed symbol frequencies (ITU-T T.81
/// Annex K.2), with code lengths limited to 16 bits.
struct JPEGHuffmanEncoder {
    /// BITS: the number of codes of each length 1...16.
    let counts: [UInt8]
    /// HUFFVAL: symbols in order of increasing code length.
    let values: [UInt8]
    private var codes = [Int](repeating: 0, count: 256)
    private var lengths = [Int](repeating: 0, count: 256)

    init(frequencies input: [Int]) {
        precondition(input.count == 256)
        // A reserved symbol with frequency 1 keeps the all-ones code unused
        // (Figure K.1).
        var frequency = input + [1]
        var codeSize = [Int](repeating: 0, count: 257)
        var others = [Int](repeating: -1, count: 257)

        while true {
            // V1: the least frequent symbol; V2: the next least frequent.
            var v1 = -1
            var v2 = -1
            for symbol in 0..<257 where frequency[symbol] > 0 {
                if v1 < 0 || frequency[symbol] <= frequency[v1] {
                    v2 = v1
                    v1 = symbol
                } else if v2 < 0 || frequency[symbol] <= frequency[v2] {
                    v2 = symbol
                }
            }
            guard v2 >= 0 else { break }
            frequency[v1] += frequency[v2]
            frequency[v2] = 0
            codeSize[v1] += 1
            var chain = v1
            while others[chain] >= 0 {
                chain = others[chain]
                codeSize[chain] += 1
            }
            others[chain] = v2
            codeSize[v2] += 1
            chain = v2
            while others[chain] >= 0 {
                chain = others[chain]
                codeSize[chain] += 1
            }
        }

        // Count codes of each size (Figure K.2) and limit them to 16 bits
        // (Figure K.3).
        var bits = [Int](repeating: 0, count: 33)
        for symbol in 0..<257 where codeSize[symbol] > 0 {
            bits[codeSize[symbol]] += 1
        }
        var length = 32
        while length > 16 {
            while bits[length] > 0 {
                var shorter = length - 2
                while bits[shorter] == 0 { shorter -= 1 }
                bits[length] -= 2
                bits[length - 1] += 1
                bits[shorter + 1] += 2
                bits[shorter] -= 1
            }
            length -= 1
        }
        // Remove the reserved code from the longest length.
        length = 16
        while bits[length] == 0 { length -= 1 }
        bits[length] -= 1

        // Sort symbols by code size (Figure K.4), excluding the reserved one.
        var sorted: [UInt8] = []
        for size in 1...32 {
            for symbol in 0..<256 where codeSize[symbol] == size {
                sorted.append(UInt8(symbol))
            }
        }
        counts = (1...16).map { UInt8(bits[$0]) }
        values = sorted

        // Canonical codes (Annex C).
        var code = 0
        var index = 0
        for size in 1...16 {
            for _ in 0..<bits[size] {
                codes[Int(values[index])] = code
                lengths[Int(values[index])] = size
                code += 1
                index += 1
            }
            code <<= 1
        }
    }

    /// The DHT segment payload for this table.
    func specification(tableClass: UInt8, identifier: UInt8) -> [UInt8] {
        [tableClass << 4 | identifier] + counts + values
    }

    func write(_ symbol: Int, to writer: inout JPEGBitWriter) {
        writer.write(codes[symbol], bits: lengths[symbol])
    }
}

/// Writes entropy-coded bits most significant first, stuffing 00H after
/// every FFH byte.
struct JPEGBitWriter {
    private(set) var bytes: [UInt8] = []
    private var buffer: UInt64 = 0
    private var count = 0

    mutating func write(_ value: Int, bits: Int) {
        guard bits > 0 else { return }
        buffer = buffer << UInt64(bits) | UInt64(value & ((1 << bits) - 1))
        count += bits
        while count >= 8 {
            count -= 8
            let byte = UInt8((buffer >> UInt64(count)) & 0xFF)
            bytes.append(byte)
            if byte == 0xFF { bytes.append(0x00) }
        }
        buffer &= (UInt64(1) << UInt64(count)) - 1
    }

    /// Pads the last byte with one bits (F.1.2.3).
    mutating func flush() {
        if count > 0 { write((1 << (8 - count)) - 1, bits: 8 - count) }
    }

    mutating func restartMarker(_ index: Int) {
        flush()
        bytes += [0xFF, 0xD0 + UInt8(index & 7)]
    }
}
