import Foundation

/// GB18030-2022 codec. GBK is its one- and two-byte subset with the same
/// encoding rules (PS3.3 C.12.1.1.2). Neither permits Code Extensions.
struct DICOMGB18030Codec: Equatable, Sendable {
    /// False for GBK, which has no four-byte sequences.
    let allowsFourByteSequences: Bool

    // MARK: Decoding

    func decode(_ bytes: [UInt8]) -> String? {
        var output = String.UnicodeScalarView()
        var index = 0
        while index < bytes.count {
            let lead = bytes[index]
            if lead < 0x80 {
                output.append(Unicode.Scalar(lead))
                index += 1
                continue
            }
            guard lead != 0x80, lead != 0xFF, index + 1 < bytes.count else { return nil }
            let second = bytes[index + 1]

            if (0x40...0xFE).contains(second) && second != 0x7F {
                let offset = Int(lead - 0x81) * 191 + Int(second - 0x40)
                guard let scalar = Self.scalar(in: DICOMCharacterSetTables.gb18030TwoByte, at: offset) else {
                    return nil
                }
                output.append(scalar)
                index += 2
                continue
            }

            guard allowsFourByteSequences, (0x30...0x39).contains(second), index + 3 < bytes.count,
                  (0x81...0xFE).contains(bytes[index + 2]), (0x30...0x39).contains(bytes[index + 3]) else {
                return nil
            }
            let linear = ((Int(lead - 0x81) * 10 + Int(second - 0x30)) * 126
                + Int(bytes[index + 2] - 0x81)) * 10 + Int(bytes[index + 3] - 0x30)
            let scalar: Unicode.Scalar?
            if linear < DICOMCharacterSetTables.gb18030FourByteBMP.count {
                scalar = Self.scalar(in: DICOMCharacterSetTables.gb18030FourByteBMP, at: linear)
            } else if lead >= 0x90 {
                // Supplementary planes are linear from 90308130H (U+10000).
                scalar = Unicode.Scalar(UInt32(0x10000 + linear - Self.firstSupplementaryLinear))
            } else {
                scalar = nil
            }
            guard let scalar, scalar.value <= 0x10FFFF else { return nil }
            output.append(scalar)
            index += 4
        }
        return String(output)
    }

    /// Linear four-byte index of 90308130H.
    private static let firstSupplementaryLinear = (0x90 - 0x81) * 12600

    private static func scalar(in table: [UInt16], at index: Int) -> Unicode.Scalar? {
        guard index < table.count, table[index] != 0 else { return nil }
        return Unicode.Scalar(table[index])
    }

    // MARK: Encoding

    func encode(_ string: String) -> [UInt8]? {
        var output: [UInt8] = []
        output.reserveCapacity(string.utf8.count)
        for scalar in string.unicodeScalars {
            let value = scalar.value
            if value < 0x80 {
                output.append(UInt8(value))
            } else if let code = Self.twoByteCodes[value] {
                output.append(UInt8(code >> 8))
                output.append(UInt8(code & 0xFF))
            } else if !allowsFourByteSequences {
                return nil
            } else if let linear = Self.fourByteBMPIndices[value] {
                output.append(contentsOf: Self.fourBytes(linear: Int(linear)))
            } else if value >= 0x10000 {
                output.append(contentsOf: Self.fourBytes(
                    linear: Self.firstSupplementaryLinear + Int(value - 0x10000)
                ))
            } else {
                return nil
            }
        }
        return output
    }

    private static func fourBytes(linear: Int) -> [UInt8] {
        let (b1, rest1) = linear.quotientAndRemainder(dividingBy: 12600)
        let (b2, rest2) = rest1.quotientAndRemainder(dividingBy: 1260)
        let (b3, b4) = rest2.quotientAndRemainder(dividingBy: 10)
        return [UInt8(0x81 + b1), UInt8(0x30 + b2), UInt8(0x81 + b3), UInt8(0x30 + b4)]
    }

    /// Two-byte codes take precedence: GB18030-2022 moved 18 characters from
    /// four-byte to two-byte codes and both still decode to them.
    private static let twoByteCodes: [UInt32: UInt16] = {
        var codes: [UInt32: UInt16] = [:]
        for (offset, value) in DICOMCharacterSetTables.gb18030TwoByte.enumerated()
        where value != 0 && codes[UInt32(value)] == nil {
            let (lead, trail) = offset.quotientAndRemainder(dividingBy: 191)
            codes[UInt32(value)] = UInt16(0x81 + lead) << 8 | UInt16(0x40 + trail)
        }
        return codes
    }()

    private static let fourByteBMPIndices: [UInt32: UInt32] = {
        var indices: [UInt32: UInt32] = [:]
        for (linear, value) in DICOMCharacterSetTables.gb18030FourByteBMP.enumerated()
        where value != 0 && indices[UInt32(value)] == nil && twoByteCodes[UInt32(value)] == nil {
            indices[UInt32(value)] = UInt32(linear)
        }
        return indices
    }()
}
