import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A Basic Diagnostic Imaging Report (TID 2000) as an HL7 CDA Release 2
/// document, following the mapping of PS3.20: the report title and section
/// headings keep their LOINC codes, the sections carry the narrative and the
/// coded observations, and a DICOM Object Catalog section (121181, DCM)
/// lists the referenced study, series, and instances. The PS3.20 and C-CDA
/// template identifiers are not written, so the result is not claimed to
/// conform to those templates.
///
/// ``report(cda:)`` reads the sections of a CDA imaging report back into a
/// TID 2000 report: each paragraph of a section becomes a text observation.
public enum DICOMReportCDA {
    /// The patient of the document.
    public struct Patient: Sendable {
        public var id: String
        /// Issuer of the identifier: an OID becomes the id's root; any other
        /// value is kept as the assigning authority name.
        public var issuer: String
        /// DICOM Person Name, Family^Given.
        public var name: String
        /// DA, YYYYMMDD.
        public var birthDate: String
        /// M, F, or O.
        public var sex: String

        public init(id: String, issuer: String = "", name: String, birthDate: String = "", sex: String = "") {
            self.id = id
            self.issuer = issuer
            self.name = name
            self.birthDate = birthDate
            self.sex = sex
        }
    }

    public struct Header: Sendable {
        /// Document id, a UID.
        public var documentID: String
        /// DT, YYYYMMDDHHMMSS.
        public var effectiveTime: String
        public var patient: Patient
        public var custodian: String
        public var studyInstanceUID: String?
        public var accessionNumber: String?
        /// Set and version of a document that replaces an earlier one.
        public var setID: String?
        public var version: Int?

        public init(documentID: String, effectiveTime: String, patient: Patient, custodian: String,
                    studyInstanceUID: String? = nil, accessionNumber: String? = nil, setID: String? = nil, version: Int? = nil) {
            self.documentID = documentID
            self.effectiveTime = effectiveTime
            self.patient = patient
            self.custodian = custodian
            self.studyInstanceUID = studyInstanceUID
            self.accessionNumber = accessionNumber
            self.setID = setID
            self.version = version
        }
    }

    static let schemes: [String: String] = ["LN": "2.16.840.1.113883.6.1", "DCM": "1.2.840.10008.2.16.4",
                                            "SCT": "2.16.840.1.113883.6.96", "UCUM": "2.16.840.1.113883.6.8"]

    static func oid(_ scheme: String) -> String {
        schemes[scheme] ?? DICOMTerminology.shared.codingScheme(scheme)?.uid ?? scheme
    }

    static func scheme(_ oid: String) -> String {
        schemes.first { $0.value == oid }?.key ?? DICOMTerminology.shared.codingScheme(uid: oid)?.designator ?? oid
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func code(_ element: String, _ code: DICOMCode, extra: String = "") -> String {
        "<\(element)\(extra) code=\"\(escape(code.value))\" codeSystem=\"\(escape(oid(code.scheme)))\" codeSystemName=\"\(escape(code.scheme))\" displayName=\"\(escape(code.meaning))\"/>"
    }

    static func isOID(_ text: String) -> Bool { text.range(of: #"^[0-2](\.(0|[1-9][0-9]*))+$"#, options: .regularExpression) != nil }

    /// The CDA document of a report; `references` fill the DICOM Object Catalog.
    public static func document(_ report: DICOMDiagnosticImagingReport, header: Header, references: [DICOMSRReference] = []) -> String {
        let p = header.patient
        let name = p.name.split(separator: "^", omittingEmptySubsequences: false).map(String.init)
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ClinicalDocument xmlns="urn:hl7-org:v3" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <typeId root="2.16.840.1.113883.1.3" extension="POCD_HD000040"/>
        <id root="\(escape(header.documentID))"/>
        \(code("code", report.title))
        <title>\(escape(report.title.meaning))</title>
        <effectiveTime value="\(escape(header.effectiveTime))"/>
        <confidentialityCode code="N" codeSystem="2.16.840.1.113883.5.25"/>

        """
        if let language = report.language { xml += "<languageCode code=\"\(escape(language.value))\"/>\n" }
        if let setID = header.setID { xml += "<setId root=\"\(escape(setID))\"/>\n" }
        if let version = header.version { xml += "<versionNumber value=\"\(version)\"/>\n" }
        let id = isOID(p.issuer) ? "<id root=\"\(escape(p.issuer))\" extension=\"\(escape(p.id))\"/>"
            : "<id extension=\"\(escape(p.id))\"" + (p.issuer.isEmpty ? " nullFlavor=\"UNK\"" : " assigningAuthorityName=\"\(escape(p.issuer))\"") + "/>"
        xml += "<recordTarget><patientRole>\(id)<patient><name>"
        if name.count > 1 { xml += "<given>\(escape(name[1]))</given>" }
        xml += "<family>\(escape(name.first ?? ""))</family></name>"
        xml += ["M", "F"].contains(p.sex) ? "<administrativeGenderCode code=\"\(p.sex)\" codeSystem=\"2.16.840.1.113883.5.1\"/>"
            : "<administrativeGenderCode nullFlavor=\"UNK\"/>"
        xml += p.birthDate.isEmpty ? "<birthTime nullFlavor=\"UNK\"/>" : "<birthTime value=\"\(escape(p.birthDate))\"/>"
        xml += "</patient></patientRole></recordTarget>\n"
        // Authors: the person observers, else the device.
        let authors = report.observers.isEmpty ? [DICOMSRObserver.device(uid: "", name: header.custodian)] : report.observers
        for author in authors {
            xml += "<author><time value=\"\(escape(header.effectiveTime))\"/><assignedAuthor>"
            switch author {
            case .person(let name, let organization, _):
                let parts = name.split(separator: "^", omittingEmptySubsequences: false).map(String.init)
                xml += "<id nullFlavor=\"UNK\"/><assignedPerson><name>"
                if parts.count > 1 { xml += "<given>\(escape(parts[1]))</given>" }
                xml += "<family>\(escape(parts.first ?? ""))</family></name></assignedPerson>"
                if let organization { xml += "<representedOrganization><name>\(escape(organization))</name></representedOrganization>" }
            case .device(let uid, let name, let manufacturer, let model, _):
                xml += uid.isEmpty ? "<id nullFlavor=\"UNK\"/>" : "<id root=\"\(escape(uid))\"/>"
                xml += "<assignedAuthoringDevice>"
                if let manufacturer { xml += "<manufacturerModelName>\(escape(manufacturer + (model.map { " " + $0 } ?? "")))</manufacturerModelName>" }
                xml += "<softwareName>\(escape(name ?? ""))</softwareName></assignedAuthoringDevice>"
            }
            xml += "</assignedAuthor></author>\n"
        }
        xml += "<custodian><assignedCustodian><representedCustodianOrganization><id nullFlavor=\"UNK\"/><name>\(escape(header.custodian))</name>"
        xml += "</representedCustodianOrganization></assignedCustodian></custodian>\n"
        if let accession = header.accessionNumber, !accession.isEmpty {
            xml += "<inFulfillmentOf><order><id extension=\"\(escape(accession))\" nullFlavor=\"UNK\"/></order></inFulfillmentOf>\n"
        }
        if let study = header.studyInstanceUID {
            xml += "<documentationOf><serviceEvent classCode=\"ACT\"><id root=\"\(escape(study))\"/>"
            if let procedure = report.procedures.first { xml += code("code", procedure) }
            xml += "</serviceEvent></documentationOf>\n"
        }
        xml += "<component><structuredBody>\n"
        let located = references.filter { ($0.studyInstanceUID ?? header.studyInstanceUID) != nil && $0.seriesInstanceUID != nil }
        if !located.isEmpty {
            xml += "<component><section>" + code("code", DICOMSRCodes.dcm("121181", "DICOM Object Catalog"))
            var studies: [String: [String: [DICOMSRReference]]] = [:], order: [String] = []
            for reference in located {
                let study = reference.studyInstanceUID ?? header.studyInstanceUID!
                if studies[study] == nil { order.append(study) }
                studies[study, default: [:]][reference.seriesInstanceUID!, default: []].append(reference)
            }
            for study in order {
                xml += "<entry><act classCode=\"ACT\" moodCode=\"EVN\"><id root=\"\(escape(study))\"/>" + code("code", DICOMSRCodes.dcm("113014", "Study"))
                for (series, instances) in studies[study]!.sorted(by: { $0.key < $1.key }) {
                    xml += "<entryRelationship typeCode=\"COMP\"><act classCode=\"ACT\" moodCode=\"EVN\"><id root=\"\(escape(series))\"/>"
                    xml += code("code", DICOMSRCodes.dcm("113015", "Series"))
                    for instance in instances {
                        xml += "<entryRelationship typeCode=\"COMP\"><observation classCode=\"DGIMG\" moodCode=\"EVN\"><id root=\"\(escape(instance.sopInstanceUID))\"/>"
                        xml += "<code code=\"\(escape(instance.sopClassUID))\" codeSystem=\"1.2.840.10008.2.6.1\" codeSystemName=\"DCMUID\"/></observation></entryRelationship>"
                    }
                    xml += "</act></entryRelationship>"
                }
                xml += "</act></entry>"
            }
            xml += "</section></component>\n"
        }
        for section in report.sections {
            xml += "<component><section>" + code("code", section.heading) + "<title>\(escape(section.heading.meaning))</title><text>"
            for observation in section.observations {
                switch observation.value {
                case .text(let text):
                    for paragraph in text.components(separatedBy: "\n\n") where !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        xml += "<paragraph>\(escape(paragraph).replacingOccurrences(of: "\n", with: "<br/>"))</paragraph>"
                    }
                case .code(let value):
                    xml += "<paragraph>\(escape(observation.concept.meaning)): \(escape(value.meaning))</paragraph>"
                case .personName(let name):
                    xml += "<paragraph>\(escape(observation.concept.meaning)): \(escape(name.replacingOccurrences(of: "^", with: " ")))</paragraph>"
                case .date(let value), .time(let value), .dateTime(let value):
                    xml += "<paragraph>\(escape(observation.concept.meaning)): \(escape(value))</paragraph>"
                }
            }
            xml += "</text>"
            for observation in section.observations {
                guard case .code(let value) = observation.value else { continue }
                xml += "<entry><observation classCode=\"OBS\" moodCode=\"EVN\">" + code("code", observation.concept)
                xml += code("value", value, extra: " xsi:type=\"CD\"") + "</observation></entry>"
            }
            xml += "</section></component>\n"
        }
        xml += "</structuredBody></component>\n</ClinicalDocument>\n"
        return xml
    }

    /// Reads the title, language, and sections of a CDA imaging report into
    /// a TID 2000 report; the DICOM Object Catalog section is left out. Nil
    /// when the document is not a CDA document with a structured body.
    public static func report(cda: Data) -> DICOMDiagnosticImagingReport? {
        let reader = Reader()
        let parser = XMLParser(data: cda)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), reader.clinicalDocument, reader.structuredBody else { return nil }
        let sections = reader.sections.compactMap { section -> DICOMDiagnosticImagingReport.Section? in
            guard let heading = section.code, !heading.sameConcept(as: DICOMSRCodes.dcm("121181", "DICOM Object Catalog")) else { return nil }
            let element = DICOMDiagnosticImagingReport.element(for: heading)
            let paragraphs = section.paragraphs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !paragraphs.isEmpty else { return nil }
            return .init(heading: heading, observations: paragraphs.map { .text($0, concept: element) })
        }
        return DICOMDiagnosticImagingReport(title: reader.title ?? DICOMDiagnosticImagingReport.Headings.diagnosticImagingReport,
                                            language: reader.language.map { DICOMCode($0, scheme: "RFC5646", meaning: $0) },
                                            sections: sections)
    }

    final class Reader: NSObject, XMLParserDelegate {
        struct Section { var code: DICOMCode?; var paragraphs: [String] = []; var title: String? }
        var clinicalDocument = false, structuredBody = false
        var title: DICOMCode?, language: String?
        var sections: [Section] = []
        var stack: [String] = []
        var open: [Int] = []
        var text: String?
        var paragraph: String?

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            func code() -> DICOMCode? {
                guard let value = attributes["code"], let system = attributes["codeSystem"] else { return nil }
                let scheme = attributes["codeSystemName"].flatMap { DICOMReportCDA.schemes[$0] != nil ? $0 : nil } ?? DICOMReportCDA.scheme(system)
                return DICOMCode(value, scheme: scheme, meaning: attributes["displayName"] ?? value)
            }
            let parent = stack.last
            stack.append(element)
            switch element {
            case "ClinicalDocument" where stack.count == 1: clinicalDocument = true
            case "structuredBody": structuredBody = true
            case "code" where parent == "ClinicalDocument": title = code()
            case "languageCode" where parent == "ClinicalDocument": language = attributes["code"]
            case "section":
                sections.append(Section())
                open.append(sections.count - 1)
            case "code" where parent == "section": if let index = open.last { sections[index].code = code() }
            case "text" where parent == "section": text = ""
            case "paragraph" where text != nil: paragraph = ""
            case "br": if paragraph != nil { paragraph! += "\n" } else if text != nil { text! += "\n" }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if paragraph != nil { paragraph! += string } else if text != nil { text! += string }
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            stack.removeLast()
            switch element {
            case "paragraph" where paragraph != nil:
                if let index = open.last { sections[index].paragraphs.append(paragraph!) }
                paragraph = nil
            case "text" where text != nil:
                // Text outside paragraphs is one more paragraph.
                if let index = open.last, !text!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sections[index].paragraphs.append(text!)
                }
                text = nil
            case "section": _ = open.popLast()
            default: break
            }
        }
    }
}
