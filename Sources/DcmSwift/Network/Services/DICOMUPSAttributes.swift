import Foundation

extension DICOMUnifiedProcedureStepService {
    static func items(_ object: [String: Any], _ tag: String) -> [[String: Any]] {
        (object[tag] as? [String: Any])?["Value"] as? [[String: Any]] ?? []
    }

    /// PS3.4 CC.2.5-3 and its Code/Content Item/Referenced Instances macros.
    /// Real-world conditions (e.g. whether a subject needs identification) remain
    /// the creating SCU's responsibility; conditions expressed in the data are checked here.
    static func validateAttributes(_ object: [String: Any]) -> String? {
        for tag in [Tag.priority, Tag.label, Tag.start, Tag.readiness, Tag.state] {
            if object[tag] != nil && !hasValue(object, tag) { return "empty Type 1 attribute \(tag)" }
        }
        for (tag, allowed) in [(Tag.priority, ["HIGH", "MEDIUM", "LOW"]),
                               (Tag.readiness, ["READY", "UNAVAILABLE", "INCOMPLETE"])] {
            if let text = value(object, tag), !allowed.contains(text) { return "invalid value of \(tag)" }
        }
        return validateNested(object)
    }

    static func validateQueryKeys(_ keys: [String: Any]) -> String? {
        if keys[Tag.transaction] != nil { return "Transaction UID cannot be queried" }
        let singleValue: Set<String> = [Tag.instance, Tag.priority, Tag.readiness, Tag.state,
                                        "00080100", "00080102", "00080119", "00080120"]
        for (tag, raw) in keys {
            if tag == "00080104", hasValue(keys, tag) { return "Code Meaning is not a Matching Key" }
            if singleValue.contains(tag), let text = value(keys, tag), text.contains(where: { "*?\\".contains($0) }) {
                return "\(tag) requires Single Value Matching"
            }
            if (raw as? [String: Any])?["vr"] as? String == "SQ" {
                for item in items(keys, tag) {
                    if let error = validateQueryKeys(item) { return error }
                }
            }
        }
        return nil
    }

    private static let codeSequences: Set<String> = [
        "00404025", "00404026", "00404027", "00404018", "00404009", "00404028", "00404029",
        "00404030", "00404019", "0074100E", "00081084", "00321064", "0040100A", "00321034",
        "0040A043", "0040A168", "004008EA", "00100044", "00100046", "00100015", "00400039", "0040003A"
    ]
    private static let contentSequences: Set<String> = ["00741210", "00741212", "00741007", "00400441"]

    private static func validateNested(_ object: [String: Any]) -> String? {
        for (tag, raw) in object {
            guard let attribute = raw as? [String: Any], let vr = attribute["vr"] as? String else {
                return "malformed attribute \(tag)"
            }
            if let expected = DicomSpec.shared.vrForTag(withCode: tag), String(describing: expected) != vr {
                return "incorrect VR for \(tag)"
            }
            if vr != "SQ" { continue }
            if let values = attribute["Value"], !(values is [[String: Any]]) { return "invalid sequence \(tag)" }
            let children = items(object, tag)
            if [Tag.progress, Tag.performed].contains(tag), children.count > 1 { return "single-item sequence \(tag)" }
            for child in children {
                func required(_ tags: [String], emptyAllowed: Bool = false) -> String? {
                    tags.first { emptyAllowed ? child[$0] == nil : !hasValue(child, $0) }
                }
                if codeSequences.contains(tag), let error = validateCode(child) { return "\(tag): \(error)" }
                if contentSequences.contains(tag) {
                    let valueTags = ["DATETIME": "0040A120", "DATE": "0040A121", "TIME": "0040A122",
                                     "PNAME": "0040A123", "UIDREF": "0040A124", "TEXT": "0040A160",
                                     "CODE": "0040A168", "NUMERIC": "0040A30A"]
                    guard let type = value(child, "0040A040"), let valueTag = valueTags[type] else {
                        return "\(tag): invalid Value Type"
                    }
                    if let missing = required(["0040A043", valueTag]) { return "\(tag): missing \(missing)" }
                    if type == "NUMERIC", let missing = required(["004008EA"]) { return "\(tag): missing \(missing)" }
                }
                let requiredValues: [String]
                let requiredPresence: [String]
                switch tag {
                case "00741216": requiredValues = []; requiredPresence = ["00404033"]
                case "00404034": requiredValues = ["00404009", "00404037", "00404036"]; requiredPresence = []
                case "00741008": requiredValues = ["0074100A"]; requiredPresence = []
                case "00101002": requiredValues = ["00100020"]; requiredPresence = ["00100021", "00100024"]
                case "0040A370":
                    requiredValues = ["0020000D"]
                    requiredPresence = ["00080050", "00080051", "00400026", "00400027", "00401001", "00321060", "00321064"]
                case "00100041": requiredValues = ["00100044"]; requiredPresence = []
                case "00100043":
                    requiredValues = ["00100046"]
                    requiredPresence = items(child, "00100046").contains { value($0, "00080100") == "131232" && value($0, "00080102") == "DCM" } ? ["00100042", "00100047"] : []
                case "00100011": requiredValues = ["00100012"]; requiredPresence = []
                case "00100014": requiredValues = ["00100015"]; requiredPresence = []
                case "00404021", "00404033":
                    requiredValues = ["0040E020", "00081199"]
                    requiredPresence = []
                    if !["0040E021", "0040E022", "0040E023", "0040E024", "0040E025"].contains(where: { hasValue(child, $0) }) {
                        return "\(tag): a retrieval sequence is required"
                    }
                    if value(child, "0040E020") == "DICOM" {
                        let models = items(child, "00081199").compactMap { reference in
                            value(reference, "00081150").flatMap { DICOMIODSpecification.shared.iod(forSOPClass: $0) }
                        }
                        for (name, key) in [("Study", "0020000D"), ("Series", "0020000E")] {
                            if models.contains(where: { $0.modules.contains(where: { $0.name.contains(name) }) }),
                               !hasValue(child, key) { return "\(tag): missing \(key) for referenced IOD" }
                        }
                    }
                    if value(child, "0040E020") == "CDA",
                       items(child, "00081199").contains(where: { !hasValue($0, "0040E001") }) {
                        return "\(tag): CDA requires HL7 Instance Identifier"
                    }
                case "0040E021": requiredValues = ["00080054"]; requiredPresence = []
                case "0040E022": requiredValues = ["00880140"]; requiredPresence = ["00880130"]
                case "0040E023": requiredValues = ["0040E010"]; requiredPresence = []
                case "0040E025": requiredValues = ["00081190"]; requiredPresence = []
                case "0040E024", "00404074": requiredValues = ["0040E030"]; requiredPresence = []
                case "00404070":
                    requiredValues = []; requiredPresence = []
                    if !["00404071", "00404072", "00404074"].contains(where: { hasValue(child, $0) }) {
                        return "\(tag): a storage destination sequence is required"
                    }
                case "00404071": requiredValues = ["21000140"]; requiredPresence = []
                case "00404072": requiredValues = ["00404073"]; requiredPresence = []
                case "00080051", "00380014", "00400026", "00400027", "00400036":
                    requiredValues = []; requiredPresence = []
                    if !hasValue(child, "00400031") && !hasValue(child, "00400032") {
                        return "\(tag): local or universal entity ID is required"
                    }
                    if hasValue(child, "00400032") && !hasValue(child, "00400033") {
                        return "\(tag): Universal Entity ID Type is required"
                    }
                case "00100024":
                    requiredValues = hasValue(child, "00400032") ? ["00400033"] : []
                    requiredPresence = ["00400032", "00400035", "00400036", "00400039", "0040003A"]
                case "00741224", "00081199": requiredValues = ["00081150", "00081155"]; requiredPresence = []
                default: requiredValues = []; requiredPresence = []
                }
                if let missing = required(requiredValues) ?? required(requiredPresence, emptyAllowed: true) {
                    return "\(tag): missing \(missing)"
                }
                if let error = validateNested(child) { return error }
            }
        }
        return nil
    }

    private static func validateCode(_ code: [String: Any]) -> String? {
        let present = ["00080100", "00080119", "00080120"].filter { hasValue(code, $0) }
        if present.count != 1 { return "exactly one Code Value, Long Code Value or URN Code Value is required" }
        if let short = value(code, "00080100"), short.count > 16 || short.hasPrefix("urn:") || short.contains("://") {
            return "use Long Code Value or URN Code Value"
        }
        if !hasValue(code, "00080104") { return "Code Meaning is required" }
        if present[0] != "00080120" && !hasValue(code, "00080102") { return "Coding Scheme Designator is required" }
        if code["00080103"] != nil && !hasValue(code, "00080102") { return "Coding Scheme Version requires a designator" }
        return nil
    }
}
