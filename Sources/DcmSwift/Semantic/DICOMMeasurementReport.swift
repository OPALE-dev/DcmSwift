import Foundation

/// A Measurement Report, PS3.16 TID 1500, with Measurement Groups of TID
/// 1501 (measurements not tied to a region): the report most quantitative
/// imaging results use.
public struct DICOMMeasurementReport: Sendable {
    /// A measurement of TID 300: a concept, a value, and UCUM units.
    public struct Measurement: Sendable {
        public var concept: DICOMCode
        public var value: Double
        public var units: DICOMCode

        public init(concept: DICOMCode, value: Double, units: DICOMCode) {
            self.concept = concept
            self.value = value
            self.units = units
        }
    }

    /// A Measurement Group of TID 1501.
    public struct Group: Sendable {
        /// Tracking Identifier (112039, DCM), human readable.
        public var trackingIdentifier: String
        /// Tracking Unique Identifier (112040, DCM).
        public var trackingUID: String
        /// Finding (121071, DCM).
        public var finding: DICOMCode?
        /// Finding Site (363698007, SCT).
        public var findingSite: DICOMCode?
        public var measurements: [Measurement]

        /// A new Tracking Unique Identifier is made when none is given.
        public init(trackingIdentifier: String, trackingUID: String? = nil,
                    finding: DICOMCode? = nil, findingSite: DICOMCode? = nil, measurements: [Measurement]) {
            self.trackingIdentifier = trackingIdentifier
            self.trackingUID = trackingUID ?? DICOMEncapsulatedDocument.newUID()
            self.finding = finding
            self.findingSite = findingSite
            self.measurements = measurements
        }
    }

    /// Procedure reported (121058, DCM), such as (77477000, SCT, "CT").
    public var procedure: DICOMCode
    /// Person Observer Name (121008, DCM).
    public var observerName: String
    /// The images measured, in the Image Library (111028, DCM).
    public var images: [DICOMSRReference]
    public var groups: [Group]
    /// Language of Content Item and Descendants (121049, DCM).
    public var language = DICOMCode("en-US", scheme: "RFC5646", meaning: "English (United States)")

    public init(procedure: DICOMCode, observerName: String, images: [DICOMSRReference] = [], groups: [Group]) {
        self.procedure = procedure
        self.observerName = observerName
        self.images = images
        self.groups = groups
    }

    static let report = DICOMCode("126000", scheme: "DCM", meaning: "Imaging Measurement Report")
    static let languageConcept = DICOMCode("121049", scheme: "DCM", meaning: "Language of Content Item and Descendants")
    static let observerType = DICOMCode("121005", scheme: "DCM", meaning: "Observer Type")
    static let person = DICOMCode("121006", scheme: "DCM", meaning: "Person")
    static let observerNameConcept = DICOMCode("121008", scheme: "DCM", meaning: "Person Observer Name")
    static let procedureReported = DICOMCode("121058", scheme: "DCM", meaning: "Procedure reported")
    static let imageLibrary = DICOMCode("111028", scheme: "DCM", meaning: "Image Library")
    static let imageLibraryGroup = DICOMCode("126200", scheme: "DCM", meaning: "Image Library Group")
    static let imagingMeasurements = DICOMCode("126010", scheme: "DCM", meaning: "Imaging Measurements")
    static let measurementGroup = DICOMCode("125007", scheme: "DCM", meaning: "Measurement Group")
    static let trackingIdentifierConcept = DICOMCode("112039", scheme: "DCM", meaning: "Tracking Identifier")
    static let trackingUIDConcept = DICOMCode("112040", scheme: "DCM", meaning: "Tracking Unique Identifier")
    static let findingConcept = DICOMCode("121071", scheme: "DCM", meaning: "Finding")
    static let findingSiteConcept = DICOMCode("363698007", scheme: "SCT", meaning: "Finding Site")

    /// The SR document of the report.
    public func document() -> DICOMStructuredReport {
        var children: [DICOMSRContentItem] = [
            DICOMSRContentItem("HAS CONCEPT MOD", Self.languageConcept, .code(language)),
            DICOMSRContentItem("HAS OBS CONTEXT", Self.observerType, .code(Self.person)),
            DICOMSRContentItem("HAS OBS CONTEXT", Self.observerNameConcept, .personName(observerName)),
            DICOMSRContentItem("HAS CONCEPT MOD", Self.procedureReported, .code(procedure)),
        ]
        if !images.isEmpty {
            children.append(DICOMSRContentItem("CONTAINS", Self.imageLibrary, .container(continuity: "SEPARATE"), children: [
                DICOMSRContentItem("CONTAINS", Self.imageLibraryGroup, .container(continuity: "SEPARATE"),
                                   children: images.map { DICOMSRContentItem("CONTAINS", nil, .image($0)) }),
            ]))
        }
        children.append(DICOMSRContentItem("CONTAINS", Self.imagingMeasurements, .container(continuity: "SEPARATE"),
                                           children: groups.map { group in
            var items = [
                DICOMSRContentItem("HAS OBS CONTEXT", Self.trackingIdentifierConcept, .text(group.trackingIdentifier)),
                DICOMSRContentItem("HAS OBS CONTEXT", Self.trackingUIDConcept, .uidReference(group.trackingUID)),
            ]
            if let finding = group.finding {
                items.append(DICOMSRContentItem("CONTAINS", Self.findingConcept, .code(finding)))
            }
            if let site = group.findingSite {
                items.append(DICOMSRContentItem("HAS CONCEPT MOD", Self.findingSiteConcept, .code(site)))
            }
            items += group.measurements.map {
                DICOMSRContentItem("CONTAINS", $0.concept, .number($0.value, units: $0.units, qualifier: nil))
            }
            return DICOMSRContentItem("CONTAINS", Self.measurementGroup, .container(continuity: "SEPARATE"), children: items)
        }))
        return DICOMStructuredReport(
            template: (mappingResource: "DCMR", identifier: "1500"),
            root: DICOMSRContentItem(nil, Self.report, .container(continuity: "SEPARATE"), children: children))
    }

    /// Reads a TID 1500 report back: its procedure, observer, images, and
    /// TID 1501 Measurement Groups.
    public init?(document: DICOMStructuredReport) {
        let root = document.root
        guard root.conceptName?.sameConcept(as: Self.report) == true else { return nil }
        func code(_ item: DICOMSRContentItem?) -> DICOMCode? {
            if case .code(let code)? = item?.value { return code }
            return nil
        }
        procedure = code(root.children(named: Self.procedureReported).first) ?? DICOMCode("", scheme: "", meaning: "")
        if case .personName(let name)? = root.children(named: Self.observerNameConcept).first?.value {
            observerName = name
        } else {
            observerName = ""
        }
        language = code(root.children(named: Self.languageConcept).first) ?? language
        images = root.children(named: Self.imageLibrary).flatMap(\.children).flatMap(\.children).compactMap {
            if case .image(let reference) = $0.value { return reference }
            return nil
        }
        groups = root.children(named: Self.imagingMeasurements).flatMap { $0.children(named: Self.measurementGroup) }.map { group in
            var identifier = "", uid = ""
            if case .text(let text)? = group.children(named: Self.trackingIdentifierConcept).first?.value { identifier = text }
            if case .uidReference(let value)? = group.children(named: Self.trackingUIDConcept).first?.value { uid = value }
            let measurements = group.children.compactMap { item -> Measurement? in
                guard let concept = item.conceptName, case .number(let value?, let units?, _) = item.value else { return nil }
                return Measurement(concept: concept, value: value, units: units)
            }
            return Group(trackingIdentifier: identifier, trackingUID: uid,
                         finding: code(group.children(named: Self.findingConcept).first),
                         findingSite: code(group.children(named: Self.findingSiteConcept).first), measurements: measurements)
        }
    }
}
