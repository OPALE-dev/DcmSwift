import Foundation

/// An encapsulated document: PDF, CDA, STL, OBJ, or MTL in an instance of
/// the Encapsulated Document IODs (PS3.3 A.45, A.85, C.24).
public struct DICOMEncapsulatedDocument: Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case pdf, cda, stl, obj, mtl

        public var sopClassUID: String {
            switch self {
            case .pdf: return "1.2.840.10008.5.1.4.1.1.104.1"
            case .cda: return "1.2.840.10008.5.1.4.1.1.104.2"
            case .stl: return "1.2.840.10008.5.1.4.1.1.104.3"
            case .obj: return "1.2.840.10008.5.1.4.1.1.104.4"
            case .mtl: return "1.2.840.10008.5.1.4.1.1.104.5"
            }
        }

        /// MIME Type of Encapsulated Document (0042,0012).
        public var mimeType: String {
            switch self {
            case .pdf: return "application/pdf"
            case .cda: return "text/XML"
            case .stl: return "model/stl"
            case .obj: return "model/obj"
            case .mtl: return "model/mtl"
            }
        }

        /// Whether the document is a 3D model of the Manufacturing 3D Model
        /// Module (PS3.3 C.35.1).
        public var isModel: Bool { [.stl, .obj, .mtl].contains(self) }

        public init?(sopClassUID: String) {
            guard let kind = Kind.allCases.first(where: { $0.sopClassUID == sopClassUID }) else { return nil }
            self = kind
        }

        /// The kind of a file, by its extension.
        public init?(pathExtension: String) {
            switch pathExtension.lowercased() {
            case "pdf": self = .pdf
            case "xml", "cda": self = .cda
            case "stl": self = .stl
            case "obj": self = .obj
            case "mtl": self = .mtl
            default: return nil
            }
        }
    }

    public var kind: Kind
    /// The document, without the padding of the Value.
    public var document: Data
    /// Document Title (0042,0010).
    public var title: String
    /// Concept Name Code Sequence (0040,A043): the kind of document.
    public var conceptName: DICOMCode?

    /// Whether `document` is an ASCII STL file, which the Encapsulated STL
    /// IOD does not allow: it holds binary STL only (PS3.3 A.85.1.4.1).
    public static func isASCIISTL(_ document: Data) -> Bool {
        guard document.starts(with: Data("solid".utf8)) else { return false }
        // A binary STL may also start with "solid" in its 80-byte header:
        // its size is then 84 + 50 bytes per triangle.
        if document.count >= 84 {
            let count = document[80..<84].enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
            if document.count == 84 + 50 * count { return false }
        }
        return true
    }

    public init(kind: Kind, document: Data, title: String = "", conceptName: DICOMCode? = nil) {
        self.kind = kind
        self.document = document
        self.title = title
        self.conceptName = conceptName
    }

    /// Reads the document of an Encapsulated Document instance.
    public init?(dataSet: DataSet) {
        guard let sopClass = dataSet.string(forTag: "SOPClassUID"), let kind = Kind(sopClassUID: sopClass),
              let element = dataSet.element(forTagName: "EncapsulatedDocument"), var bytes = element.data else {
            return nil
        }
        // Encapsulated Document Length (0042,0015) gives the length before
        // padding; PDF and CDA are padded to an even length otherwise.
        if let length = dataSet.unsignedInteger32(forTag: "EncapsulatedDocumentLength"), Int(length) <= bytes.count {
            bytes = bytes.prefix(Int(length))
        } else if kind == .pdf, bytes.last == 0 {
            bytes = bytes.dropLast()
        }
        self.kind = kind
        document = Data(bytes)
        title = dataSet.element(forTagName: "DocumentTitle")?.textValues?.first ?? ""
        conceptName = (dataSet.element(forTagName: "ConceptNameCodeSequence") as? DataSequence)?.items.first
            .flatMap(DICOMCode.init(item:))
    }

    /// A new instance holding the document. The patient and study come from
    /// `context`, such as an image of the same study, when given; otherwise
    /// a new study is made with empty patient attributes.
    public func dataSet(context: DataSet? = nil, seriesNumber: Int = 1, instanceNumber: Int = 1,
                        date: Date = Date()) -> DataSet {
        let dataSet = DataSet()
        func set(_ name: String, _ value: Any) { _ = dataSet.set(value: value, forTagName: name) }
        func text(_ name: String) -> String { context?.element(forTagName: name)?.textValues?.first ?? "" }
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents(in: TimeZone.current, from: date)
        let day = String(format: "%04d%02d%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
        let time = String(format: "%02d%02d%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)

        // Characters outside ASCII need UTF-8.
        let texts = [title, conceptName?.meaning ?? "", text("PatientName"), text("StudyDescription")]
        if texts.contains(where: { $0.unicodeScalars.contains { $0.value > 0x7F } }) {
            set("SpecificCharacterSet", "ISO_IR 192")
        }
        set("SOPClassUID", kind.sopClassUID)
        set("SOPInstanceUID", Self.newUID())
        // Patient and General Study.
        for name in ["PatientName", "PatientID", "PatientBirthDate", "PatientSex", "StudyDate", "StudyTime",
                     "ReferringPhysicianName", "StudyID", "AccessionNumber"] {
            set(name, text(name))
        }
        if !text("StudyDescription").isEmpty { set("StudyDescription", text("StudyDescription")) }
        set("StudyInstanceUID", context?.string(forTag: "StudyInstanceUID") ?? Self.newUID())
        if context == nil {
            set("StudyDate", day)
            set("StudyTime", time)
        }
        // Encapsulated Document Series.
        set("Modality", kind.isModel ? "M3D" : "DOC")
        set("SeriesInstanceUID", Self.newUID())
        set("SeriesNumber", String(seriesNumber))
        // General Equipment, SC Equipment or Enhanced General Equipment.
        set("Manufacturer", "DcmSwift")
        if kind.isModel {
            set("ManufacturerModelName", "DcmSwift")
            set("DeviceSerialNumber", "0")
            set("SoftwareVersions", DICOMImplementation.versionName)
            // Frame of Reference (STL and OBJ, not MTL) and Manufacturing
            // 3D Model.
            if kind != .mtl {
                set("FrameOfReferenceUID", context?.string(forTag: "FrameOfReferenceUID") ?? Self.newUID())
                set("PositionReferenceIndicator", "")
            }
            addCode("MeasurementUnitsCodeSequence", DICOMCode("mm", scheme: "UCUM", meaning: "mm"), to: dataSet)
        } else {
            set("ConversionType", "WSD")
        }
        // Encapsulated Document.
        set("InstanceNumber", String(instanceNumber))
        set("ContentDate", day)
        set("ContentTime", time)
        set("AcquisitionDateTime", day + time)
        set("BurnedInAnnotation", "YES")
        set("DocumentTitle", title)
        if let conceptName {
            addCode("ConceptNameCodeSequence", conceptName, to: dataSet)
        } else {
            addEmptySequence("ConceptNameCodeSequence", to: dataSet)
        }
        set("MIMETypeOfEncapsulatedDocument", kind.mimeType)
        var bytes = document
        if bytes.count % 2 == 1 { bytes.append(0) }
        if let element = DataElement(withTagName: "EncapsulatedDocument", dataset: dataSet) {
            element.vr = .OB
            _ = element.setValue(bytes)
            dataSet.add(element: element)
        }
        if let element = DataElement(withTagName: "EncapsulatedDocumentLength", dataset: dataSet) {
            element.vr = .UL
            let length = UInt32(document.count)
            element.data = Data([UInt8(length & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length >> 16 & 0xFF), UInt8(length >> 24)])
            element.length = 4
            dataSet.add(element: element)
        }
        if kind == .cda, let identifier = Self.cdaIdentifier(document) {
            // HL7 Instance Identifier (0040,E001): the CDA's root^extension.
            set("HL7InstanceIdentifier", identifier)
        }
        dataSet.sortElements()
        return dataSet
    }

    /// The ClinicalDocument/id of a CDA document, as root^extension.
    static func cdaIdentifier(_ document: Data) -> String? {
        let text = String(decoding: document.prefix(65536), as: UTF8.self)
        guard let range = text.range(of: #"<id\s[^>]*>"#, options: .regularExpression) else { return nil }
        let tag = String(text[range])
        func attribute(_ name: String) -> String? {
            guard let match = tag.range(of: "\(name)=\"([^\"]*)\"", options: .regularExpression) else { return nil }
            return String(tag[match].dropFirst(name.count + 2).dropLast())
        }
        guard let root = attribute("root") else { return nil }
        return attribute("extension").map { "\(root)^\($0)" } ?? root
    }

    static func newUID() -> String {
        "2.25." + DICOMDeidentifier.decimal(withUnsafeBytes(of: UUID().uuid) { Array($0) })
    }

    private func addCode(_ name: String, _ code: DICOMCode, to dataSet: DataSet) {
        guard let tag = DicomSpec.shared.dataTag(forName: name) else { return }
        let sequence = DataSequence(withTag: tag)
        sequence.vr = .SQ
        sequence.length = -1
        let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
        item.length = -1
        for (keyword, value) in [("CodeValue", code.value), ("CodingSchemeDesignator", code.scheme), ("CodeMeaning", code.meaning)] {
            guard let element = DataElement(withTagName: keyword, dataset: dataSet, parent: item) else { continue }
            _ = element.setValue(value)
            item.elements.append(element)
        }
        sequence.items.append(item)
        dataSet.add(element: sequence)
    }

    private func addEmptySequence(_ name: String, to dataSet: DataSet) {
        guard let tag = DicomSpec.shared.dataTag(forName: name) else { return }
        let sequence = DataSequence(withTag: tag)
        sequence.vr = .SQ
        sequence.length = -1
        dataSet.add(element: sequence)
    }
}
