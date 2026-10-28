import Foundation

/// A PS3.16 template as rows (PS3.16 6.1): the content items a container may
/// hold, their relationship, value type, concept name, cardinality, and
/// requirement. Conditions of MC and UC rows are not evaluated: such rows
/// are checked as optional.
public struct DICOMSRTemplate: Sendable {
    /// The concept name a row asks for.
    public enum Concept: Sendable {
        /// Enumerated value: this code (EV).
        case code(DICOMCode)
        /// A Context Group: defined (DCID) or baseline (BCID). A code outside
        /// an extensible group is accepted; outside a baseline group it is
        /// reported as a warning.
        case group(Int, baseline: Bool)
        /// Any concept name, or none.
        case any
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
        public var valueGroup: Int?
        public var minimum: Int
        public var maximum: Int?
        public var requirement: Requirement
        public var children: [Row]

        public init(_ relationship: String?, _ valueTypes: [String], _ concept: Concept, valueGroup: Int? = nil,
                    _ minimum: Int = 1, _ maximum: Int? = 1, _ requirement: Requirement = .mandatory, children: [Row] = []) {
            self.relationship = relationship
            self.valueTypes = valueTypes
            self.concept = concept
            self.valueGroup = valueGroup
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
    /// The templates the validator knows, by identifier.
    public static let templates: [String: DICOMSRTemplate] = Dictionary(uniqueKeysWithValues: [
        DICOMSRTemplates.basicDiagnosticImagingReport, DICOMSRTemplates.keyObjectSelection, DICOMSRTemplates.measurementReport,
        DICOMSRTemplates.ctRadiationDose, DICOMSRTemplates.projectionXRayRadiationDose, DICOMSRTemplates.radiopharmaceuticalRadiationDose,
        DICOMSRTemplates.patientRadiationDose, DICOMSRTemplates.mammographyCAD, DICOMSRTemplates.chestCAD,
        DICOMSRTemplates.obstetricGynecologicUltrasound, DICOMSRTemplates.vascularUltrasound, DICOMSRTemplates.echocardiography,
    ].map { ($0.identifier, $0) })

    /// Validates a document; without `template`, the declared one is used
    /// (Content Template Sequence, mapping resource DCMR), if known.
    public static func validate(_ document: DICOMStructuredReport, against template: DICOMSRTemplate? = nil,
                                terminology: DICOMTerminology = .shared) -> [DICOMSRValidationIssue] {
        var issues = header(document)
        issues += sopClassConstraints(document)
        let chosen = template ?? document.template.flatMap { $0.mappingResource == "DCMR" ? templates[$0.identifier] : nil }
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
            switch row.concept {
            case .any: return true
            case .code(let code): return item.conceptName?.sameConcept(as: code) == true
            case .group(let cid, _):
                guard let concept = item.conceptName else { return false }
                let membership = terminology.membership(of: concept, in: cid)
                return membership == .member || (loosely && membership != .notAllowed)
            }
        }

        mutating func check(_ item: DICOMSRContentItem, path: [Int], against row: DICOMSRTemplate.Row) {
            if !fits(item, row, loosely: true) {
                report(.error, path, "expected \(row.valueTypes.joined(separator: "/")) \(describe(row.concept)), found \(item.value.valueType) \(item.conceptName?.description ?? "without concept name")")
                return
            }
            checkConcept(item, path: path, row: row)
            checkValue(item, path: path, row: row)
            // Assign each child to the first row it fits strictly, then loosely.
            var assigned = [Int?](repeating: nil, count: item.children.count)
            for loosely in [false, true] {
                for (index, child) in item.children.enumerated() where assigned[index] == nil {
                    assigned[index] = row.children.firstIndex { fits(child, $0, loosely: loosely) }
                }
            }
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

        mutating func checkConcept(_ item: DICOMSRContentItem, path: [Int], row: DICOMSRTemplate.Row) {
            guard case .group(let cid, let baseline) = row.concept, let concept = item.conceptName else { return }
            if terminology.membership(of: concept, in: cid) == .allowedByExtension && baseline {
                report(.warning, path, "concept name \(concept) is not in baseline CID \(cid)")
            }
        }

        mutating func checkValue(_ item: DICOMSRContentItem, path: [Int], row: DICOMSRTemplate.Row) {
            guard let cid = row.valueGroup, case .code(let value) = item.value else { return }
            switch terminology.membership(of: value, in: cid) {
            case .notAllowed: report(.error, path, "coded value \(value) is not in CID \(cid)")
            case .allowedByExtension: report(.warning, path, "coded value \(value) is not listed in CID \(cid)")
            case .member, .undetermined: break
            }
        }

        func describe(_ concept: DICOMSRTemplate.Concept) -> String {
            switch concept {
            case .code(let code): return code.description
            case .group(let cid, _): return "from CID \(cid)"
            case .any: return ""
            }
        }
    }
}

/// The rows of the templates the validator knows. Included templates are
/// written in place; rows the validator cannot check (conditions, by
/// reference content) are optional.
public enum DICOMSRTemplates {
    typealias Row = DICOMSRTemplate.Row
    static let dcm = DICOMSRCodes.dcm

    /// TID 1204 Language of Content Item and Descendants.
    static let language = Row.optional("HAS CONCEPT MOD", "CODE", .code(DICOMSRCodes.language))

    /// TID 1002 Observer Context, with TID 1003 and 1004, all optional here.
    static let observerContext: [Row] = [
        .optional("HAS OBS CONTEXT", "CODE", .code(DICOMSRCodes.observerType), valueGroup: 270, many: true),
        .optional("HAS OBS CONTEXT", "PNAME", .code(DICOMSRCodes.personObserverName), many: true),
        .optional("HAS OBS CONTEXT", "TEXT", .code(DICOMSRCodes.personObserverOrganization), many: true),
        .optional("HAS OBS CONTEXT", "CODE", .code(DICOMSRCodes.personObserverRoleInOrganization), many: true),
        .optional("HAS OBS CONTEXT", "CODE", .code(DICOMSRCodes.personObserverRoleInProcedure), many: true),
        .optional("HAS OBS CONTEXT", "UIDREF", .code(DICOMSRCodes.deviceObserverUID), many: true),
        .optional("HAS OBS CONTEXT", "TEXT", .code(DICOMSRCodes.deviceObserverName), many: true),
        .optional("HAS OBS CONTEXT", "TEXT", .code(DICOMSRCodes.deviceObserverManufacturer), many: true),
        .optional("HAS OBS CONTEXT", "TEXT", .code(DICOMSRCodes.deviceObserverModelName), many: true),
        .optional("HAS OBS CONTEXT", "TEXT", .code(DICOMSRCodes.deviceObserverSerialNumber), many: true),
    ]

    static func root(_ concept: DICOMSRTemplate.Concept, _ children: [Row]) -> Row {
        Row(nil, ["CONTAINER"], concept, children: children)
    }

    static func container(_ code: DICOMCode, _ minimum: Int = 1, _ maximum: Int? = 1,
                          _ requirement: DICOMSRTemplate.Requirement = .mandatory, _ children: [Row]) -> Row {
        Row("CONTAINS", ["CONTAINER"], .code(code), minimum, maximum, requirement, children: children)
    }

    static func item(_ type: String, _ code: DICOMCode, valueGroup: Int? = nil, _ relationship: String = "CONTAINS",
                     _ minimum: Int = 1, _ maximum: Int? = 1, _ requirement: DICOMSRTemplate.Requirement = .mandatory) -> Row {
        Row(relationship, [type], .code(code), valueGroup: valueGroup, minimum, maximum, requirement)
    }

    /// TID 2000 Basic Diagnostic Imaging Report, sections of TID 2002.
    public static let basicDiagnosticImagingReport: DICOMSRTemplate = {
        let image = Row.optional("INFERRED FROM", "IMAGE", .any, many: true)
        let section = Row("CONTAINS", ["CONTAINER"], .group(7001, baseline: false), 1, nil, .mandatory, children: observerContext + [
            .optional("CONTAINS", "TEXT", .group(7002, baseline: false), many: true, children: [image]),
            .optional("CONTAINS", "CODE", .group(7002, baseline: false), many: true, children: [image]),
            .optional("CONTAINS", "IMAGE", .any, many: true),
        ])
        return DICOMSRTemplate(identifier: "2000", name: "Basic Diagnostic Imaging Report", root: root(.group(7000, baseline: false),
            [language] + observerContext + [.optional("HAS CONCEPT MOD", "CODE", .code(DICOMSRCodes.procedureReported), many: true), section]))
    }()

    /// TID 2010 Key Object Selection.
    public static let keyObjectSelection = DICOMSRTemplate(identifier: "2010", name: "Key Object Selection", extensible: false,
        root: root(.group(7010, baseline: false), [
            .optional("HAS CONCEPT MOD", "CODE", .code(DICOMSRCodes.documentTitleModifier), many: true),
            language,
        ] + observerContext + [
            .optional("CONTAINS", "TEXT", .code(DICOMSRCodes.keyObjectDescription)),
            Row("CONTAINS", ["IMAGE", "WAVEFORM", "COMPOSITE"], .any, 1, nil, .mandatory),
        ]))

    /// TID 1500 Measurement Report with TID 1501 groups.
    public static let measurementReport: DICOMSRTemplate = {
        let group = container(dcm("125007", "Measurement Group"), 1, nil, .mandatory, [
            item("TEXT", dcm("112039", "Tracking Identifier"), "HAS OBS CONTEXT"),
            item("UIDREF", dcm("112040", "Tracking Unique Identifier"), "HAS OBS CONTEXT"),
            .optional("CONTAINS", "CODE", .code(dcm("121071", "Finding"))),
            .optional("HAS CONCEPT MOD", "CODE", .code(DICOMCode("363698007", scheme: "SCT", meaning: "Finding Site"))),
            .optional("CONTAINS", "NUM", .any, many: true),
        ])
        return DICOMSRTemplate(identifier: "1500", name: "Measurement Report", root: root(.code(dcm("126000", "Imaging Measurement Report")),
            [language] + observerContext + [
                item("CODE", DICOMSRCodes.procedureReported, "HAS CONCEPT MOD", 1, nil),
                container(dcm("111028", "Image Library"), 0, 1, .userOption, []),
                container(dcm("126010", "Imaging Measurements"), 0, 1, .mandatoryConditional, [group]),
            ]))
    }()

    /// TID 10011 CT Radiation Dose, with TID 10012 and 10013.
    public static let ctRadiationDose: DICOMSRTemplate = {
        typealias C = DICOMRadiationDoseReport.Codes
        let source = container(C.ctXRaySourceParameters, 1, nil, .mandatory, [
            item("TEXT", C.identificationOfTheXRaySource), item("NUM", C.kvp), item("NUM", C.maximumXRayTubeCurrent),
            item("NUM", C.xRayTubeCurrent), item("NUM", C.exposureTimePerRotation, "CONTAINS", 0, 1, .mandatoryConditional),
        ])
        let acquisition = container(C.ctAcquisition, 1, nil, .mandatory, [
            item("TEXT", C.acquisitionProtocol, "CONTAINS", 0, 1, .userOption),
            item("CODE", C.targetRegion, valueGroup: 4030),
            item("CODE", C.ctAcquisitionType, valueGroup: 10013),
            item("UIDREF", C.irradiationEventUID),
            container(C.ctAcquisitionParameters, 1, 1, .mandatory, [
                item("NUM", C.exposureTime), item("NUM", C.scanningLength), item("NUM", C.nominalSingleCollimationWidth),
                item("NUM", C.nominalTotalCollimationWidth), item("NUM", C.pitchFactor, "CONTAINS", 0, 1, .mandatoryConditional),
                item("NUM", C.numberOfXRaySources), source,
            ]),
            container(C.ctDose, 0, 1, .mandatoryConditional, [
                item("NUM", C.meanCTDIvol), item("CODE", C.ctdiwPhantomType, valueGroup: 4052), item("NUM", C.dlp),
            ]),
        ])
        return DICOMSRTemplate(identifier: "10011", name: "CT Radiation Dose", root: root(.code(C.xRayRadiationDoseReport),
            [language] + observerContext + [
                item("CODE", DICOMSRCodes.procedureReported, "HAS CONCEPT MOD"),
                .optional("HAS OBS CONTEXT", "CODE", .code(C.deviceRoleInProcedure), many: true),
                item("DATETIME", C.startOfXRayIrradiation), item("DATETIME", C.endOfXRayIrradiation),
                item("CODE", C.scopeOfAccumulation, valueGroup: 10000, "HAS ACQ CONTEXT"),
                container(C.ctAccumulatedDoseData, 1, 1, .mandatory, [
                    item("NUM", C.totalNumberOfIrradiationEvents), item("NUM", C.ctDoseLengthProductTotal),
                    item("NUM", C.ctEffectiveDoseTotal, "CONTAINS", 0, 1, .userOption),
                ]),
                acquisition,
                .optional("CONTAINS", "CODE", .code(C.sourceOfDoseInformation), valueGroup: 10021, many: true),
            ]))
    }()

    /// TID 10001 Projection X-Ray Radiation Dose, with TID 10002 and 10003.
    public static let projectionXRayRadiationDose: DICOMSRTemplate = {
        typealias C = DICOMRadiationDoseReport.Codes
        return DICOMSRTemplate(identifier: "10001", name: "Projection X-Ray Radiation Dose", root: root(.code(C.xRayRadiationDoseReport),
            [language] + observerContext + [
                item("CODE", DICOMSRCodes.procedureReported, "HAS CONCEPT MOD"),
                container(C.accumulatedXRayDoseData, 1, nil, .mandatory, [item("CODE", C.irradiationEventXRayData.with("113764", "Acquisition Plane"), valueGroup: 10003)]),
                container(C.irradiationEventXRayData, 0, nil, .userOption, [
                    item("UIDREF", C.irradiationEventUID), item("DATETIME", C.dateTimeStarted),
                    item("CODE", C.irradiationEventType, valueGroup: 10002),
                ]),
            ]))
    }()

    /// TID 10021 Radiopharmaceutical Radiation Dose, with TID 10022.
    public static let radiopharmaceuticalRadiationDose: DICOMSRTemplate = {
        typealias C = DICOMRadiationDoseReport.Codes
        return DICOMSRTemplate(identifier: "10021", name: "Radiopharmaceutical Radiation Dose",
            root: root(.code(C.radiopharmaceuticalRadiationDoseReport), [language] + observerContext + [
                container(C.radiopharmaceuticalAdministration, 1, nil, .mandatory, [
                    item("UIDREF", C.administrationEventUID), item("NUM", C.administeredActivity),
                ]),
            ]))
    }()

    /// TID 10030 Patient Radiation Dose: the title only is checked.
    public static let patientRadiationDose = DICOMSRTemplate(identifier: "10030", name: "Patient Radiation Dose",
        root: root(.code(DICOMRadiationDoseReport.Codes.patientRadiationDoseReport), [language] + observerContext))

    static func cad(_ identifier: String, _ name: String, _ title: DICOMCode) -> DICOMSRTemplate {
        DICOMSRTemplate(identifier: identifier, name: name, root: root(.code(title), [language] + observerContext + [
            item("CODE", DICOMCADReport.Codes.summary, valueGroup: 6047),
            container(dcm("111028", "Image Library"), 1, 1, .mandatory, []),
        ]))
    }

    /// TID 4000 Mammography CAD: top-level rows.
    public static let mammographyCAD = cad("4000", "Mammography CAD Document Root", DICOMCADReport.Codes.mammographyCADReport)
    /// TID 4100 Chest CAD: top-level rows.
    public static let chestCAD = cad("4100", "Chest CAD Document Root", DICOMCADReport.Codes.chestCADReport)

    static func ultrasound(_ identifier: String, _ name: String, _ title: DICOMCode) -> DICOMSRTemplate {
        DICOMSRTemplate(identifier: identifier, name: name, root: root(.code(title), [language] + observerContext))
    }

    /// TID 5000 OB-GYN Ultrasound Procedure Report: the title is checked.
    public static let obstetricGynecologicUltrasound = ultrasound("5000", "OB-GYN Ultrasound Procedure Report",
                                                                  DICOMUltrasoundReport.Codes.obstetricGynecologicReport)
    /// TID 5100 Vascular Ultrasound Report: the title is checked.
    public static let vascularUltrasound = ultrasound("5100", "Vascular Ultrasound Report", DICOMUltrasoundReport.Codes.vascularReport)
    /// TID 5200 Echocardiography Procedure Report: the title is checked.
    public static let echocardiography = ultrasound("5200", "Echocardiography Procedure Report",
                                                    DICOMUltrasoundReport.Codes.echocardiographyReport)
}

extension DICOMCode {
    /// Another code of the same scheme.
    func with(_ value: String, _ meaning: String) -> DICOMCode { DICOMCode(value, scheme: scheme, meaning: meaning) }
}
