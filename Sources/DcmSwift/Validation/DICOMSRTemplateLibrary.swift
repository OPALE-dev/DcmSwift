import Foundation

/// The templates of PS3.16 Annex A (2026d), generated from the Standard by
/// Scripts/generate-dicom-sr-templates.py, and expanded on demand into
/// ``DICOMSRTemplate`` rows: included templates are written in place with
/// the parameters the including row passes, their relationship, requirement
/// and multiplicity adjusted to that row.
///
/// What is not checked: conditions of MC and UC rows (such rows are
/// optional), constraints written as prose, and the content of an included
/// template that is missing from the resource, includes itself, or lies
/// deeper than ``maximumDepth``; such content is accepted as is.
public final class DICOMSRTemplateLibrary: @unchecked Sendable {
    /// The library bundled with DcmSwift, loaded on first use.
    public static let shared: DICOMSRTemplateLibrary = {
        do {
            guard let url = Bundle.module.url(forResource: "dicom-sr-templates-2026d", withExtension: "json") else {
                fatalError("DcmSwift's bundled SR template resource is missing")
            }
            return try DICOMSRTemplateLibrary(data: Data(contentsOf: url))
        } catch {
            fatalError("DcmSwift's bundled SR templates cannot be read: \(error)")
        }
    }()

    /// Nesting of included templates beyond which content is not checked.
    public static let maximumDepth = 12

    /// A template as the Standard writes it.
    public struct Definition: Decodable, Sendable {
        public let identifier: String
        public let name: String
        public let extensible: Bool
        public let orderSignificant: Bool
        /// Whether the template may be the root of a document.
        public let root: Bool
        public let parameters: [String]
        let rows: [RowDefinition]
    }

    struct Form: Decodable, Sendable {
        let code: [String]?
        let defined: Bool?
        let group: Int?
        let groups: [Int]?
        let baseline: Bool?
        let include: String?
        let parameter: String?
    }

    struct RowDefinition: Decodable, Sendable {
        let row: String
        let depth: Int
        let relationship: String?
        let valueTypes: [String]
        let concept: Form?
        let multiplicity: [Int?]
        let requirement: String
        let condition: String?
        let value: Form?
        let units: Form?
        let arguments: [String: Form]?
        let presence: [String: [String]]?
    }

    struct Resource: Decodable {
        let edition: String
        let templates: [Definition]
    }

    /// The edition of the Standard, such as 2026d.
    public let edition: String
    private let definitions: [String: Definition]
    private let lock = NSLock()
    private var expanded: [String: DICOMSRTemplate] = [:]
    /// Numbers each expansion of a template, so conditions name the rows of their own instance.
    private var instances = 0

    public init(data: Data) throws {
        let resource = try JSONDecoder().decode(Resource.self, from: data)
        edition = resource.edition
        definitions = Dictionary(resource.templates.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Template numbers of the resource.
    public var identifiers: [String] { definitions.keys.sorted { (Int($0) ?? 0, $0) < (Int($1) ?? 0, $1) } }

    /// The definition of a template, such as "2000".
    public func definition(_ identifier: String) -> Definition? { definitions[identifier] }

    /// The name of a template, such as "Basic Diagnostic Imaging Report".
    public func name(of identifier: String) -> String? { definitions[identifier]?.name }

    /// A template expanded for validation; nil when the Standard has no such
    /// template or its table has no root row.
    public func template(_ identifier: String) -> DICOMSRTemplate? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = expanded[identifier] { return cached }
        guard let definition = definitions[identifier] else { return nil }
        let rows = expand(definition, bindings: [:], stack: [identifier])
        guard rows.count == 1, let root = rows.first else { return nil }
        let template = DICOMSRTemplate(identifier: identifier, name: definition.name, extensible: definition.extensible, root: root)
        expanded[identifier] = template
        return template
    }

    // MARK: Expansion

    typealias Row = DICOMSRTemplate.Row

    /// The top-level rows of a template, with their children.
    private func expand(_ definition: Definition, bindings: [String: Form], stack: [String]) -> [Row] {
        instances += 1
        let instance = instances
        // Rows nest by level: each row belongs to the closest earlier row one level up.
        func children(from start: Int, depth: Int) -> (rows: [Row], next: Int) {
            var result: [Row] = []
            var index = start
            while index < definition.rows.count {
                let row = definition.rows[index]
                if row.depth < depth { break }
                if row.depth > depth { index += 1; continue } // orphaned deeper row: skipped
                let nested = children(from: index + 1, depth: depth + 1)
                result += rows(for: row, children: nested.rows, bindings: bindings, stack: stack, instance: instance)
                index = nested.next
            }
            return (result, index)
        }
        let minimum = definition.rows.map(\.depth).min() ?? 0
        return children(from: 0, depth: minimum).rows
    }

    private func rows(for row: RowDefinition, children: [Row], bindings: [String: Form], stack: [String], instance: Int) -> [Row] {
        let minimum = row.multiplicity.first.flatMap { $0 } ?? 1
        let maximum: Int? = row.multiplicity.count > 1 ? row.multiplicity[1] : minimum
        let requirement = DICOMSRTemplate.Requirement(rawValue: row.requirement) ?? .userOption
        if row.valueTypes.first == "INCLUDE" {
            let target = resolve(row.concept, bindings)?.include
            guard let target, let included = definitions[target], !stack.contains(target),
                  stack.count < Self.maximumDepth else {
                var unchecked = Row(row.relationship, Self.allValueTypes, .any, 0, nil, .userOption)
                unchecked.unchecked = true
                return [unchecked]
            }
            var passed: [String: Form] = [:]
            for (name, form) in row.arguments ?? [:] { passed[name] = resolve(form, bindings) ?? form }
            return expand(included, bindings: passed, stack: stack + [target]).map { top in
                var top = top
                if top.relationship == nil { top.relationship = row.relationship }
                if requirement != .mandatory, top.requirement == .mandatory { top.requirement = .userOption }
                if requirement != .mandatory { top.minimum = 0; top.optionalInclusion = true }
                if maximum == nil { top.maximum = nil } else if let each = top.maximum, let times = maximum { top.maximum = each * times }
                return top
            }
        }
        var result = Row(row.relationship, row.valueTypes, concept(resolve(row.concept, bindings)),
                         requirement == .mandatory ? minimum : 0, maximum, requirement, children: children)
        result.value = row.value.flatMap { resolve($0, bindings) }.map(concept)
        result.units = row.units.flatMap { resolve($0, bindings) }.map(concept)
        result.origin = "\(instance)#\(row.row)"
        if let presence = row.presence, let kind = presence.keys.first, let rows = presence[kind] {
            let origins = rows.map { "\(instance)#\($0)" }
            switch kind {
            case "xor": result.presence = .exclusive(origins)
            case "atLeastOne": result.presence = .atLeastOne(origins)
            case "ifAbsent": result.presence = .ifAbsent(origins)
            case "iffPresent": result.presence = .ifAndOnlyIfPresent(origins)
            default: break
            }
        }
        return [result]
    }

    static let allValueTypes = ["CONTAINER", "TEXT", "CODE", "NUM", "DATETIME", "DATE", "TIME", "UIDREF", "PNAME",
                                "COMPOSITE", "IMAGE", "WAVEFORM", "SCOORD", "SCOORD3D", "TCOORD", "TABLE"]

    /// A form with its parameter replaced by the value passed; an unbound
    /// parameter stays unresolved (any concept).
    private func resolve(_ form: Form?, _ bindings: [String: Form]) -> Form? {
        guard let form else { return nil }
        if let parameter = form.parameter { return bindings[parameter] }
        return form
    }

    private func concept(_ form: Form?) -> DICOMSRTemplate.Concept {
        guard let form else { return .any }
        if let code = form.code, code.count == 3 {
            let value = DICOMCode(code[0], scheme: code[1], meaning: code[2])
            return form.defined == true ? .defined(value) : .code(value)
        }
        if let group = form.group { return .group(group, baseline: form.baseline ?? false) }
        if let groups = form.groups { return .groups(groups, baseline: form.baseline ?? false) }
        return .any
    }
}
