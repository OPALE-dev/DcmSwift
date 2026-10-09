import Foundation

/// The matching conditions of a C-FIND Identifier, independent of any
/// storage, for archive adapters to translate (PS3.4 C.2.2.2).
///
/// An adapter translates the conditions it can, such as SQL `WHERE`
/// clauses, and returns every document that might match; the core then
/// filters them with `DICOMQueryMatcher`. A translation that drops a
/// condition, or is looser than it, therefore still gives exact results;
/// it must never be stricter.
///
/// Universal keys (empty or `*`) give no condition. Values are normalized
/// as `DICOMQueryMatcher` compares them: `normalizedRange(_:vr:)` gives the
/// moments a stored date or time covers, `DICOMQueryMatcher.foldedName(_:)`
/// the form in which names are compared.
public struct DICOMQuery: Sendable, Equatable {
    public enum Constraint: Sendable, Equatable {
        /// Equal to one of the values: List of UID Matching, Single Value
        /// Matching, or a key with several values.
        case equals([String])
        /// Wild Card Matching, case-sensitive: `*` any sequence, `?` any
        /// character.
        case wildcard(String)
        /// A person name pattern, folded with `DICOMQueryMatcher.foldedName`,
        /// possibly with wild cards; it is matched against each component
        /// group of the stored name, or against the whole name when the
        /// pattern contains `=`.
        case personName(String)
        /// A DS or IS value, compared numerically.
        case number(Double)
        /// Dates and times whose normalized lower bound falls in this range,
        /// in microseconds (since 0001-01-01 UTC for DA and DT, since
        /// midnight for TM).
        case range(ClosedRange<Int>)
        /// A DA attribute and its TM sibling (`timeTag`) matched together
        /// as one DT, in microseconds since 0001-01-01.
        case dateTime(timeTag: String, ClosedRange<Int>)
    }

    public struct Condition: Sendable, Equatable {
        /// Tags as 8 upper-case hexadecimal digits: the sequences that lead
        /// to the attribute, then the attribute. Conditions under the same
        /// sequence apply to the same Item.
        public var path: [String]
        public var vr: String
        public var constraint: Constraint
    }

    public var conditions: [Condition]

    public init(conditions: [Condition]) {
        self.conditions = conditions
    }

    /// The conditions of an Identifier, as `matcher` applies them.
    public init(identifier: DataSet, matcher: DICOMQueryMatcher = DICOMQueryMatcher()) throws {
        let object = try DICOMJSON.object(identifier, options: DICOMJSON.EncodingOptions(numbersAsStrings: true))
        self.init(identifier: object, matcher: matcher)
    }

    /// The conditions of an Identifier in the DICOM JSON Model.
    public init(identifier: [String: Any], matcher: DICOMQueryMatcher = DICOMQueryMatcher()) {
        conditions = Self.conditions(identifier, path: [], matcher: matcher)
    }

    /// The moments a stored DA, TM, or DT value covers, in microseconds, or
    /// nil when it cannot be read.
    public static func normalizedRange(_ value: String, vr: String) -> ClosedRange<Int>? {
        DICOMDateTimeValue.parse(value, vr: vr).map { $0.lower...$0.upper }
    }

    static func conditions(_ keys: [String: Any], path: [String], matcher: DICOMQueryMatcher) -> [Condition] {
        var conditions: [Condition] = []
        var combined: Set<String> = []
        for pair in matcher.combinedDateTime {
            guard let date = keys[pair.date] as? [String: Any], let time = keys[pair.time] as? [String: Any],
                  let dateKey = DICOMQueryMatcher.strings(date).first,
                  let timeKey = DICOMQueryMatcher.strings(time).first,
                  let range = DICOMQueryMatcher.combinedRange(date: dateKey, time: timeKey) else { continue }
            conditions.append(Condition(path: path + [pair.date], vr: "DA", constraint: .dateTime(timeTag: pair.time, range)))
            combined.formUnion([pair.date, pair.time])
        }
        for tag in keys.keys.sorted() {
            guard let key = keys[tag] as? [String: Any], !combined.contains(tag), !matcher.echoed.contains(tag),
                  tag != DICOMQueryMatcher.specificCharacterSet, tag != DICOMQueryMatcher.timezoneOffset else { continue }
            let vr = key["vr"] as? String ?? ""
            if vr == "SQ" {
                if let item = (key["Value"] as? [[String: Any]])?.first {
                    conditions += Self.conditions(item, path: path + [tag], matcher: matcher)
                }
                continue
            }
            let values = DICOMQueryMatcher.strings(key)
            guard !DICOMQueryMatcher.isUniversal(values) else { continue }
            if let constraint = constraint(values, vr: vr) {
                conditions.append(Condition(path: path + [tag], vr: vr, constraint: constraint))
            }
        }
        return conditions
    }

    /// The constraint of a key, or nil when it cannot be expressed (the
    /// core still applies it).
    static func constraint(_ values: [String], vr: String) -> Constraint? {
        guard values.count == 1 || vr == "UI" else {
            // Several values match when any does: only exact values combine.
            let plain = values.allSatisfy { !$0.contains("*") && !$0.contains("?") && !$0.contains("-") }
            return plain && !["PN", "DA", "TM", "DT", "DS", "IS"].contains(vr) ? .equals(values) : nil
        }
        let key = values[0]
        switch vr {
        case "UI": return .equals(values)
        case "DA", "TM", "DT": return DICOMDateTimeValue.range(key, vr: vr).map(Constraint.range)
        case "PN": return .personName(DICOMQueryMatcher.foldedName(key))
        case "DS", "IS": return Double(key.trimmingCharacters(in: .whitespaces)).map(Constraint.number)
        case "AE", "CS", "LO", "LT", "SH", "ST", "UC", "UR", "UT":
            return key.contains("*") || key.contains("?") ? .wildcard(key) : .equals([key])
        default: return .equals([key])
        }
    }
}
