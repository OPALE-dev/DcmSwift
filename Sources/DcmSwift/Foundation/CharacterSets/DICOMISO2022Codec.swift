import Foundation

/// Where text delimiters occur in a value, which decides when the Value 1
/// character sets become active again (PS3.5 6.1.2.5.3).
struct DICOMTextContext: Equatable, Sendable {
    /// A single-byte 05/12 separates values (every VR except ST, LT and UT).
    var delimitsValues: Bool
    /// "^" and "=" separate Person Name components and groups.
    var isPersonName: Bool

    init(vr: VR.VR?) {
        switch vr {
        case .ST?, .LT?, .UT?:
            delimitsValues = false
        default:
            delimitsValues = true
        }
        isPersonName = vr == .PN
    }
}

/// ISO/IEC 2022 8-bit codec restricted as in PS3.5 6.1.2.5: G0 is invoked in
/// GL and G1 in GR, no locking or single shifts, and only the escape sequences
/// of PS3.3 Tables C.12-3 and C.12-4.
struct DICOMISO2022Codec: Equatable, Sendable {
    let initialG0: DICOMGraphicCharacterSet
    let initialG1: DICOMGraphicCharacterSet?
    /// Sets that may be designated by an escape sequence, in the order of the
    /// Specific Character Set Values. Empty when Code Extensions are not used.
    let extensions: [DICOMGraphicCharacterSet]

    var allowsCodeExtensions: Bool { !extensions.isEmpty }

    // MARK: Decoding

    func decode(_ bytes: [UInt8], context: DICOMTextContext) -> String? {
        var output = String.UnicodeScalarView()
        var g0 = initialG0
        var g1 = initialG1
        var index = 0

        func activateValue1() {
            g0 = initialG0
            g1 = initialG1
        }

        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case 0x1B:
                guard allowsCodeExtensions,
                      let (set, length) = Self.designation(in: bytes, at: index + 1) else {
                    return nil
                }
                if set.isG0 { g0 = set } else { g1 = set }
                index += 1 + length
                continue

            case 0x09, 0x0A, 0x0C, 0x0D:
                // Value 1 is active at the start of each line and page and
                // after any other Control Character.
                output.append(Unicode.Scalar(byte))
                activateValue1()

            case 0x00..<0x20, 0x7F:
                output.append(Unicode.Scalar(byte))

            case 0x20:
                output.append(" ")

            case 0x21..<0x7F:
                if g0.isMultiByte {
                    guard index + 1 < bytes.count,
                          let scalar = g0.decode(row: byte, cell: bytes[index + 1]) else {
                        return nil
                    }
                    output.append(scalar)
                    index += 2
                    continue
                }
                if byte == 0x5C && context.delimitsValues {
                    // Only a single-byte 05/12 separates values, whatever
                    // glyph the G0 set assigns to it.
                    output.append("\\")
                    activateValue1()
                } else {
                    guard let scalar = g0.decode(gl: byte) else { return nil }
                    output.append(scalar)
                    if context.isPersonName && (byte == 0x5E || byte == 0x3D) {
                        activateValue1()
                    }
                }

            case 0x80..<0xA0:
                // C1 Control Characters shall not be used.
                return nil

            default:
                guard let set = g1 else { return nil }
                if set.isMultiByte {
                    guard index + 1 < bytes.count, bytes[index + 1] >= 0xA1,
                          let scalar = set.decode(row: byte & 0x7F, cell: bytes[index + 1] & 0x7F) else {
                        return nil
                    }
                    output.append(scalar)
                    index += 2
                    continue
                }
                guard let scalar = set.decode(gr: byte) else { return nil }
                output.append(scalar)
            }
            index += 1
        }
        return String(output)
    }

    /// Recognizes the DICOM escape sequence following an ESC byte and returns
    /// the designated set and the sequence length (excluding ESC).
    private static func designation(
        in bytes: [UInt8], at start: Int
    ) -> (DICOMGraphicCharacterSet, Int)? {
        for set in DICOMGraphicCharacterSet.all {
            let sequence = set.escapeSequence
            guard start + sequence.count <= bytes.count,
                  bytes[start..<(start + sequence.count)].elementsEqual(sequence) else {
                continue
            }
            return (set, sequence.count)
        }
        return nil
    }

    // MARK: Encoding

    func encode(_ string: String, context: DICOMTextContext) -> [UInt8]? {
        var output: [UInt8] = []
        var g0 = initialG0
        var g1 = initialG1
        // A set designated in an earlier line, value, or Person Name component
        // must be designated again before its first use (PS3.5 6.1.2.5.3).
        var usableG1 = initialG1

        func designate(_ set: DICOMGraphicCharacterSet) {
            output.append(0x1B)
            output.append(contentsOf: set.escapeSequence)
            if set.isG0 {
                g0 = set
            } else {
                g1 = set
                usableG1 = set
            }
        }

        func activateValue1() {
            if g0 != initialG0 { designate(initialG0) }
            if let initialG1, g1 != initialG1 { designate(initialG1) }
            usableG1 = initialG1
        }

        func append(_ bytes: [UInt8], from set: DICOMGraphicCharacterSet) {
            output.append(contentsOf: set.isG0 ? bytes : bytes.map { $0 | 0x80 })
        }

        // A character that a single-byte G0 set encodes as 05/12 cannot
        // appear inside a value where 05/12 separates values (PS3.5 6.1.2.3).
        func encoded(_ scalar: Unicode.Scalar, in set: DICOMGraphicCharacterSet) -> [UInt8]? {
            guard let bytes = set.encode(scalar) else { return nil }
            if context.delimitsValues && set.isG0 && bytes == [0x5C] { return nil }
            return bytes
        }

        for scalar in string.unicodeScalars {
            let value = scalar.value
            let isValueDelimiter = value == 0x5C && context.delimitsValues
            let isNameDelimiter = context.isPersonName && (value == 0x5E || value == 0x3D)

            if isValueDelimiter || isNameDelimiter || [0x09, 0x0A, 0x0C, 0x0D].contains(value) {
                activateValue1()
                if isValueDelimiter {
                    output.append(0x5C)
                } else if isNameDelimiter {
                    guard let bytes = g0.encode(scalar) else { return nil }
                    output.append(contentsOf: bytes)
                } else {
                    output.append(UInt8(value))
                }
                continue
            }
            if value == 0x20 {
                output.append(0x20)
                continue
            }
            if value < 0x20 && value != 0x1B {
                output.append(UInt8(value))
                continue
            }

            if let bytes = encoded(scalar, in: g0) {
                append(bytes, from: g0)
            } else if let set = usableG1, let bytes = encoded(scalar, in: set) {
                append(bytes, from: set)
            } else if let (set, bytes) = extensions.lazy
                        .compactMap({ set in encoded(scalar, in: set).map { (set, $0) } })
                        .first {
                // Sets are tried in the order of the Specific Character Set
                // Values, so Value 1 is preferred.
                designate(set)
                append(bytes, from: set)
            } else {
                return nil
            }
        }
        activateValue1()
        return output
    }
}
