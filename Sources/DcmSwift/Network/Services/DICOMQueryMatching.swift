/// Attribute matching of C-FIND keys (PS3.4 C.2.2.2), on string values as
/// encoded (multiple values joined by backslashes).
public enum DICOMQueryMatching {
    /// Whether a stored value matches a key: universal matching (empty or
    /// `*`), single value, wildcard (`*`, `?`), list of UID, and range
    /// matching for dates and times. Person names match without regard to
    /// case, as PS3.4 C.2.2.2.1 allows.
    public static func matches(_ stored: String, key: String, keyword: String) -> Bool {
        if key.isEmpty || key == "*" { return true }
        let vr = DicomSpec.shared.dataTag(forName: keyword).flatMap { DicomSpec.shared.vrForTag(withCode: $0.code) }
        switch vr {
        case .UI?:
            return key.split(separator: "\\").contains { $0 == stored }
        case .DA?, .TM?, .DT?:
            guard key.contains("-") else { return stored == key }
            let bounds = key.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            let low = String(bounds[0]), high = bounds.count > 1 ? String(bounds[1]) : ""
            guard !stored.isEmpty else { return false }
            // A bound covers its whole precision: 20240131 includes any
            // time of that day in a DT range.
            return (low.isEmpty || stored >= low) && (high.isEmpty || stored.prefix(high.count) <= high)
        case .PN?:
            return wildcard(stored.uppercased(), pattern: key.uppercased())
        default:
            return key.contains("*") || key.contains("?") ? wildcard(stored, pattern: key) : stored == key
        }
    }

    /// `*` matches any sequence of characters, `?` any single one.
    public static func wildcard(_ value: String, pattern: String) -> Bool {
        let value = Array(value), pattern = Array(pattern)
        var v = 0, p = 0, star = -1, mark = 0
        while v < value.count {
            if p < pattern.count, pattern[p] == "?" || pattern[p] == value[v] {
                v += 1
                p += 1
            } else if p < pattern.count, pattern[p] == "*" {
                star = p
                mark = v
                p += 1
            } else if star >= 0 {
                p = star + 1
                mark += 1
                v = mark
            } else {
                return false
            }
        }
        while p < pattern.count, pattern[p] == "*" { p += 1 }
        return p == pattern.count
    }
}
