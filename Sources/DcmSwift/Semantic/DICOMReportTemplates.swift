import Foundation

// PS3.16 templates shared by reports: Observer Context (TID 1002, 1003,
// 1004), Language (TID 1204), the Basic Diagnostic Imaging Report (TID 2000,
// 2002) and Key Object Selection (TID 2010).

/// Codes of the DICOM Controlled Terminology (PS3.16 Annex D) used by the
/// report templates. Meanings are those of the terminology resource.
public enum DICOMSRCodes {
    static func dcm(_ value: String, _ meaning: String) -> DICOMCode { DICOMCode(value, scheme: "DCM", meaning: meaning) }

    public static let language = dcm("121049", "Language of Content Item and Descendants")
    public static let observerType = dcm("121005", "Observer Type")
    public static let person = dcm("121006", "Person")
    public static let device = dcm("121007", "Device")
    public static let personObserverName = dcm("121008", "Person Observer Name")
    public static let personObserverOrganization = dcm("121009", "Person Observer's Organization Name")
    public static let personObserverRoleInOrganization = dcm("121010", "Person Observer's Role in the Organization")
    public static let personObserverRoleInProcedure = dcm("121011", "Person Observer's Role in this Procedure")
    public static let deviceObserverUID = dcm("121012", "Device Observer UID")
    public static let deviceObserverName = dcm("121013", "Device Observer Name")
    public static let deviceObserverManufacturer = dcm("121014", "Device Observer Manufacturer")
    public static let deviceObserverModelName = dcm("121015", "Device Observer Model Name")
    public static let deviceObserverSerialNumber = dcm("121016", "Device Observer Serial Number")
    public static let procedureReported = dcm("121058", "Procedure reported")
    public static let documentTitleModifier = dcm("113011", "Document Title Modifier")
    public static let keyObjectDescription = dcm("113012", "Key Object Description")
}

/// The observer of a report or of a part of it: Observer Context, TID 1002
/// (a person, TID 1003, or a device, TID 1004).
public enum DICOMSRObserver: Sendable, Equatable {
    case person(name: String, organization: String? = nil, role: DICOMCode? = nil)
    case device(uid: String, name: String? = nil, manufacturer: String? = nil, model: String? = nil, serialNumber: String? = nil)

    /// The HAS OBS CONTEXT items of the observer.
    public var items: [DICOMSRContentItem] {
        func item(_ concept: DICOMCode, _ value: DICOMSRContentItem.Value) -> DICOMSRContentItem {
            DICOMSRContentItem("HAS OBS CONTEXT", concept, value)
        }
        switch self {
        case .person(let name, let organization, let role):
            var items = [item(DICOMSRCodes.observerType, .code(DICOMSRCodes.person)),
                         item(DICOMSRCodes.personObserverName, .personName(name))]
            if let organization, !organization.isEmpty { items.append(item(DICOMSRCodes.personObserverOrganization, .text(organization))) }
            if let role { items.append(item(DICOMSRCodes.personObserverRoleInProcedure, .code(role))) }
            return items
        case .device(let uid, let name, let manufacturer, let model, let serial):
            var items = [item(DICOMSRCodes.observerType, .code(DICOMSRCodes.device)),
                         item(DICOMSRCodes.deviceObserverUID, .uidReference(uid))]
            for (concept, text) in [(DICOMSRCodes.deviceObserverName, name), (DICOMSRCodes.deviceObserverManufacturer, manufacturer),
                                    (DICOMSRCodes.deviceObserverModelName, model), (DICOMSRCodes.deviceObserverSerialNumber, serial)] {
                if let text, !text.isEmpty { items.append(item(concept, .text(text))) }
            }
            return items
        }
    }

    /// Reads the observers of a container's HAS OBS CONTEXT children, in
    /// order: a new observer starts at each Observer Type or, without one,
    /// at each Person Observer Name or Device Observer UID.
    public static func read(_ container: DICOMSRContentItem) -> [DICOMSRObserver] {
        var observers: [DICOMSRObserver] = []
        var current: DICOMSRObserver?
        var typed = false
        func flush() { if let current { observers.append(current) }; current = nil; typed = false }
        for child in container.children where child.relationship == "HAS OBS CONTEXT" {
            guard let concept = child.conceptName else { continue }
            switch (concept, child.value) {
            case (_, .code(let type)) where concept.sameConcept(as: DICOMSRCodes.observerType):
                flush()
                typed = true
                current = type.sameConcept(as: DICOMSRCodes.device) ? .device(uid: "") : .person(name: "")
            case (_, .personName(let name)) where concept.sameConcept(as: DICOMSRCodes.personObserverName):
                if case .person(let previous, let organization, let role)? = current, previous.isEmpty, typed || current != nil {
                    current = .person(name: name, organization: organization, role: role)
                } else {
                    flush()
                    current = .person(name: name)
                }
            case (_, .text(let text)) where concept.sameConcept(as: DICOMSRCodes.personObserverOrganization):
                if case .person(let name, _, let role)? = current { current = .person(name: name, organization: text, role: role) }
            case (_, .code(let role)) where concept.sameConcept(as: DICOMSRCodes.personObserverRoleInProcedure):
                if case .person(let name, let organization, _)? = current { current = .person(name: name, organization: organization, role: role) }
            case (_, .uidReference(let uid)) where concept.sameConcept(as: DICOMSRCodes.deviceObserverUID):
                if case .device(let previous, let n, let m, let model, let s)? = current, previous.isEmpty {
                    current = .device(uid: uid, name: n, manufacturer: m, model: model, serialNumber: s)
                } else {
                    flush()
                    current = .device(uid: uid)
                }
            case (_, .text(let text)):
                if case .device(let uid, var name, var manufacturer, var model, var serial)? = current {
                    if concept.sameConcept(as: DICOMSRCodes.deviceObserverName) { name = text }
                    if concept.sameConcept(as: DICOMSRCodes.deviceObserverManufacturer) { manufacturer = text }
                    if concept.sameConcept(as: DICOMSRCodes.deviceObserverModelName) { model = text }
                    if concept.sameConcept(as: DICOMSRCodes.deviceObserverSerialNumber) { serial = text }
                    current = .device(uid: uid, name: name, manufacturer: manufacturer, model: model, serialNumber: serial)
                }
            default: break
            }
        }
        flush()
        return observers
    }
}

extension DICOMSRContentItem {
    /// The value of the first child with this concept name, when it is a code.
    func code(of concept: DICOMCode) -> DICOMCode? {
        if case .code(let code)? = children(named: concept).first?.value { return code }
        return nil
    }

    /// The value of the first child with this concept name, when it is text.
    func text(of concept: DICOMCode) -> String? {
        if case .text(let text)? = children(named: concept).first?.value { return text }
        return nil
    }
}

/// A Basic Diagnostic Imaging Report, PS3.16 TID 2000: a coded title, the
/// observation context, and narrative sections (TID 2002) whose headings come
/// from CID 7001 and whose observations come from CID 7002.
public struct DICOMDiagnosticImagingReport: Sendable {
    /// An image an observation or a section refers to, with its purpose of
    /// reference (CID 7003), such as "Best illustration of finding".
    public struct Image: Sendable, Equatable {
        public var purpose: DICOMCode?
        public var reference: DICOMSRReference

        public init(purpose: DICOMCode? = nil, reference: DICOMSRReference) {
            self.purpose = purpose
            self.reference = reference
        }
    }

    /// A report element: a text or a coded observation (CID 7002), with the
    /// images it is inferred from.
    public struct Observation: Sendable, Equatable {
        public enum Value: Sendable, Equatable {
            case text(String)
            case code(DICOMCode)
            /// A person, such as the one who authorised the irradiation (TID 2008).
            case personName(String)
            /// DICOM DA, TM and DT values, such as the study date (TID 2007).
            case date(String)
            case time(String)
            case dateTime(String)
        }

        public var concept: DICOMCode
        public var value: Value
        public var inferredFrom: [Image]

        public init(concept: DICOMCode, value: Value, inferredFrom: [Image] = []) {
            self.concept = concept
            self.value = value
            self.inferredFrom = inferredFrom
        }

        /// A text observation.
        public static func text(_ text: String, concept: DICOMCode) -> Observation {
            Observation(concept: concept, value: .text(text))
        }
    }

    /// A section of the report narrative: a heading of CID 7001.
    public struct Section: Sendable, Equatable {
        public var heading: DICOMCode
        /// Observer of this section, when not the report's.
        public var observer: DICOMSRObserver?
        public var observations: [Observation]
        public var images: [Image]

        public init(heading: DICOMCode, observer: DICOMSRObserver? = nil, observations: [Observation], images: [Image] = []) {
            self.heading = heading
            self.observer = observer
            self.observations = observations
            self.images = images
        }
    }

    /// Document title, CID 7000, such as (18748-4, LN, "Diagnostic Imaging Report").
    public var title: DICOMCode
    /// Language of Content Item and Descendants (TID 1204), such as (fr-FR, RFC5646, "French (France)").
    public var language: DICOMCode?
    /// Observer Context (TID 1002): the report's observers.
    public var observers: [DICOMSRObserver]
    /// Procedures reported (121058, DCM), such as (77477000, SCT, "CT").
    public var procedures: [DICOMCode]
    public var sections: [Section]

    public init(title: DICOMCode = Headings.diagnosticImagingReport, language: DICOMCode? = nil,
                observers: [DICOMSRObserver] = [], procedures: [DICOMCode] = [], sections: [Section]) {
        self.title = title
        self.language = language
        self.observers = observers
        self.procedures = procedures
        self.sections = sections
    }

    /// Codes of CID 7000 (titles), CID 7001 (headings), and CID 7002
    /// (elements) used most; any member of these groups may be used.
    public enum Headings {
        static func ln(_ value: String, _ meaning: String) -> DICOMCode { DICOMCode(value, scheme: "LN", meaning: meaning) }
        public static let diagnosticImagingReport = ln("18748-4", "Diagnostic Imaging Report")
        public static let radiologyReport = ln("11528-7", "Radiology Report")

        public static let history = ln("11329-0", "History")
        public static let request = ln("55115-0", "Request")
        public static let currentProcedureDescriptions = ln("55111-9", "Current Procedure Descriptions")
        public static let priorProcedureDescriptions = ln("55114-3", "Prior Procedure Descriptions")
        public static let previousFindings = ln("18834-2", "Previous Findings")
        public static let findings = ln("59776-5", "Findings")
        public static let impressions = ln("19005-8", "Impressions")
        public static let recommendations = ln("18783-1", "Recommendations")
        public static let conclusions = ln("55110-1", "Conclusions")
        public static let addendum = ln("55107-7", "Addendum")
        public static let indications = ln("18785-6", "Indications for Procedure")
        public static let patientPresentation = ln("55108-5", "Patient Presentation")
        public static let complications = ln("55109-3", "Complications")
        public static let summary = ln("55112-7", "Summary")
        public static let keyImages = ln("55113-5", "Key Images")
        public static let radiationExposure = ln("73569-6", "Radiation Exposure and Protection Information")
        public static let clinicalInformation = ln("55752-0", "Clinical Information")
        public static let medicationsAdministered = ln("29549-3", "Medications Administered")
        public static let criticalResults = ln("73568-8", "Communication of Critical Results")

        public static let procedureDescription = DICOMSRCodes.dcm("121065", "Procedure Description")
        public static let previousFinding = DICOMSRCodes.dcm("121069", "Previous Finding")
        public static let finding = DICOMSRCodes.dcm("121071", "Finding")
        public static let impression = DICOMSRCodes.dcm("121073", "Impression")
        public static let recommendation = DICOMSRCodes.dcm("121075", "Recommendation")
        public static let conclusion = DICOMSRCodes.dcm("121077", "Conclusion")
        public static let complicationOfProcedure = DICOMCode("116224001", scheme: "SCT", meaning: "Complication of Procedure")
    }

    /// The report element (CID 7002) that usually fills a section: Finding
    /// under Findings, Conclusion under Conclusions. Headings with no element
    /// of their own, such as Indications for Procedure, use the heading's
    /// concept (CID 7002 is extensible).
    public static func element(for heading: DICOMCode) -> DICOMCode {
        let pairs: [(DICOMCode, DICOMCode)] = [
            (Headings.history, Headings.history), (Headings.request, Headings.request),
            (Headings.currentProcedureDescriptions, Headings.procedureDescription),
            (Headings.priorProcedureDescriptions, Headings.procedureDescription),
            (Headings.previousFindings, Headings.previousFinding), (Headings.findings, Headings.finding),
            (Headings.impressions, Headings.impression), (Headings.recommendations, Headings.recommendation),
            (Headings.conclusions, Headings.conclusion), (Headings.complications, Headings.complicationOfProcedure),
            (Headings.patientPresentation, Headings.patientPresentation), (Headings.summary, Headings.summary),
        ]
        return pairs.first { $0.0.sameConcept(as: heading) }?.1 ?? heading
    }

    static let template = (mappingResource: "DCMR", identifier: "2000")

    /// The SR document of the report. Basic Text SR holds every content of
    /// TID 2000; Enhanced or Comprehensive SR may be asked for.
    public func document(sopClassUID: String = DICOMStructuredReport.basicTextSR, completionFlag: String = "COMPLETE",
                         verificationFlag: String = "UNVERIFIED") -> DICOMStructuredReport {
        func image(_ image: Image, relationship: String) -> DICOMSRContentItem {
            DICOMSRContentItem(relationship, image.purpose, .image(image.reference))
        }
        var children: [DICOMSRContentItem] = []
        if let language { children.append(DICOMSRContentItem("HAS CONCEPT MOD", DICOMSRCodes.language, .code(language))) }
        children += observers.flatMap(\.items)
        children += procedures.map { DICOMSRContentItem("HAS CONCEPT MOD", DICOMSRCodes.procedureReported, .code($0)) }
        children += sections.map { section in
            var items = section.observer?.items ?? []
            items += section.observations.map { observation in
                let value: DICOMSRContentItem.Value
                switch observation.value {
                case .text(let text): value = .text(text)
                case .code(let code): value = .code(code)
                case .personName(let name): value = .personName(name)
                case .date(let date): value = .date(date)
                case .time(let time): value = .time(time)
                case .dateTime(let dateTime): value = .dateTime(dateTime)
                }
                return DICOMSRContentItem("CONTAINS", observation.concept, value,
                                          children: observation.inferredFrom.map { image($0, relationship: "INFERRED FROM") })
            }
            items += section.images.map { image($0, relationship: "CONTAINS") }
            return DICOMSRContentItem("CONTAINS", section.heading, .container(continuity: "SEPARATE"), children: items)
        }
        return DICOMStructuredReport(sopClassUID: sopClassUID, completionFlag: completionFlag, verificationFlag: verificationFlag,
                                     template: Self.template,
                                     root: DICOMSRContentItem(nil, title, .container(continuity: "SEPARATE"), children: children))
    }

    /// Reads a TID 2000 report: a document declaring DCMR 2000, or whose
    /// title belongs to CID 7000.
    public init?(document: DICOMStructuredReport) {
        let root = document.root
        guard case .container = root.value, let title = root.conceptName else { return nil }
        // TID 2000, or TID 2006, which adds fixed sections and radiation exposure information (TID 2008).
        let declared = ["2000", "2006"].contains(document.template?.identifier ?? "")
        // Without a declared template, a title of CID 7000 is enough; a document that declares
        // another template (a cardiology or CAD report…) is not read as a diagnostic report.
        let titled = document.template == nil && DICOMTerminology.shared.membership(of: title, in: 7000) == .member
        guard declared || titled else { return nil }
        self.title = title
        language = root.code(of: DICOMSRCodes.language)
        observers = DICOMSRObserver.read(root)
        procedures = root.children(named: DICOMSRCodes.procedureReported).compactMap {
            if case .code(let code) = $0.value { return code }
            return nil
        }
        func image(_ item: DICOMSRContentItem) -> Image? {
            if case .image(let reference) = item.value { return Image(purpose: item.conceptName, reference: reference) }
            return nil
        }
        sections = root.children.filter { $0.relationship == "CONTAINS" }.compactMap { item -> Section? in
            guard case .container = item.value, let heading = item.conceptName else { return nil }
            let observations = item.children.filter { $0.relationship == "CONTAINS" }.compactMap { child -> Observation? in
                guard let concept = child.conceptName else { return nil }
                let inferred = child.children.filter { $0.relationship == "INFERRED FROM" }.compactMap(image)
                switch child.value {
                case .text(let text): return Observation(concept: concept, value: .text(text), inferredFrom: inferred)
                case .code(let code): return Observation(concept: concept, value: .code(code), inferredFrom: inferred)
                case .personName(let name): return Observation(concept: concept, value: .personName(name), inferredFrom: inferred)
                case .date(let date): return Observation(concept: concept, value: .date(date), inferredFrom: inferred)
                case .time(let time): return Observation(concept: concept, value: .time(time), inferredFrom: inferred)
                case .dateTime(let dateTime): return Observation(concept: concept, value: .dateTime(dateTime), inferredFrom: inferred)
                default: return nil
                }
            }
            return Section(heading: heading, observer: DICOMSRObserver.read(item).first, observations: observations,
                           images: item.children.filter { $0.relationship == "CONTAINS" }.compactMap(image))
        }
    }

    /// The narrative as plain text: each heading followed by its observations.
    public var text: String {
        sections.map { section in
            ([section.heading.meaning] + section.observations.map { observation in
                switch observation.value {
                case .text(let text): return text
                case .code(let code): return observation.concept.meaning + ": " + code.meaning
                case .personName(let name): return observation.concept.meaning + ": " + name.replacingOccurrences(of: "^", with: " ")
                case .date(let value), .time(let value), .dateTime(let value): return observation.concept.meaning + ": " + value
                }
            }).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

/// A Key Object Selection document, PS3.16 TID 2010: a selection of
/// instances with a title (CID 7010), such as "Of Interest" or "Rejected for
/// Quality Reasons", an optional modifier (CID 7011 and others), and a
/// description.
public struct DICOMKeyObjectSelection: Sendable {
    public enum Titles {
        public static let ofInterest = DICOMSRCodes.dcm("113000", "Of Interest")
        public static let rejectedForQualityReasons = DICOMSRCodes.dcm("113001", "Rejected for Quality Reasons")
        public static let forReferringProvider = DICOMSRCodes.dcm("113002", "For Referring Provider")
        public static let forSurgery = DICOMSRCodes.dcm("113003", "For Surgery")
        public static let forTeaching = DICOMSRCodes.dcm("113004", "For Teaching")
        public static let qualityIssue = DICOMSRCodes.dcm("113010", "Quality Issue")
        public static let rejectedForPatientSafetyReasons = DICOMSRCodes.dcm("113037", "Rejected for Patient Safety Reasons")
        public static let incorrectModalityWorklistEntry = DICOMSRCodes.dcm("113038", "Incorrect Modality Worklist Entry")
        public static let dataRetentionPolicyExpired = DICOMSRCodes.dcm("113039", "Data Retention Policy Expired")
    }

    /// Document title, CID 7010.
    public var title: DICOMCode
    /// Document Title Modifiers (113011, DCM), such as a CID 7011 reason.
    public var modifiers: [DICOMCode]
    public var language: DICOMCode?
    public var observers: [DICOMSRObserver]
    /// Key Object Description (113012, DCM).
    public var description: String?
    /// The instances selected; their study and series fill the evidence.
    public var references: [DICOMSRReference]

    public init(title: DICOMCode = Titles.ofInterest, modifiers: [DICOMCode] = [], language: DICOMCode? = nil,
                observers: [DICOMSRObserver] = [], description: String? = nil, references: [DICOMSRReference]) {
        self.title = title
        self.modifiers = modifiers
        self.language = language
        self.observers = observers
        self.description = description
        self.references = references
    }

    /// The KO document. Image Storage SOP Classes are referenced as IMAGE,
    /// waveforms as WAVEFORM, and the other instances as COMPOSITE.
    public func document() -> DICOMStructuredReport {
        var children = modifiers.map { DICOMSRContentItem("HAS CONCEPT MOD", DICOMSRCodes.documentTitleModifier, .code($0)) }
        if let language { children.append(DICOMSRContentItem("HAS CONCEPT MOD", DICOMSRCodes.language, .code(language))) }
        children += observers.flatMap(\.items)
        if let description, !description.isEmpty {
            children.append(DICOMSRContentItem("CONTAINS", DICOMSRCodes.keyObjectDescription, .text(description)))
        }
        children += references.map { reference in
            let value: DICOMSRContentItem.Value
            if reference.sopClassUID.hasPrefix("1.2.840.10008.5.1.4.1.1.9.") { value = .waveform(reference) }
            else if imageSOPClass(reference.sopClassUID) { value = .image(reference) }
            else { value = .composite(reference) }
            return DICOMSRContentItem("CONTAINS", nil, value)
        }
        return DICOMStructuredReport(sopClassUID: DICOMStructuredReport.keyObjectSelection, completionFlag: "", verificationFlag: "",
                                     template: (mappingResource: "DCMR", identifier: "2010"),
                                     root: DICOMSRContentItem(nil, title, .container(continuity: "SEPARATE"), children: children))
    }

    /// Reads a Key Object Selection document.
    public init?(document: DICOMStructuredReport) {
        let root = document.root
        guard document.isKeyObjectSelection || document.template?.identifier == "2010", let title = root.conceptName else { return nil }
        self.title = title
        modifiers = root.children(named: DICOMSRCodes.documentTitleModifier).compactMap {
            if case .code(let code) = $0.value { return code }
            return nil
        }
        language = root.code(of: DICOMSRCodes.language)
        observers = DICOMSRObserver.read(root)
        description = root.text(of: DICOMSRCodes.keyObjectDescription)
        // Content items carry no study or series: they come from the evidence.
        references = root.children.compactMap {
            switch $0.value {
            case .image(let reference), .composite(let reference), .waveform(let reference): return reference
            default: return nil
            }
        }
    }

    /// Fills the study and series of the references from the Current
    /// Requested Procedure Evidence Sequence of the KO instance.
    public mutating func locate(in dataSet: DataSet) {
        let evidence = DICOMStructuredReport.hierarchicalReferences(dataSet.element(forTagName: "CurrentRequestedProcedureEvidenceSequence"))
        for index in references.indices {
            if let found = evidence.first(where: { $0.sopInstanceUID == references[index].sopInstanceUID }) {
                references[index].studyInstanceUID = found.studyInstanceUID
                references[index].seriesInstanceUID = found.seriesInstanceUID
            }
        }
    }

    /// Image Storage SOP Classes, as opposed to SR, documents, presentation
    /// states, raw data, and other non-image objects.
    func imageSOPClass(_ uid: String) -> Bool {
        let prefix = "1.2.840.10008.5.1.4.1.1."
        guard uid.hasPrefix(prefix) else { return false }
        let rest = uid.dropFirst(prefix.count)
        return !["88.", "104.", "11.", "66", "9.", "481.", "200.", "90."].contains { rest.hasPrefix($0) }
    }
}
