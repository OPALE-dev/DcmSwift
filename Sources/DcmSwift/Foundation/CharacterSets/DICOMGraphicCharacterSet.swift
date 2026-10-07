import Foundation

/// A Graphic Character Set that DICOM designates to the G0 or G1 code element
/// (PS3.3 Tables C.12-2 to C.12-4, PS3.5 6.1.2.5).
enum DICOMGraphicCharacterSet: Hashable, Sendable {
    /// ISO-IR 6, the Default Character Repertoire (G0).
    case ascii
    /// ISO-IR 14, JIS X 0201 romaji (G0).
    case jisRomaji
    /// A single-byte G1 set identified by its ISO-IR registration number.
    case singleByte(registration: Int)
    /// ISO-IR 87, JIS X 0208 kanji (G0).
    case jisX0208
    /// ISO-IR 159, JIS X 0212 supplementary kanji (G0).
    case jisX0212
    /// ISO-IR 149, KS X 1001 Hangul and Hanja (G1).
    case ksX1001
    /// ISO-IR 58, GB 2312 simplified Chinese (G1).
    case gb2312

    /// Every set DICOM defines, used to recognize escape sequences.
    static let all: [Self] = [.ascii, .jisRomaji, .singleByte(registration: 13),
                              .jisX0208, .jisX0212, .ksX1001, .gb2312]
        + singleByteFinalBytes.keys.sorted().map { .singleByte(registration: $0) }

    /// Final bytes of the ESC 02/13 F sequences that designate 96-character
    /// sets to G1, by ISO-IR registration number (PS3.3 Table C.12-3).
    private static let singleByteFinalBytes: [Int: UInt8] = [
        100: 0x41, 101: 0x42, 109: 0x43, 110: 0x44, 144: 0x4C, 127: 0x47,
        126: 0x46, 138: 0x48, 148: 0x4D, 203: 0x62, 166: 0x54
    ]

    static func singleByteSetExists(registration: Int) -> Bool {
        return registration == 13 || singleByteFinalBytes[registration] != nil
    }

    var isG0: Bool {
        switch self {
        case .ascii, .jisRomaji, .jisX0208, .jisX0212: return true
        case .singleByte, .ksX1001, .gb2312: return false
        }
    }

    var isMultiByte: Bool {
        switch self {
        case .jisX0208, .jisX0212, .ksX1001, .gb2312: return true
        case .ascii, .jisRomaji, .singleByte: return false
        }
    }

    /// The bytes following ESC that designate this set.
    var escapeSequence: [UInt8] {
        switch self {
        case .ascii: return [0x28, 0x42]
        case .jisRomaji: return [0x28, 0x4A]
        case .singleByte(13): return [0x29, 0x49]
        case .singleByte(let registration): return [0x2D, Self.singleByteFinalBytes[registration] ?? 0]
        case .jisX0208: return [0x24, 0x42]
        case .jisX0212: return [0x24, 0x28, 0x44]
        case .ksX1001: return [0x24, 0x29, 0x43]
        case .gb2312: return [0x24, 0x29, 0x41]
        }
    }

    // MARK: Decoding

    /// Decodes one GL byte (21H-7EH) of a single-byte G0 set. Byte 5CH is
    /// handled by the caller because it may be the value delimiter.
    func decode(gl byte: UInt8) -> Unicode.Scalar? {
        switch self {
        case .ascii:
            return Unicode.Scalar(byte)
        case .jisRomaji:
            switch byte {
            case 0x5C: return "\u{00A5}"
            case 0x7E: return "\u{203E}"
            default: return Unicode.Scalar(byte)
            }
        default:
            return nil
        }
    }

    /// Decodes one GR byte (A0H-FFH) of a single-byte G1 set.
    func decode(gr byte: UInt8) -> Unicode.Scalar? {
        guard case .singleByte = self, let table = singleByteTable, byte >= 0xA0 else { return nil }
        let value = table[Int(byte - 0xA0)]
        return value == 0 ? nil : Unicode.Scalar(value)
    }

    /// Decodes a two-byte character given as 7-bit row and cell (21H-7EH).
    func decode(row: UInt8, cell: UInt8) -> Unicode.Scalar? {
        guard let table = multiByteTable,
              (0x21...0x7E).contains(row), (0x21...0x7E).contains(cell) else { return nil }
        let index = Int(row - 0x21) * 94 + Int(cell - 0x21)
        guard index < table.count else { return nil }
        let value = table[index]
        return value == 0 ? nil : Unicode.Scalar(value)
    }

    // MARK: Encoding

    /// Encodes a scalar as one or two 7-bit bytes, or nil when the set does not
    /// contain it. G1 callers set the high bit. The codec decides whether a
    /// single-byte 5CH is a character or the value delimiter.
    func encode(_ scalar: Unicode.Scalar) -> [UInt8]? {
        let value = scalar.value
        switch self {
        case .ascii:
            guard (0x21...0x7E).contains(value) else { return nil }
            return [UInt8(value)]
        case .jisRomaji:
            switch value {
            case 0xA5: return [0x5C]
            case 0x203E: return [0x7E]
            case 0x5C, 0x7E: return nil
            case 0x21...0x7E: return [UInt8(value)]
            default: return nil
            }
        case .singleByte:
            guard let byte = DICOMCharacterSetTables.reverse(of: self)[value] else { return nil }
            return [UInt8(byte - 0x80)]
        case .jisX0208, .jisX0212, .ksX1001, .gb2312:
            guard let code = DICOMCharacterSetTables.reverse(of: self)[value] else { return nil }
            return [UInt8(code >> 8), UInt8(code & 0xFF)]
        }
    }

    // MARK: Tables

    fileprivate var singleByteTable: [UInt16]? {
        switch self {
        case .singleByte(13): return DICOMSingleByteTables.isoIR13
        case .singleByte(100): return DICOMSingleByteTables.isoIR100
        case .singleByte(101): return DICOMSingleByteTables.isoIR101
        case .singleByte(109): return DICOMSingleByteTables.isoIR109
        case .singleByte(110): return DICOMSingleByteTables.isoIR110
        case .singleByte(144): return DICOMSingleByteTables.isoIR144
        case .singleByte(127): return DICOMSingleByteTables.isoIR127
        case .singleByte(126): return DICOMSingleByteTables.isoIR126
        case .singleByte(138): return DICOMSingleByteTables.isoIR138
        case .singleByte(148): return DICOMSingleByteTables.isoIR148
        case .singleByte(203): return DICOMSingleByteTables.isoIR203
        case .singleByte(166): return DICOMSingleByteTables.isoIR166
        default: return nil
        }
    }

    fileprivate var multiByteTable: [UInt16]? {
        switch self {
        case .jisX0208: return DICOMCharacterSetTables.jisX0208
        case .jisX0212: return DICOMCharacterSetTables.jisX0212
        case .ksX1001: return DICOMCharacterSetTables.ksX1001
        case .gb2312: return DICOMCharacterSetTables.gb2312
        default: return nil
        }
    }
}

/// Lazily loaded mapping tables generated by
/// `Scripts/generate-character-set-tables.py` into `Resources/CharacterSets`.
enum DICOMCharacterSetTables {
    static let jisX0208 = load("jisx0208")
    static let jisX0212 = load("jisx0212")
    static let ksX1001 = load("ksx1001")
    static let gb2312 = load("gb2312")
    /// GB18030 two-byte codes: lead 81H-FEH by trail 40H-FEH (191 per lead).
    static let gb18030TwoByte = load("gb18030-2byte")
    /// GB18030 four-byte codes 81308130H-8431A439H by linear index.
    static let gb18030FourByteBMP = load("gb18030-4byte-bmp")

    /// Unicode scalar to code: the GR byte for single-byte sets, or the 7-bit
    /// row and cell (row << 8 | cell) for two-byte sets. The first code wins
    /// when several decode to the same scalar.
    static func reverse(of set: DICOMGraphicCharacterSet) -> [UInt32: UInt16] {
        switch set {
        case .jisX0208: return jisX0208Reverse
        case .jisX0212: return jisX0212Reverse
        case .ksX1001: return ksX1001Reverse
        case .gb2312: return gb2312Reverse
        case .singleByte:
            return singleByteReverse[set] ?? [:]
        case .ascii, .jisRomaji:
            return [:]
        }
    }

    private static let jisX0208Reverse = reverseTwoByte(jisX0208)
    private static let jisX0212Reverse = reverseTwoByte(jisX0212)
    private static let ksX1001Reverse = reverseTwoByte(ksX1001)
    private static let gb2312Reverse = reverseTwoByte(gb2312)

    private static let singleByteReverse: [DICOMGraphicCharacterSet: [UInt32: UInt16]] = {
        var result: [DICOMGraphicCharacterSet: [UInt32: UInt16]] = [:]
        for set in DICOMGraphicCharacterSet.all {
            guard let table = set.singleByteTable else { continue }
            var reverse: [UInt32: UInt16] = [:]
            for (offset, value) in table.enumerated() where value != 0 && reverse[UInt32(value)] == nil {
                reverse[UInt32(value)] = UInt16(0xA0 + offset)
            }
            result[set] = reverse
        }
        return result
    }()

    private static func reverseTwoByte(_ table: [UInt16]) -> [UInt32: UInt16] {
        var reverse: [UInt32: UInt16] = [:]
        reverse.reserveCapacity(table.count)
        for (index, value) in table.enumerated() where value != 0 && reverse[UInt32(value)] == nil {
            let (row, cell) = index.quotientAndRemainder(dividingBy: 94)
            reverse[UInt32(value)] = UInt16(0x21 + row) << 8 | UInt16(0x21 + cell)
        }
        return reverse
    }

    private static func load(_ name: String) -> [UInt16] {
        guard let url = Bundle.module.url(
            forResource: name, withExtension: "bin", subdirectory: "CharacterSets"
        ), let data = try? Data(contentsOf: url), data.count % 2 == 0 else {
            return []
        }
        let bytes = [UInt8](data)
        return (0..<bytes.count / 2).map { index in
            UInt16(bytes[index * 2]) | UInt16(bytes[index * 2 + 1]) << 8
        }
    }
}
