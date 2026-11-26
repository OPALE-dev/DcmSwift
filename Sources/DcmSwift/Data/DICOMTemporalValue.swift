import Foundation

/// A DA, TM or DT Value read as written (PS3.5 6.2, Table 6.2-1): only the
/// components present, the fraction of a second as its digits, and for DT
/// the offset from UTC when one is given. No time zone is implied.
public struct DICOMDateTime: Hashable, Sendable, CustomStringConvertible {
    public var year: Int?
    public var month: Int?
    public var day: Int?
    public var hour: Int?
    public var minute: Int?
    public var second: Int?
    /// The fraction of a second, as written: `"123"` for `.123`.
    public var fraction: String?
    /// The offset from UTC in minutes (DT `&ZZXX`), nil when absent.
    public var utcOffset: Int?
    /// Written in a retired ACR-NEMA form: `1990.01.31` for DA,
    /// `12:30:00` for TM. Reading accepts it, a writer should not.
    public var isACRNEMA = false

    public init(year: Int? = nil, month: Int? = nil, day: Int? = nil, hour: Int? = nil, minute: Int? = nil,
                second: Int? = nil, fraction: String? = nil, utcOffset: Int? = nil) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.fraction = fraction
        self.utcOffset = utcOffset
    }

    /// A DA Value: `YYYYMMDD`, or `YYYY.MM.DD` from ACR-NEMA.
    public init?(date text: String) {
        var digits = text
        if text.count == 10, text.dropFirst(4).first == ".", text.dropFirst(7).first == "." {
            digits = text.replacingOccurrences(of: ".", with: "")
            isACRNEMA = true
        }
        guard digits.count == 8, let parts = Self.numbers(digits, [4, 2, 2]) else { return nil }
        (year, month, day) = (parts[0], parts[1], parts[2])
        guard isValidDate else { return nil }
    }

    /// A TM Value: `HH[MM[SS[.F{1,6}]]]`, or `HH:MM[:SS[.F]]` from ACR-NEMA.
    public init?(time text: String) {
        var text = text
        if text.contains(":") {
            text = text.replacingOccurrences(of: ":", with: "")
            isACRNEMA = true
        }
        let pieces = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let clock = String(pieces[0])
        guard [2, 4, 6].contains(clock.count),
              let parts = Self.numbers(clock, Array(repeating: 2, count: clock.count / 2)) else { return nil }
        hour = parts[0]
        minute = parts.count > 1 ? parts[1] : nil
        second = parts.count > 2 ? parts[2] : nil
        if pieces.count == 2 {
            guard clock.count == 6, let fraction = Self.fraction(pieces[1]) else { return nil }
            self.fraction = fraction
        }
        guard isValidTime else { return nil }
    }

    /// A DT Value: `YYYY[MM[DD[HH[MM[SS[.F{1,6}]]]]]][&ZZXX]`.
    public init?(dateTime text: String) {
        var body = Substring(text)
        if let sign = body.lastIndex(where: { $0 == "+" || $0 == "-" }) {
            let zone = String(body[body.index(after: sign)...])
            guard zone.count == 4, let parts = Self.numbers(zone, [2, 2]), parts[0] <= 14, parts[1] <= 59 else { return nil }
            utcOffset = (parts[0] * 60 + parts[1]) * (body[sign] == "-" ? -1 : 1)
            body = body[..<sign]
        }
        let pieces = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let digits = String(pieces[0])
        guard [4, 6, 8, 10, 12, 14].contains(digits.count),
              let parts = Self.numbers(digits, [4] + Array(repeating: 2, count: (digits.count - 4) / 2)) else { return nil }
        func part(_ index: Int) -> Int? { parts.count > index ? parts[index] : nil }
        (year, month, day, hour, minute, second) = (parts[0], part(1), part(2), part(3), part(4), part(5))
        if pieces.count == 2 {
            guard digits.count == 14, let fraction = Self.fraction(pieces[1]) else { return nil }
            self.fraction = fraction
        }
        guard isValidDate, isValidTime else { return nil }
    }

    /// The components present, with the time zone only when the Value gives
    /// an offset from UTC.
    public var dateComponents: DateComponents {
        var components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        if let fraction { components.nanosecond = Int((fraction + String(repeating: "0", count: 9 - fraction.count)).prefix(9)) }
        if let utcOffset { components.timeZone = TimeZone(secondsFromGMT: utcOffset * 60) }
        return components
    }

    /// The Value as DICOM writes it for DA, TM or DT, in the current form.
    public func rawValue(for vr: VR.VR) -> String {
        func two(_ value: Int?) -> String { value.map { String(format: "%02d", $0) } ?? "" }
        let year = self.year.map { String(format: "%04d", $0) } ?? ""
        let clock = two(hour) + two(minute) + two(second) + (fraction.map { "." + $0 } ?? "")
        switch vr {
        case .DA: return year + two(month) + two(day)
        case .TM: return clock
        default:
            let zone = utcOffset.map { String(format: "%@%02d%02d", $0 < 0 ? "-" : "+", abs($0) / 60, abs($0) % 60) } ?? ""
            return year + two(month) + two(day) + clock + zone
        }
    }

    public var description: String {
        rawValue(for: hour == nil ? .DA : year == nil ? .TM : .DT)
    }

    private var isValidDate: Bool {
        guard (1...12).contains(month ?? 1), (1...31).contains(day ?? 1) else { return false }
        guard let year, let month, let day else { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
            .map { calendar.component(.day, from: $0) == day } ?? false
    }

    private var isValidTime: Bool {
        (hour ?? 0) <= 23 && (minute ?? 0) <= 59 && (second ?? 0) <= 60
    }

    private static func fraction(_ text: Substring) -> String? {
        (1...6).contains(text.count) && text.allSatisfy(\.isASCIIDigit) ? String(text) : nil
    }

    private static func numbers(_ digits: String, _ widths: [Int]) -> [Int]? {
        guard digits.allSatisfy(\.isASCIIDigit) else { return nil }
        var result: [Int] = []
        var index = digits.startIndex
        for width in widths {
            guard let end = digits.index(index, offsetBy: width, limitedBy: digits.endIndex),
                  let number = Int(digits[index..<end]) else { return nil }
            result.append(number)
            index = end
        }
        return index == digits.endIndex ? result : nil
    }
}

/// A DA, TM or DT Value: one point, or a range as matching keys write it
/// (PS3.4 C.2.2.2.5), open at either end.
public enum DICOMTemporalValue: Hashable, Sendable {
    case single(DICOMDateTime)
    case range(from: DICOMDateTime?, to: DICOMDateTime?)

    /// Reads a Value of the VR, a range when it contains a `-` that is not
    /// a DT offset from UTC.
    public init?(_ text: String, vr: VR.VR) {
        let read: (String) -> DICOMDateTime? = switch vr {
        case .DA: { DICOMDateTime(date: $0) }
        case .TM: { DICOMDateTime(time: $0) }
        case .DT: { DICOMDateTime(dateTime: $0) }
        default: { _ in nil }
        }
        if let value = read(text) {
            self = .single(value)
            return
        }
        // A range: the first `-` whose two sides read, either may be empty.
        for index in text.indices where text[index] == "-" {
            let start = String(text[..<index]), end = String(text[text.index(after: index)...])
            guard !(start.isEmpty && end.isEmpty) else { continue }
            let from = start.isEmpty ? nil : read(start), to = end.isEmpty ? nil : read(end)
            if (start.isEmpty || from != nil) && (end.isEmpty || to != nil) {
                self = .range(from: from, to: to)
                return
            }
        }
        return nil
    }
}

/// An AS Value: `nnnD`, `nnnW`, `nnnM` or `nnnY` (PS3.5 Table 6.2-1).
public struct DICOMAge: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public enum Unit: Character, Sendable {
        case days = "D", weeks = "W", months = "M", years = "Y"
    }

    public var count: Int
    public var unit: Unit

    public init?(count: Int, unit: Unit) {
        guard (0...999).contains(count) else { return nil }
        self.count = count
        self.unit = unit
    }

    public init?(rawValue: String) {
        guard rawValue.count == 4, let last = rawValue.last, let unit = Unit(rawValue: last),
              rawValue.prefix(3).allSatisfy(\.isASCIIDigit), let count = Int(rawValue.prefix(3)) else { return nil }
        self.init(count: count, unit: unit)
    }

    public var rawValue: String { String(format: "%03d", count) + String(unit.rawValue) }
    public var description: String { rawValue }

    /// The age as calendar components, without a date of reference.
    public var dateComponents: DateComponents {
        switch unit {
        case .days: DateComponents(day: count)
        case .weeks: DateComponents(weekOfMonth: count)
        case .months: DateComponents(month: count)
        case .years: DateComponents(year: count)
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
