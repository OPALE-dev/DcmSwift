import Foundation

/// Lexical rules of the character-string Value Representations (PS3.5
/// Table 6.2-1): repertoire, format, and length of each Value. Dictionary
/// and IOD rules are separate.
public enum DICOMValueValidation {
    /// Why a Value does not conform to its VR, or nil when it does. `value`
    /// is one decoded Value, without the delimiter; padding allowed by the
    /// VR is accepted.
    public static func problem(with value: String, vr: VR.VR) -> String? {
        diagnostic(with: value, vr: vr)?.description
    }

    /// Why a Value does not conform to its VR, to translate; nil when it does.
    public static func diagnostic(with value: String, vr: VR.VR) -> DICOMDiagnostic? {
        if value.isEmpty { return nil }
        let bytes = Array(value.utf8)
        let characters = value.count
        func outside(_ allowed: (UInt8) -> Bool) -> Bool { !bytes.allSatisfy(allowed) }
        func digits(_ text: Substring) -> Bool { !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber } }
        let trailingTrimmed = String(value.reversed().drop { $0 == " " }.reversed())
        let trimmed = trailingTrimmed.drop { $0 == " " }

        switch vr {
        case .AE:
            if bytes.count > 16 { return DICOMDiagnostic(.longerThanBytes, "16") }
            if outside({ $0 >= 0x20 && $0 < 0x7F && $0 != 0x5C }) { return DICOMDiagnostic(.outsideDefaultRepertoire) }
            if trimmed.isEmpty { return DICOMDiagnostic(.onlySpaces) }
        case .AS:
            guard bytes.count == 4, digits(Substring(value.prefix(3))), "DWMY".contains(value.last!) else {
                return DICOMDiagnostic(.notAge)
            }
        case .CS:
            if bytes.count > 16 { return DICOMDiagnostic(.longerThanBytes, "16") }
            if outside({ (0x41...0x5A).contains($0) || (0x30...0x39).contains($0) || $0 == 0x20 || $0 == 0x5F }) {
                return DICOMDiagnostic(.notCodeString)
            }
        case .DA:
            if value.count == 10, value.dropFirst(4).first == ".", value.dropFirst(7).first == "." {
                return DICOMDiagnostic(.acrNemaDate)
            }
            guard trailingTrimmed.count == 8, digits(Substring(trailingTrimmed)), isDate(trailingTrimmed) else {
                return DICOMDiagnostic(.notDate)
            }
        case .DS:
            if bytes.count > 16 { return DICOMDiagnostic(.longerThanBytes, "16") }
            guard isDecimal(trimmed) else { return DICOMDiagnostic(.notDecimal) }
        case .DT:
            if bytes.count > 26 { return DICOMDiagnostic(.longerThanBytes, "26") }
            guard isDateTime(trailingTrimmed) else { return DICOMDiagnostic(.notDateTime) }
        case .IS:
            if bytes.count > 12 { return DICOMDiagnostic(.longerThanBytes, "12") }
            guard let number = Int64(trimmed.hasPrefix("+") ? trimmed.dropFirst() : trimmed),
                  !trimmed.contains(" "), (-2_147_483_648...2_147_483_647).contains(number) else {
                return DICOMDiagnostic(.notInteger)
            }
        case .TM:
            if trailingTrimmed.contains(":") { return DICOMDiagnostic(.acrNemaTime) }
            if trailingTrimmed.utf8.count > 14 { return DICOMDiagnostic(.longerThanBytes, "14") }
            guard isTime(trailingTrimmed) else { return DICOMDiagnostic(.notTime) }
        case .UI:
            if bytes.count > 64 { return DICOMDiagnostic(.longerThanBytes, "64") }
            // PS3.5 9.1: digits in dot-separated components, without a
            // leading zero unless the component is "0".
            let components = value.split(separator: ".", omittingEmptySubsequences: false)
            guard DICOMUniqueIdentifier.isValid(value),
                  components.allSatisfy({ !$0.isEmpty && ($0 == "0" || $0.first != "0") }) else {
                return DICOMDiagnostic(.notUID)
            }
        case .UR:
            if value.first == " " { return DICOMDiagnostic(.leadingSpace) }
            if trailingTrimmed.contains(" ") || outside({ $0 >= 0x20 && $0 < 0x7F }) {
                return DICOMDiagnostic(.notURI)
            }
        case .SH, .LO, .UC:
            let limit = vr == .SH ? 16 : vr == .LO ? 64 : Int.max
            if characters > limit { return DICOMDiagnostic(.longerThanCharacters, "\(limit)") }
            if value.unicodeScalars.contains(where: { $0.value < 0x20 && $0 != "\u{1B}" || $0 == "\\" }) {
                return DICOMDiagnostic(.controlOrBackslash)
            }
        case .ST, .LT, .UT:
            let limit = vr == .ST ? 1024 : vr == .LT ? 10240 : Int.max
            if characters > limit { return DICOMDiagnostic(.longerThanCharacters, "\(limit)") }
            if value.unicodeScalars.contains(where: {
                $0.value < 0x20 && !["\t", "\n", "\u{0C}", "\r", "\u{1B}"].contains($0)
            }) {
                return DICOMDiagnostic(.controlCharacter)
            }
        case .PN:
            let groups = value.split(separator: "=", omittingEmptySubsequences: false)
            if groups.count > 3 { return DICOMDiagnostic(.tooManyComponentGroups) }
            for group in groups {
                if group.count > 64 { return DICOMDiagnostic(.longComponentGroup) }
                if group.filter({ $0 == "^" }).count > 4 { return DICOMDiagnostic(.tooManyComponents) }
            }
            if value.unicodeScalars.contains(where: { $0.value < 0x20 && $0 != "\u{1B}" || $0 == "\\" }) {
                return DICOMDiagnostic(.controlOrBackslash)
            }
        default:
            break
        }
        return nil
    }

    private static func isDate(_ text: String) -> Bool {
        let digits = text.compactMap(\.wholeNumberValue)
        guard digits.count == 8 else { return false }
        let year = digits[0...3].reduce(0) { $0 * 10 + $1 }
        let month = digits[4] * 10 + digits[5], day = digits[6] * 10 + digits[7]
        guard (1...12).contains(month), day >= 1 else { return false }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
        return day <= days
    }

    /// HH, HHMM, HHMMSS, or HHMMSS.F to HHMMSS.FFFFFF.
    private static func isTime(_ text: String) -> Bool {
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let main = parts[0]
        guard [2, 4, 6].contains(main.count), main.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        let values = stride(from: 0, to: main.count, by: 2).map {
            Int(main.dropFirst($0).prefix(2))!
        }
        let limits = [23, 59, 60]
        guard zip(values, limits).allSatisfy({ $0 <= $1 }) else { return false }
        if parts.count == 2 {
            guard main.count == 6, (1...6).contains(parts[1].count),
                  parts[1].allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        }
        return true
    }

    private static func isDateTime(_ text: String) -> Bool {
        var body = Substring(text)
        // &ZZXX, -1200 to +1400.
        if let sign = body.lastIndex(where: { $0 == "+" || $0 == "-" }) {
            let offset = body[body.index(after: sign)...]
            guard offset.count == 4, offset.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
            let minutes = Int(offset.prefix(2))! * 60 + Int(offset.suffix(2))!
            if Int(offset.suffix(2))! > 59 { return false }
            if body[sign] == "-" ? minutes > 12 * 60 : minutes > 14 * 60 { return false }
            if body[sign] == "-", minutes == 0 { return false }
            body = body[..<sign]
        }
        let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let main = parts[0]
        guard [4, 6, 8, 10, 12, 14].contains(main.count), main.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return false
        }
        if main.count >= 6 {
            let month = Int(main.dropFirst(4).prefix(2))!
            guard (1...12).contains(month) else { return false }
        }
        if main.count >= 8, !isDate(String(main.prefix(8))) { return false }
        if main.count > 8, !isTime(String(main.dropFirst(8))) { return false }
        if parts.count == 2 {
            guard main.count == 14, (1...6).contains(parts[1].count),
                  parts[1].allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        }
        return true
    }

    /// Fixed point or ANSI X3.9 floating point, without embedded spaces.
    private static func isDecimal(_ text: Substring) -> Bool {
        var rest = text[...]
        if rest.first == "+" || rest.first == "-" { rest = rest.dropFirst() }
        var mantissa = rest, exponent: Substring?
        if let e = rest.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantissa = rest[..<e]
            exponent = rest[rest.index(after: e)...]
        }
        let pieces = mantissa.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard pieces.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              pieces.contains(where: { !$0.isEmpty }) else { return false }
        if var exponent {
            if exponent.first == "+" || exponent.first == "-" { exponent = exponent.dropFirst() }
            guard !exponent.isEmpty, exponent.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        }
        return true
    }
}
