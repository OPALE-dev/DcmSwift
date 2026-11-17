import Foundation

/// An attribute a DIMSE-N request must carry, as the attribute tables of
/// PS3.4 give them: present (Type 2) or with a value (Type 1), optionally
/// limited to enumerated values, with the requirements of its Items.
/// Conditional types are not checked.
struct DICOMAttributeRequirement {
    let keyword: String
    var type: Character
    var items: [DICOMAttributeRequirement] = []
    /// Enumerated values, when the attribute has any.
    var values: Set<String>? = nil

    /// The tag of a keyword, as 8 upper-case hexadecimal digits.
    static func tag(_ keyword: String) -> String {
        DicomSpec.shared.dataTag(forName: keyword)!.code.uppercased()
    }

    static func failure(_ status: DICOMStatus, _ comment: String, _ keywords: [String]) -> DICOMNormalizedResponse {
        DICOMNormalizedResponse(status: status, errorComment: comment,
                                attributes: keywords.compactMap { UInt32(tag($0), radix: 16) })
    }

    /// The failure for the first unmet requirement of a DICOM JSON object:
    /// 0120H for a missing attribute, 0121H for a missing value, 0106H for a
    /// value outside the enumerated ones. With `presentOnly`, the top-level
    /// requirements apply only to the attributes present.
    static func check(
        _ object: [String: Any], _ rules: [DICOMAttributeRequirement], presentOnly: Bool = false
    ) -> DICOMNormalizedResponse? {
        for rule in rules {
            guard let attribute = object[tag(rule.keyword)] as? [String: Any] else {
                if presentOnly || rule.type == "3" { continue }
                return failure(.missingAttribute, "\(rule.keyword) is missing", [rule.keyword])
            }
            let values = attribute["Value"] as? [Any] ?? []
            let empty = values.isEmpty || values.allSatisfy { $0 is NSNull || ($0 as? String)?.isEmpty == true }
            if rule.type == "1", empty {
                return failure(.missingAttributeValue, "\(rule.keyword) has no value", [rule.keyword])
            }
            if let allowed = rule.values, let invalid = values.compactMap({ $0 as? String }).first(where: { !allowed.contains($0) }) {
                return failure(.invalidAttributeValue, "\(rule.keyword) cannot be \(invalid)", [rule.keyword])
            }
            for item in values.compactMap({ $0 as? [String: Any] }) where !rule.items.isEmpty {
                if let failure = check(item, rule.items) { return failure }
            }
        }
        return nil
    }
}
