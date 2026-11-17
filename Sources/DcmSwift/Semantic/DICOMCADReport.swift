import Foundation

/// A coded modifier of a content item: a HAS CONCEPT MOD or HAS PROPERTIES
/// child with a code, such as Finding Site or Laterality.
public struct DICOMSRModifier: Sendable, Equatable {
    public var concept: DICOMCode
    public var value: DICOMCode

    public init(concept: DICOMCode, value: DICOMCode) {
        self.concept = concept
        self.value = value
    }
}

/// A Computer Aided Detection report read back: Mammography CAD (PS3.16 TID
/// 4000) or Chest CAD (TID 4100). The reader keeps the processing summary,
/// the algorithms, and the findings with their rendering intent, certainty,
/// and coordinates; it does not make CAD reports.
public struct DICOMCADReport: Sendable {
    public enum Kind: String, Sendable { case mammography, chest }

    /// A spatial coordinate of a finding and the image it was selected from.
    public struct Location: Sendable, Equatable {
        /// Concept of the coordinate, such as (111010, DCM, "Center") or (111041, DCM, "Outline").
        public var concept: DICOMCode?
        public var graphicType: String
        public var points: [Double]
        public var image: DICOMSRReference?
    }

    /// A Single Image Finding (111059) or a Composite Feature (111015).
    public struct Finding: Sendable, Equatable {
        public var composite: Bool
        /// The finding type, such as (4147007, SCT, "Mass").
        public var type: DICOMCode
        /// Rendering Intent (111056), CID 6034.
        public var renderingIntent: DICOMCode?
        /// Certainty of Finding (111012), 0 to 100.
        public var certainty: Double?
        public var locations: [Location]
        /// For a composite feature, the single image findings it groups.
        public var components: [Finding]
        public var modifiers: [DICOMSRModifier]
    }

    /// An algorithm of the report: Algorithm Name (111001), Algorithm Version (111003).
    public struct Algorithm: Sendable, Hashable {
        public var name: String
        public var version: String
    }

    public enum Codes {
        static let dcm = DICOMSRCodes.dcm
        public static let mammographyCADReport = dcm("111036", "Mammography CAD Report")
        public static let chestCADReport = dcm("112000", "Chest CAD Report")
        public static let summary = dcm("111017", "CAD Processing and Findings Summary")
        public static let singleImageFinding = dcm("111059", "Single Image Finding")
        public static let compositeFeature = dcm("111015", "Composite Feature")
        public static let renderingIntent = dcm("111056", "Rendering Intent")
        public static let certaintyOfFinding = dcm("111012", "Certainty of Finding")
        public static let algorithmName = dcm("111001", "Algorithm Name")
        public static let algorithmVersion = dcm("111003", "Algorithm Version")
    }

    public var kind: Kind
    /// CAD Processing and Findings Summary, CID 6047, such as "All algorithms succeeded; with findings".
    public var summary: DICOMCode?
    public var algorithms: [Algorithm]
    /// The findings at the top: composite features with their components, and
    /// single image findings that belong to no composite feature.
    public var findings: [Finding]

    /// Reads a CAD report: a document declaring TID 4000 or 4100, or whose
    /// root is a Mammography or Chest CAD Report.
    public init?(document: DICOMStructuredReport) {
        let root = document.root
        switch (document.template?.identifier, root.conceptName) {
        case ("4000", _): kind = .mammography
        case ("4100", _): kind = .chest
        case (_, let title?) where title.sameConcept(as: Codes.mammographyCADReport): kind = .mammography
        case (_, let title?) where title.sameConcept(as: Codes.chestCADReport): kind = .chest
        default: return nil
        }
        let all = root.flattened().map(\.item)
        summary = all.first { $0.conceptName?.sameConcept(as: Codes.summary) == true }.flatMap {
            if case .code(let code) = $0.value { return code }
            return nil
        }
        var algorithms: [Algorithm] = [], seen = Set<Algorithm>()
        for item in all {
            guard let name = item.text(of: Codes.algorithmName) else { continue }
            let algorithm = Algorithm(name: name, version: item.text(of: Codes.algorithmVersion) ?? "")
            if seen.insert(algorithm).inserted { algorithms.append(algorithm) }
        }
        self.algorithms = algorithms

        func isFinding(_ item: DICOMSRContentItem) -> Bool {
            guard let concept = item.conceptName, case .code = item.value else { return false }
            return concept.sameConcept(as: Codes.singleImageFinding) || concept.sameConcept(as: Codes.compositeFeature)
        }
        func finding(_ item: DICOMSRContentItem) -> Finding {
            guard case .code(let type) = item.value else { preconditionFailure() }
            var certainty: Double?
            if case .number(let value?, _, _)? = item.children(named: Codes.certaintyOfFinding).first?.value { certainty = value }
            let locations = item.children.compactMap { child -> Location? in
                guard case .spatialCoordinates(let graphicType, let points) = child.value else { return nil }
                let image = child.children.compactMap { grandchild -> DICOMSRReference? in
                    if case .image(let reference) = grandchild.value { return reference }
                    return nil
                }.first
                return Location(concept: child.conceptName, graphicType: graphicType, points: points, image: image)
            }
            let modifiers = item.children.compactMap { child -> DICOMSRModifier? in
                guard ["HAS CONCEPT MOD", "HAS PROPERTIES"].contains(child.relationship ?? ""), let concept = child.conceptName,
                      !concept.sameConcept(as: Codes.renderingIntent), case .code(let value) = child.value else { return nil }
                return DICOMSRModifier(concept: concept, value: value)
            }
            return Finding(composite: item.conceptName?.sameConcept(as: Codes.compositeFeature) == true, type: type,
                           renderingIntent: item.code(of: Codes.renderingIntent), certainty: certainty, locations: locations,
                           components: item.children.filter(isFinding).map(finding), modifiers: modifiers)
        }
        // Findings nested in a composite feature are listed under it only.
        var top: [DICOMSRContentItem] = []
        func walk(_ item: DICOMSRContentItem) {
            for child in item.children {
                if isFinding(child) { top.append(child) } else { walk(child) }
            }
        }
        walk(root)
        findings = top.map(finding)
    }
}

/// The measurements of an ultrasound procedure report: OB-GYN (PS3.16 TID
/// 5000), vascular (TID 5100), or adult echocardiography (TID 5200). Each
/// numeric value keeps the containers it sits in and the coded modifiers in
/// effect, such as Finding Site, Laterality, Derivation, or Measurement
/// Method; the nearest modifier of a concept wins.
public struct DICOMUltrasoundReport: Sendable {
    public enum Kind: String, Sendable { case obstetricGynecologic, vascular, echocardiography }

    public struct Measurement: Sendable, Equatable {
        public var concept: DICOMCode
        public var value: Double
        public var units: DICOMCode?
        /// The concepts of the containers from the root's child down, such as
        /// "Fetal Biometry" then "Biometry Group".
        public var path: [DICOMCode]
        public var modifiers: [DICOMSRModifier]

        /// The value of a modifier, such as Laterality.
        public func modifier(_ concept: DICOMCode) -> DICOMCode? {
            modifiers.first { $0.concept.sameConcept(as: concept) }?.value
        }
    }

    public enum Codes {
        static let dcm = DICOMSRCodes.dcm
        public static let obstetricGynecologicReport = dcm("125000", "OB-GYN Ultrasound Procedure Report")
        public static let vascularReport = dcm("125100", "Vascular Ultrasound Procedure Report")
        public static let echocardiographyReport = dcm("125200", "Adult Echocardiography Procedure Report")
        public static let findingSite = DICOMCode("363698007", scheme: "SCT", meaning: "Finding Site")
        public static let laterality = DICOMCode("272741003", scheme: "SCT", meaning: "Laterality")
        public static let derivation = dcm("121401", "Derivation")
    }

    public var kind: Kind
    public var observers: [DICOMSRObserver]
    public var measurements: [Measurement]

    public init?(document: DICOMStructuredReport) {
        let root = document.root
        switch (document.template?.identifier, root.conceptName) {
        case ("5000", _): kind = .obstetricGynecologic
        case ("5100", _): kind = .vascular
        case ("5200", _): kind = .echocardiography
        case (_, let title?) where title.sameConcept(as: Codes.obstetricGynecologicReport): kind = .obstetricGynecologic
        case (_, let title?) where title.sameConcept(as: Codes.vascularReport): kind = .vascular
        case (_, let title?) where title.sameConcept(as: Codes.echocardiographyReport): kind = .echocardiography
        default: return nil
        }
        observers = DICOMSRObserver.read(root)
        func modifiers(_ item: DICOMSRContentItem) -> [DICOMSRModifier] {
            item.children.compactMap { child in
                guard ["HAS CONCEPT MOD", "HAS PROPERTIES", "HAS ACQ CONTEXT"].contains(child.relationship ?? ""),
                      let concept = child.conceptName, case .code(let value) = child.value else { return nil }
                return DICOMSRModifier(concept: concept, value: value)
            }
        }
        var measurements: [Measurement] = []
        func walk(_ item: DICOMSRContentItem, path: [DICOMCode], inherited: [DICOMSRModifier]) {
            for child in item.children {
                switch child.value {
                case .container:
                    let own = modifiers(child)
                    walk(child, path: path + [child.conceptName].compactMap { $0 },
                         inherited: own + inherited.filter { old in !own.contains { $0.concept.sameConcept(as: old.concept) } })
                case .number(let value?, let units, _):
                    guard let concept = child.conceptName else { continue }
                    let own = modifiers(child)
                    measurements.append(Measurement(concept: concept, value: value, units: units, path: path,
                        modifiers: own + inherited.filter { old in !own.contains { $0.concept.sameConcept(as: old.concept) } }))
                default: break
                }
            }
        }
        walk(root, path: [], inherited: modifiers(root))
        self.measurements = measurements
    }
}
