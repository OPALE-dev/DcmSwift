import Foundation

/// A PS3.16 template as rows (PS3.16 6.1): the content items a container may
/// hold, their relationship, value type, concept name, cardinality, and
/// requirement. Conditions of MC and UC rows are not evaluated: such rows
/// are checked as optional. The templates of the Standard are generated
/// from PS3.16 (``DICOMSRTemplateLibrary``).
public struct DICOMSRTemplate: Sendable {
    /// The concept name a row asks for.
    public enum Concept: Sendable {
        /// Enumerated value: this code (EV).
        case code(DICOMCode)
        /// A Context Group: defined (DCID), whose codes are required (an
        /// extensible group may be extended, reported as a warning), or
        /// baseline (BCID), whose codes are suggested (any code is accepted).
        case group(Int, baseline: Bool)
        /// A code of any of these Context Groups.
        case groups([Int], baseline: Bool)
        /// Defined term (DT): this code, which another code may replace.
        case defined(DICOMCode)
        /// Any concept name, or none.
        case any
    }

    /// Conditions of PS3.16 tables on the presence of other rows.
    public enum Presence: Sendable, Equatable {
        /// Exactly one of these rows (MC), at most one (UC).
        case exclusive([String])
        /// At least one of these rows.
        case atLeastOne([String])
        /// Required when all these rows are absent.
        case ifAbsent([String])
        /// Required when this row is present, forbidden otherwise.
        case ifAndOnlyIfPresent([String])
    }

    public enum Requirement: String, Sendable {
        /// Mandatory.
        case mandatory = "M"
        /// Mandatory under a condition, not evaluated.
        case mandatoryConditional = "MC"
        case userOption = "U"
        case userOptionConditional = "UC"
    }

    public struct Row: Sendable {
        public var relationship: String?
        public var valueTypes: [String]
        public var concept: Concept
        /// Context Group of a CODE value.
        public var valueGroup: Int? {
            get { if case .group(let cid, _) = value { return cid } else { return nil } }
            set { value = newValue.map { .group($0, baseline: false) } }
        }
        /// Constraint on a CODE value: code, defined term, or Context Group.
        public var value: Concept?
        /// Constraint on the units of a NUM value.
        public var units: Concept?
        /// The row's content is accepted without looking inside: an included
        /// template that is missing, recursive, or nested too deep.
        public var unchecked = false
        /// Where the row comes from: template instance and row number.
        public var origin: String?
        /// Condition on the presence of sibling rows (by origin), evaluated
        /// for MC and UC rows; other conditions are not evaluated.
        public var presence: Presence?
        /// The row comes from an optional inclusion: its conditions apply
        /// only once a row of that inclusion is present.
        public var optionalInclusion = false
        public var minimum: Int
        public var maximum: Int?
        public var requirement: Requirement
        public var children: [Row]

        public init(_ relationship: String?, _ valueTypes: [String], _ concept: Concept, valueGroup: Int? = nil,
                    _ minimum: Int = 1, _ maximum: Int? = 1, _ requirement: Requirement = .mandatory, children: [Row] = []) {
            self.relationship = relationship
            self.valueTypes = valueTypes
            self.concept = concept
            self.value = valueGroup.map { .group($0, baseline: false) }
            self.minimum = minimum
            self.maximum = maximum
            self.requirement = requirement
            self.children = children
        }

        /// An optional row.
        static func optional(_ relationship: String, _ valueType: String, _ concept: Concept, valueGroup: Int? = nil,
                             many: Bool = false, children: [Row] = []) -> Row {
            Row(relationship, [valueType], concept, valueGroup: valueGroup, 0, many ? nil : 1, .userOption, children: children)
        }
    }

    /// Template number, such as "2000".
    public var identifier: String
    public var name: String
    /// An extensible template accepts content items it does not list.
    public var extensible: Bool
    public var root: Row

    public init(identifier: String, name: String, extensible: Bool = true, root: Row) {
        self.identifier = identifier
        self.name = name
        self.extensible = extensible
        self.root = root
    }
}

/// A finding of SR validation.
public struct DICOMSRValidationIssue: Sendable, Equatable, CustomStringConvertible {
    public enum Severity: String, Sendable { case error, warning }

    public var severity: Severity
    /// Content item identifier, such as "1.4.2" (PS3.3 C.17.3.2.5); empty for the header.
    public var path: String
    public var message: String

    public var description: String { "\(severity.rawValue) \(path.isEmpty ? "header" : path): \(message)" }
}

/// Checks an SR document against its IOD constraints (value types and
/// relationships allowed by its SOP Class, flags) and against the template
/// it declares, or one given, using the Context Groups of the terminology.
public enum DICOMSRTemplateValidator {
    /// The templates of the Standard, generated from PS3.16.
    public static var library: DICOMSRTemplateLibrary { .shared }

    /// Validates a document; without `template`, the declared one is used
    /// (Content Template Sequence, mapping resource DCMR), if known.
    public static func validate(_ document: DICOMStructuredReport, against template: DICOMSRTemplate? = nil,
                                terminology: DICOMTerminology = .shared) -> [DICOMSRValidationIssue] {
        var issues = header(document)
        issues += sopClassConstraints(document)
        let chosen = template ?? document.template.flatMap { $0.mappingResource == "DCMR" ? library.template($0.identifier) : nil }
        if let chosen {
            var checker = Checker(terminology: terminology, extensible: chosen.extensible)
            checker.check(document.root, path: [1], against: chosen.root)
            issues += checker.issues
        }
        return issues
    }

    /// Validates the SR document of a data set; nil when it holds none.
    public static func validate(dataSet: DataSet, terminology: DICOMTerminology = .shared) -> [DICOMSRValidationIssue]? {
        DICOMStructuredReport(dataSet: dataSet).map { validate($0, terminology: terminology) }
    }

    static func header(_ document: DICOMStructuredReport) -> [DICOMSRValidationIssue] {
        guard !document.isKeyObjectSelection else { return [] }
        var issues: [DICOMSRValidationIssue] = []
        if !["PARTIAL", "COMPLETE"].contains(document.completionFlag) {
            issues.append(.init(severity: .error, path: "", message: "Completion Flag must be PARTIAL or COMPLETE"))
        }
        if !["UNVERIFIED", "VERIFIED"].contains(document.verificationFlag) {
            issues.append(.init(severity: .error, path: "", message: "Verification Flag must be UNVERIFIED or VERIFIED"))
        }
        if document.verificationFlag == "VERIFIED" && document.verifyingObservers.isEmpty {
            issues.append(.init(severity: .error, path: "", message: "a VERIFIED document needs a Verifying Observer Sequence"))
        }
        if let flag = document.preliminaryFlag, !["PRELIMINARY", "FINAL"].contains(flag) {
            issues.append(.init(severity: .error, path: "", message: "Preliminary Flag must be PRELIMINARY or FINAL"))
        }
        return issues
    }

    /// Value types of the SOP Classes with restrictions (PS3.3 A.35.1,
    /// A.35.2, A.35.4): Basic Text SR, Enhanced SR, Key Object Selection.
    static func sopClassConstraints(_ document: DICOMStructuredReport) -> [DICOMSRValidationIssue] {
        let basic: Set = ["CONTAINER", "TEXT", "CODE", "DATETIME", "DATE", "TIME", "UIDREF", "PNAME", "COMPOSITE", "IMAGE", "WAVEFORM"]
        let allowed: Set<String>
        switch document.sopClassUID {
        case DICOMStructuredReport.basicTextSR: allowed = basic
        case DICOMStructuredReport.enhancedSR: allowed = basic.union(["NUM", "SCOORD", "TCOORD"])
        case DICOMStructuredReport.keyObjectSelection: allowed = ["CONTAINER", "TEXT", "CODE", "UIDREF", "PNAME", "COMPOSITE", "IMAGE", "WAVEFORM"]
        default: return []
        }
        return document.root.flattened().compactMap { entry in
            let identifier = entry.identifier.map(String.init).joined(separator: ".")
            if case .reference = entry.item.value {
                return .init(severity: .error, path: identifier, message: "by-reference relationships are not allowed in this SOP Class")
            }
            let type = entry.item.value.valueType
            return allowed.contains(type) ? nil
                : .init(severity: .error, path: identifier, message: "value type \(type) is not allowed in this SOP Class")
        }
    }

    struct Checker {
        let terminology: DICOMTerminology
        let extensible: Bool
        var issues: [DICOMSRValidationIssue] = []

        func name(_ path: [Int]) -> String { path.map(String.init).joined(separator: ".") }

        mutating func report(_ severity: DICOMSRValidationIssue.Severity, _ path: [Int], _ message: String) {
            issues.append(.init(severity: severity, path: name(path), message: message))
        }

        /// Whether an item fits a row; `loosely` also accepts concepts an
        /// extensible group allows without listing them.
        func fits(_ item: DICOMSRContentItem, _ row: DICOMSRTemplate.Row, loosely: Bool) -> Bool {
            guard row.relationship == nil || item.relationship == row.relationship,
                  row.valueTypes.contains(item.value.valueType) else { return false }
            // A reference may go without concept name (its purpose): the row's constraint applies when it has one.
            if item.conceptName == nil, ["IMAGE", "COMPOSITE", "WAVEFORM"].contains(item.value.valueType) { return true }
            switch row.concept {
            case .any: return true
            case .code(let code): return item.conceptName?.sameConcept(as: code) == true
            case .defined(let code): return loosely ? item.conceptName != nil : item.conceptName?.sameConcept(as: code) == true
            case .group(let cid, let baseline):
                guard let concept = item.conceptName else { return false }
                let membership = terminology.membership(of: concept, in: cid)
                return membership == .member || (loosely && (baseline || membership != .notAllowed))
            case .groups(let cids, let baseline):
                guard let concept = item.conceptName else { return false }
                let memberships = cids.map { terminology.membership(of: concept, in: $0) }
                return memberships.contains(.member) || (loosely && (baseline || memberships.contains { $0 != .notAllowed }))
            }
        }

        mutating func check(_ item: DICOMSRContentItem, path: [Int], against row: DICOMSRTemplate.Row) {
            if !fits(item, row, loosely: true) {
                report(.error, path, "expected \(row.valueTypes.joined(separator: "/")) \(describe(row.concept)), found \(item.value.valueType) \(item.conceptName?.description ?? "without concept name")")
                return
            }
            checkConcept(item, path: path, row: row)
            checkValue(item, path: path, row: row)
            if row.unchecked { return }
            // Assign each child to a row it fits strictly, then loosely. When several rows fit (the
            // same concept in several included templates), the one whose check finds fewest errors wins.
            var assigned = [Int?](repeating: nil, count: item.children.count)
            for loosely in [false, true] {
                for (index, child) in item.children.enumerated() where assigned[index] == nil {
                    // A defined term stands for its meaning under another code: loosely, it takes an item
                    // only while it has room, so unrelated items are not all counted against it.
                    let candidates = row.children.indices.filter { index in
                        let candidate = row.children[index]
                        guard fits(child, candidate, loosely: loosely) else { return false }
                        guard loosely, case .defined = candidate.concept, let maximum = candidate.maximum else { return true }
                        return assigned.filter { $0 == index }.count < maximum
                    }
                    assigned[index] = candidates.count < 2 ? candidates.first : candidates.min { a, b in
                        errors(child, against: row.children[a]) < errors(child, against: row.children[b])
                    }
                }
            }
            checkPresence(row.children, counts: row.children.indices.map { index in assigned.filter { $0 == index }.count }, path: path)
            for (rowIndex, childRow) in row.children.enumerated() {
                let matched = item.children.indices.filter { assigned[$0] == rowIndex }
                if matched.count < childRow.minimum && childRow.requirement == .mandatory {
                    report(.error, path, "missing \(childRow.relationship ?? "") \(childRow.valueTypes.joined(separator: "/")) \(describe(childRow.concept))"
                           + (childRow.minimum > 1 ? " (at least \(childRow.minimum))" : ""))
                }
                if let maximum = childRow.maximum, matched.count > maximum {
                    report(.error, path, "\(matched.count) items \(describe(childRow.concept)), at most \(maximum) allowed")
                }
                for index in matched {
                    check(item.children[index], path: path + [index + 1], against: childRow)
                }
            }
            if !extensible {
                for (index, child) in item.children.enumerated() where assigned[index] == nil && !row.children.isEmpty {
                    report(.error, path + [index + 1], "\(child.relationship ?? "") \(child.value.valueType) \(child.conceptName?.description ?? "") is not part of the template")
                }
            }
        }

        /// Errors a trial check of an item against a row finds.
        func errors(_ item: DICOMSRContentItem, against row: DICOMSRTemplate.Row) -> Int {
            var trial = Checker(terminology: terminology, extensible: extensible)
            trial.check(item, path: [], against: row)
            return trial.issues.filter { $0.severity == .error }.count
        }

        /// Presence conditions between sibling rows: each finding once.
        mutating func checkPresence(_ rows: [DICOMSRTemplate.Row], counts: [Int], path: [Int]) {
            var present: [String: Bool] = [:], label: [String: String] = [:]
            for (index, row) in rows.enumerated() {
                guard let origin = row.origin else { continue }
                present[origin] = (present[origin] ?? false) || counts[index] > 0
                label[origin] = label[origin] ?? "\(row.valueTypes.joined(separator: "/")) \(describe(row.concept))".trimmingCharacters(in: .whitespaces)
            }
            // Instances of optional inclusions with nothing present: their conditions do not apply.
            func instance(_ origin: String) -> Substring { origin.prefix { $0 != "#" } }
            let optional = Set(rows.filter(\.optionalInclusion).compactMap { $0.origin.map(instance) })
            let used = Set(present.filter(\.value).keys.map(instance))
            var reported = Set<String>()
            func once(_ message: String) {
                if reported.insert(message).inserted { report(.error, path, message) }
            }
            for row in rows {
                guard let origin = row.origin, let presence = row.presence,
                      row.requirement == .mandatoryConditional || row.requirement == .userOptionConditional,
                      !optional.contains(instance(origin)) || used.contains(instance(origin)) else { continue }
                let mandatory = row.requirement == .mandatoryConditional
                func known(_ origins: [String]) -> [String]? { origins.allSatisfy { present[$0] != nil } ? origins : nil }
                func names(_ origins: [String]) -> String {
                    // Rows that differ only by their value set read the same: each name once.
                    var seen = Set<String>()
                    return origins.compactMap { label[$0] }.filter { seen.insert($0).inserted }.joined(separator: ", ")
                }
                switch presence {
                case .exclusive(let others):
                    guard let set = known(Array(Set(others + [origin])).sorted()) else { continue }
                    let count = set.filter { present[$0] == true }.count
                    if count > 1 { once("only one of \(names(set)) may be present") }
                    if count == 0, mandatory { once("one of \(names(set)) is required") }
                case .atLeastOne(let set):
                    guard let set = known(set) else { continue }
                    if mandatory, !set.contains(where: { present[$0] == true }) { once("at least one of \(names(set)) is required") }
                case .ifAbsent(let others):
                    guard let others = known(others) else { continue }
                    if mandatory, present[origin] != true, !others.contains(where: { present[$0] == true }) {
                        once("\(label[origin] ?? "") is required when \(names(others)) \(others.count > 1 ? "are" : "is") absent")
                    }
                case .ifAndOnlyIfPresent(let others):
                    guard let others = known(others) else { continue }
                    let condition = others.allSatisfy { present[$0] == true }
                    if condition, mandatory, present[origin] != true { once("\(label[origin] ?? "") is required when \(names(others)) is present") }
                    if !condition, present[origin] == true { once("\(label[origin] ?? "") is only allowed when \(names(others)) is present") }
                }
            }
        }

        mutating func checkConcept(_ item: DICOMSRContentItem, path: [Int], row: DICOMSRTemplate.Row) {
            guard case .group(let cid, false) = row.concept, let concept = item.conceptName else { return }
            if terminology.membership(of: concept, in: cid) == .allowedByExtension {
                report(.warning, path, "concept name \(concept) is not listed in CID \(cid)")
            }
        }

        mutating func checkValue(_ item: DICOMSRContentItem, path: [Int], row: DICOMSRTemplate.Row) {
            switch item.value {
            case .code(let value): check(value, against: row.value, path: path, what: "coded value")
            case .number(_, let units?, _): check(units, against: row.units, path: path, what: "units")
            default: break
            }
        }

        mutating func check(_ code: DICOMCode, against constraint: DICOMSRTemplate.Concept?, path: [Int], what: String) {
            switch constraint {
            case .group(let cid, let baseline)?:
                guard !baseline else { break }
                switch terminology.membership(of: code, in: cid) {
                case .notAllowed: report(.error, path, "\(what) \(code) is not in CID \(cid)")
                case .allowedByExtension: report(.warning, path, "\(what) \(code) is not listed in CID \(cid)")
                case .member, .undetermined: break
                }
            case .groups(let cids, let baseline)?:
                guard !baseline else { break }
                let memberships = cids.map { terminology.membership(of: code, in: $0) }
                if memberships.contains(.member) || memberships.contains(.undetermined) { break }
                let list = cids.map { "CID \($0)" }.joined(separator: ", ")
                if memberships.allSatisfy({ $0 == .notAllowed }) { report(.error, path, "\(what) \(code) is not in \(list)") }
                else { report(.warning, path, "\(what) \(code) is not listed in \(list)") }
            case .code(let expected)?:
                if !code.sameConcept(as: expected) { report(.error, path, "\(what) \(code) should be \(expected)") }
            case .defined(let expected)?:
                if !code.sameConcept(as: expected) { report(.warning, path, "\(what) \(code) differs from the defined term \(expected)") }
            case .any?, nil: break
            }
        }

        func describe(_ concept: DICOMSRTemplate.Concept) -> String {
            switch concept {
            case .code(let code), .defined(let code): return code.description
            case .group(let cid, _): return "from CID \(cid)"
            case .groups(let cids, _): return "from " + cids.map { "CID \($0)" }.joined(separator: " or ")
            case .any: return ""
            }
        }
    }
}

extension DICOMCode {
    /// Another code of the same scheme.
    func with(_ value: String, _ meaning: String) -> DICOMCode { DICOMCode(value, scheme: scheme, meaning: meaning) }
}
