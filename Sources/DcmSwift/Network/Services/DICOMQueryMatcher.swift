import Foundation

/// Matches a C-FIND Identifier against an entity and builds the response
/// Identifier (PS3.4 C.2.2.2, C.2.2.3, K.2.2.1): Single Value, List of UID,
/// Universal, Wild Card, Range, and Sequence Matching, at any depth.
///
/// - Matching follows the meaning of dates and times: a DA, TM, or DT key
///   covers its whole precision (`2230` matches `223000` and `223059`), and
///   DT values are compared in UTC when they carry an offset. A single
///   value is matched as a range whose bounds are that value.
/// - Person names match without regard to case or accents; a key without a
///   component group delimiter `=` is matched against each group.
/// - DS and IS values match by their numeric value.
/// - A key with several values (other than UI) matches when any of them
///   does; a stored attribute with several values matches when any of its
///   values does, and all of them are returned.
/// - An entity whose attribute is absent or empty does not match a key that
///   is not universal.
/// - Specific Character Set and Timezone Offset From UTC are never matched;
///   the entity's values are returned when it has them.
public struct DICOMQueryMatcher: Sendable {
    /// Pairs of DA and TM attributes, as 8-digit tags, matched as one DT
    /// when both keys use the same form of Range Matching (C.2.2.2.5.4).
    /// The Modality Worklist requires it for Scheduled Procedure Step Start
    /// Date and Time.
    public var combinedDateTime: [(date: String, time: String)]
    /// Tags, as 8 hexadecimal digits, returned as given in the request and
    /// never matched, such as Query/Retrieve Level.
    public var echoed: Set<String>

    public init(combinedDateTime: [(date: String, time: String)] = [], echoed: Set<String> = []) {
        self.combinedDateTime = combinedDateTime
        self.echoed = echoed
    }

    /// The Modality Worklist matcher (PS3.4 K.6.1.2.2): Scheduled Procedure
    /// Step Start Date and Time are matched together.
    public static let modalityWorklist = DICOMQueryMatcher(combinedDateTime: [("00400002", "00400003")])

    static let specificCharacterSet = "00080005"
    static let timezoneOffset = "00080201"

    /// The response Identifier for `entity`, or nil when it does not match
    /// `identifier`.
    public func match(_ identifier: DataSet, against entity: DataSet) throws -> DataSet? {
        let options = DICOMJSON.EncodingOptions(numbersAsStrings: true)
        guard let response = match(
            try DICOMJSON.object(identifier, options: options), against: try DICOMJSON.object(entity, options: options),
            topLevel: true) else { return nil }
        return try DICOMJSON.dataSet(response)
    }

    /// Matching on DICOM JSON Model objects (PS3.18 F), whose IS and DS
    /// Values are strings.
    public func match(_ identifier: [String: Any], against entity: [String: Any]) -> [String: Any]? {
        match(identifier, against: entity, topLevel: true)
    }

    private func match(_ keys: [String: Any], against entity: [String: Any], topLevel: Bool) -> [String: Any]? {
        var response: [String: Any] = [:]
        var combined: Set<String> = []
        for pair in combinedDateTime {
            guard let date = keys[pair.date] as? [String: Any], let time = keys[pair.time] as? [String: Any],
                  let dateKey = Self.strings(date).first, let timeKey = Self.strings(time).first,
                  let range = Self.combinedRange(date: dateKey, time: timeKey) else { continue }
            let storedDate = Self.strings(entity[pair.date] as? [String: Any] ?? [:])
            let storedTime = Self.strings(entity[pair.time] as? [String: Any] ?? [:])
            guard let day = storedDate.first, !day.isEmpty else { return nil }
            let stored = DICOMDateTimeValue.dateTime(day + (storedTime.first ?? ""))
            guard let stored, range.contains(stored.lower) else { return nil }
            combined.formUnion([pair.date, pair.time])
        }
        for (tag, value) in keys {
            guard let key = value as? [String: Any] else { continue }
            if tag == Self.specificCharacterSet || tag == Self.timezoneOffset { continue }
            if echoed.contains(tag) {
                response[tag] = key
                continue
            }
            let stored = entity[tag] as? [String: Any]
            let vr = key["vr"] as? String ?? stored?["vr"] as? String ?? ""
            if vr == "SQ" {
                guard let sequence = matchSequence(key, stored) else { return nil }
                response[tag] = sequence
                continue
            }
            if !combined.contains(tag) {
                let values = Self.strings(key)
                if !Self.isUniversal(values) {
                    let candidates = Self.strings(stored ?? [:]).filter { !$0.isEmpty }
                    guard !candidates.isEmpty, Self.matches(candidates, keys: values, vr: vr) else { return nil }
                }
            }
            response[tag] = stored ?? ["vr": vr]
        }
        if topLevel || keys[Self.specificCharacterSet] != nil {
            for tag in [Self.specificCharacterSet, Self.timezoneOffset] where entity[tag] != nil {
                response[tag] = entity[tag]
            }
        }
        return response
    }

    /// Sequence Matching (C.2.2.2.6): the matching Items, reduced to the
    /// requested attributes, or the whole sequence when the key has no Item
    /// attribute.
    private func matchSequence(_ key: [String: Any], _ stored: [String: Any]?) -> [String: Any]? {
        let keyItems = key["Value"] as? [[String: Any]] ?? []
        guard let keyItem = keyItems.first, !keyItem.isEmpty else { return stored ?? ["vr": "SQ"] }
        let items = stored?["Value"] as? [[String: Any]] ?? []
        let matched = items.compactMap { match(keyItem, against: $0, topLevel: false) }
        if matched.isEmpty, Self.constrains(keyItem) { return nil }
        return matched.isEmpty ? ["vr": "SQ"] : ["vr": "SQ", "Value": matched]
    }

    /// Whether an Item holds a key that is not universal.
    static func constrains(_ item: [String: Any]) -> Bool {
        item.contains { tag, value in
            guard tag != specificCharacterSet, tag != timezoneOffset, let key = value as? [String: Any] else { return false }
            if key["vr"] as? String == "SQ" {
                return (key["Value"] as? [[String: Any]])?.first.map(constrains) ?? false
            }
            return !isUniversal(strings(key))
        }
    }

    /// The Values of a JSON attribute as strings; a PN as `A=I=P`.
    static func strings(_ attribute: [String: Any]) -> [String] {
        (attribute["Value"] as? [Any] ?? []).map { value in
            switch value {
            case let string as String: return string
            case let number as NSNumber: return number.stringValue
            case let name as [String: Any]:
                var groups = ["Alphabetic", "Ideographic", "Phonetic"].map { name[$0] as? String ?? "" }
                while groups.count > 1, groups.last == "" { groups.removeLast() }
                return groups.joined(separator: "=")
            default: return ""
            }
        }
    }

    static func isUniversal(_ values: [String]) -> Bool {
        values.allSatisfy { $0.isEmpty || $0 == "*" }
    }

    /// Whether any stored value matches any key value.
    static func matches(_ stored: [String], keys: [String], vr: String) -> Bool {
        keys.contains { key in stored.contains { matches($0, key: key, vr: vr) } }
    }

    /// Matching of one stored value against one key value.
    public static func matches(_ stored: String, key: String, vr: String) -> Bool {
        if key.isEmpty || key == "*" { return true }
        switch vr {
        case "DA", "TM", "DT":
            guard let range = DICOMDateTimeValue.range(key, vr: vr),
                  let value = DICOMDateTimeValue.parse(stored, vr: vr) else { return false }
            return range.contains(value.lower)
        case "PN":
            return matchesName(stored, key: key)
        case "IS", "DS":
            if let number = Double(stored.trimmingCharacters(in: .whitespaces)),
               let wanted = Double(key.trimmingCharacters(in: .whitespaces)) {
                return number == wanted
            }
            return stored.trimmingCharacters(in: .whitespaces) == key.trimmingCharacters(in: .whitespaces)
        case "AE", "CS", "LO", "LT", "SH", "ST", "UC", "UR", "UT":
            if key.contains("*") || key.contains("?") { return DICOMQueryMatching.wildcard(stored, pattern: key) }
            return stored == key
        default:
            return stored == key
        }
    }

    /// Person names, insensitive to case and accents, with wild cards; a
    /// key without `=` is tried on each component group.
    static func matchesName(_ stored: String, key: String) -> Bool {
        let fold = foldedName
        let pattern = fold(key)
        let candidates = key.contains("=")
            ? [stored] : stored.split(separator: "=", omittingEmptySubsequences: true).map(String.init)
        return candidates.contains { DICOMQueryMatching.wildcard(fold($0), pattern: pattern) }
    }

    /// A person name as matched: without case or accents, and without
    /// trailing empty components. Adapters index names in this form.
    public static func foldedName(_ name: String) -> String {
        var text = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        while text.hasSuffix("^") { text.removeLast() }
        return text
    }

    /// The DT range of a DA and a TM key that use the same form of Range
    /// Matching, or nil when they do not.
    static func combinedRange(date: String, time: String) -> ClosedRange<Int>? {
        guard date.contains("-"), time.contains("-") else { return nil }
        let dates = date.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let times = time.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard dates[0].isEmpty == times[0].isEmpty, dates[1].isEmpty == times[1].isEmpty else { return nil }
        let low = dates[0].isEmpty ? Int.min : DICOMDateTimeValue.dateTime(dates[0] + times[0])?.lower
        let high = dates[1].isEmpty ? Int.max : DICOMDateTimeValue.dateTime(dates[1] + times[1])?.upper
        guard let low, let high, low <= high else { return nil }
        return low...high
    }
}

/// A DA, TM, or DT value as the interval of moments its precision covers,
/// in microseconds (since midnight for TM, since 0001-01-01 UTC for DA and
/// DT).
struct DICOMDateTimeValue {
    let lower: Int
    let upper: Int

    /// A single value or a range (`a-b`, `-b`, `a-`) as the moments it
    /// covers, each bound covering its whole precision.
    static func range(_ key: String, vr: String) -> ClosedRange<Int>? {
        guard key.contains("-") else {
            return parse(key, vr: vr).map { $0.lower...$0.upper }
        }
        // A DT offset may be negative: the range separator is the "-" that
        // follows a complete value or starts the key.
        let parts = split(key, vr: vr)
        let low = parts.low.isEmpty ? Int.min : parse(parts.low, vr: vr)?.lower
        let high = parts.high.isEmpty ? Int.max : parse(parts.high, vr: vr)?.upper
        guard let low, let high, low <= high else { return nil }
        return low...high
    }

    /// The two bounds of a range.
    static func split(_ key: String, vr: String) -> (low: String, high: String) {
        let characters = Array(key)
        for index in characters.indices where characters[index] == "-" {
            let low = String(characters[..<index]), high = String(characters[(index + 1)...])
            if (low.isEmpty || parse(low, vr: vr) != nil) && (high.isEmpty || parse(high, vr: vr) != nil) {
                return (low, high)
            }
        }
        return (key, "")
    }

    static func parse(_ value: String, vr: String) -> DICOMDateTimeValue? {
        let value = value.trimmingCharacters(in: .whitespaces)
        switch vr {
        case "DA": return date(value)
        case "TM": return time(value)
        default: return dateTime(value)
        }
    }

    /// YYYYMMDD, or the retired YYYY.MM.DD (PS3.5 6.2 note).
    static func date(_ value: String) -> DICOMDateTimeValue? {
        let digits = value.count == 10 && value.filter({ $0 == "." }).count == 2
            ? value.replacingOccurrences(of: ".", with: "") : value
        guard digits.count == 8 else { return nil }
        return dateTime(digits)
    }

    /// HH[MM[SS[.F{1,6}]]], or the retired HH:MM:SS form.
    static func time(_ value: String) -> DICOMDateTimeValue? {
        let text = value.replacingOccurrences(of: ":", with: "")
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = String(parts[0])
        guard [2, 4, 6].contains(whole.count), whole.allSatisfy(\.isASCIIDigit) else { return nil }
        var fraction = parts.count > 1 ? String(parts[1]) : ""
        guard fraction.count <= 6, fraction.allSatisfy(\.isASCIIDigit), parts.count == 1 || whole.count == 6 else {
            return nil
        }
        let numbers = stride(from: 0, to: whole.count, by: 2).map {
            Int(whole.dropFirst($0).prefix(2))!
        }
        let hours = numbers[0], minutes = numbers.count > 1 ? numbers[1] : 0, seconds = numbers.count > 2 ? numbers[2] : 0
        guard hours < 24, minutes < 60, seconds < 61 else { return nil }
        let precision = fraction.count
        fraction += String(repeating: "0", count: 6 - precision)
        let lower = ((hours * 60 + minutes) * 60 + seconds) * 1_000_000 + Int(fraction)!
        let span: Int
        switch (numbers.count, precision) {
        case (1, _): span = 3_600_000_000
        case (2, _): span = 60_000_000
        default: span = Int(pow(10, Double(6 - precision)))
        }
        return DICOMDateTimeValue(lower: lower, upper: lower + span - 1)
    }

    /// YYYY[MM[DD[HH[MM[SS[.F{1,6}]]]]]][&ZZXX], in UTC when an offset is
    /// given.
    static func dateTime(_ value: String) -> DICOMDateTimeValue? {
        var text = value
        var offset = 0
        if let sign = text.lastIndex(where: { $0 == "+" || $0 == "-" }) {
            let zone = String(text[text.index(after: sign)...])
            guard zone.count == 4, zone.allSatisfy(\.isASCIIDigit) else { return nil }
            let minutes = Int(zone.prefix(2))! * 60 + Int(zone.suffix(2))!
            offset = (text[sign] == "-" ? -minutes : minutes) * 60_000_000
            text = String(text[..<sign])
        }
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = String(parts[0])
        guard [4, 6, 8, 10, 12, 14].contains(whole.count), whole.allSatisfy(\.isASCIIDigit) else { return nil }
        guard parts.count == 1 || whole.count == 14 else { return nil }
        let year = Int(whole.prefix(4))!
        let month = whole.count >= 6 ? Int(whole.dropFirst(4).prefix(2))! : 1
        let day = whole.count >= 8 ? Int(whole.dropFirst(6).prefix(2))! : 1
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let days = Self.days(year: year, month: month, day: day)
        var lower = days * 86_400_000_000
        var upper: Int
        switch whole.count {
        case 4: upper = Self.days(year: year + 1, month: 1, day: 1) * 86_400_000_000 - 1
        case 6:
            let next = month == 12 ? Self.days(year: year + 1, month: 1, day: 1) : Self.days(year: year, month: month + 1, day: 1)
            upper = next * 86_400_000_000 - 1
        case 8: upper = lower + 86_400_000_000 - 1
        default:
            let suffix = String(whole.dropFirst(8)) + (parts.count > 1 ? "." + parts[1] : "")
            guard let time = time(suffix) else { return nil }
            upper = lower + time.upper
            lower += time.lower
        }
        lower -= offset
        upper -= offset
        return DICOMDateTimeValue(lower: lower, upper: upper)
    }

    /// Days since 0001-01-01 in the proleptic Gregorian calendar.
    static func days(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468 + 719_162
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
