import Foundation

/// A reference of an SR content item to another instance (COMPOSITE, IMAGE,
/// WAVEFORM): the Referenced SOP Sequence (0008,1199).
public struct DICOMSRReference: Sendable, Equatable {
    public var sopClassUID: String
    public var sopInstanceUID: String
    /// Referenced Frame Number (0008,1160).
    public var frames: [Int]
    /// Referenced Segment Number (0062,000B).
    public var segments: [Int]

    public init(sopClassUID: String, sopInstanceUID: String, frames: [Int] = [], segments: [Int] = []) {
        self.sopClassUID = sopClassUID
        self.sopInstanceUID = sopInstanceUID
        self.frames = frames
        self.segments = segments
    }
}

/// A content item of a Structured Report (PS3.3 C.17.3, C.18).
public struct DICOMSRContentItem: Sendable {
    public enum Value: Sendable {
        /// Continuity Of Content (0040,A050): SEPARATE or CONTINUOUS.
        case container(continuity: String)
        case text(String)
        case code(DICOMCode)
        /// Numeric Value (0040,A30A) with its Measurement Units; nil when
        /// the Numeric Value Qualifier tells why there is none.
        case number(Double?, units: DICOMCode?, qualifier: DICOMCode?)
        case dateTime(String)
        case date(String)
        case time(String)
        case uidReference(String)
        case personName(String)
        case composite(DICOMSRReference)
        case image(DICOMSRReference)
        case waveform(DICOMSRReference)
        /// Graphic Type (0070,0023) and Graphic Data (0070,0022), image
        /// coordinates.
        case spatialCoordinates(graphicType: String, points: [Double])
        /// With the Referenced Frame of Reference UID (3006,0024).
        case spatialCoordinates3D(graphicType: String, points: [Double], frameOfReferenceUID: String)
        /// Temporal Range Type (0040,A130) and the sample positions, time
        /// offsets, or date times it ranges over.
        case temporalCoordinates(rangeType: String, samplePositions: [Int], timeOffsets: [Double], dateTimes: [String])
        /// Referenced Content Item Identifier (0040,DB73): a by-reference
        /// relationship to another item of the tree, by position.
        case reference([Int])
        /// Value types read as attributes only, such as TABLE.
        case other(valueType: String)

        public var valueType: String {
            switch self {
            case .container: return "CONTAINER"
            case .text: return "TEXT"
            case .code: return "CODE"
            case .number: return "NUM"
            case .dateTime: return "DATETIME"
            case .date: return "DATE"
            case .time: return "TIME"
            case .uidReference: return "UIDREF"
            case .personName: return "PNAME"
            case .composite: return "COMPOSITE"
            case .image: return "IMAGE"
            case .waveform: return "WAVEFORM"
            case .spatialCoordinates: return "SCOORD"
            case .spatialCoordinates3D: return "SCOORD3D"
            case .temporalCoordinates: return "TCOORD"
            case .reference: return ""
            case .other(let type): return type
            }
        }
    }

    /// Relationship Type (0040,A010) with the parent; nil for the root.
    public var relationship: String?
    /// Concept Name Code Sequence (0040,A043).
    public var conceptName: DICOMCode?
    public var value: Value
    /// Observation DateTime (0040,A032).
    public var observationDateTime: String?
    /// Observation UID (0040,A171).
    public var observationUID: String?
    public var children: [DICOMSRContentItem]

    public init(_ relationship: String?, _ conceptName: DICOMCode?, _ value: Value,
                children: [DICOMSRContentItem] = [], observationDateTime: String? = nil, observationUID: String? = nil) {
        self.relationship = relationship
        self.conceptName = conceptName
        self.value = value
        self.children = children
        self.observationDateTime = observationDateTime
        self.observationUID = observationUID
    }

    /// The descendants, depth first, with their content item identifiers
    /// (the positions from the root, PS3.3 C.17.3.2.5).
    public func flattened(_ identifier: [Int] = [1]) -> [(identifier: [Int], item: DICOMSRContentItem)] {
        [(identifier, self)] + children.enumerated().flatMap { index, child in child.flattened(identifier + [index + 1]) }
    }

    /// The children with a concept name, by scheme and value.
    public func children(named code: DICOMCode) -> [DICOMSRContentItem] {
        children.filter { $0.conceptName?.sameConcept(as: code) == true }
    }

    // MARK: Reading

    init(attributes elements: [DataElement], relationship: String?) {
        func element(_ name: String) -> DataElement? { elements.first { $0.name == name } }
        func text(_ name: String) -> String? { element(name)?.decodedTexts?.first }
        func code(_ name: String) -> DICOMCode? {
            (element(name) as? DataSequence)?.items.first.flatMap(DICOMCode.init(item:))
        }
        func reference() -> DICOMSRReference {
            let item = (element("ReferencedSOPSequence") as? DataSequence)?.items.first
            func value(_ name: String) -> DataElement? { item?.element(withName: name) }
            return DICOMSRReference(
                sopClassUID: value("ReferencedSOPClassUID")?.decodedTexts?.first ?? "",
                sopInstanceUID: value("ReferencedSOPInstanceUID")?.decodedTexts?.first ?? "",
                frames: value("ReferencedFrameNumber")?.decodedNumbers.map { Int($0) } ?? [],
                segments: value("ReferencedSegmentNumber")?.decodedNumbers.map { Int($0) } ?? [])
        }
        self.relationship = relationship
        conceptName = code("ConceptNameCodeSequence")
        observationDateTime = text("ObservationDateTime")
        observationUID = text("ObservationUID")
        if let identifier = element("ReferencedContentItemIdentifier") {
            value = .reference(identifier.decodedNumbers.map { Int($0) })
        } else {
            let type = text("ValueType") ?? ""
            switch type {
            case "CONTAINER": value = .container(continuity: text("ContinuityOfContent") ?? "SEPARATE")
            case "TEXT": value = .text(text("TextValue") ?? "")
            case "CODE": value = code("ConceptCodeSequence").map(Value.code) ?? .other(valueType: type)
            case "NUM":
                let measured = (element("MeasuredValueSequence") as? DataSequence)?.items.first
                let number = measured?.element(withName: "NumericValue")?.decodedNumbers.first
                let units = (measured?.element(withName: "MeasurementUnitsCodeSequence") as? DataSequence)?.items.first
                    .flatMap(DICOMCode.init(item:))
                value = .number(number, units: units, qualifier: code("NumericValueQualifierCodeSequence"))
            case "DATETIME": value = .dateTime(text("DateTime") ?? "")
            case "DATE": value = .date(text("Date") ?? "")
            case "TIME": value = .time(text("Time") ?? "")
            case "UIDREF": value = .uidReference(text("UID") ?? "")
            case "PNAME": value = .personName(text("PersonName") ?? "")
            case "COMPOSITE": value = .composite(reference())
            case "IMAGE": value = .image(reference())
            case "WAVEFORM": value = .waveform(reference())
            case "SCOORD":
                value = .spatialCoordinates(graphicType: text("GraphicType") ?? "",
                                            points: element("GraphicData")?.decodedNumbers ?? [])
            case "SCOORD3D":
                value = .spatialCoordinates3D(graphicType: text("GraphicType") ?? "",
                                              points: element("GraphicData")?.decodedNumbers ?? [],
                                              frameOfReferenceUID: text("ReferencedFrameOfReferenceUID") ?? "")
            case "TCOORD":
                value = .temporalCoordinates(
                    rangeType: text("TemporalRangeType") ?? "",
                    samplePositions: element("ReferencedSamplePositions")?.decodedNumbers.map { Int($0) } ?? [],
                    timeOffsets: element("ReferencedTimeOffsets")?.decodedNumbers ?? [],
                    dateTimes: element("ReferencedDateTime")?.decodedTexts ?? [])
            default: value = .other(valueType: type)
            }
        }
        children = ((element("ContentSequence") as? DataSequence)?.items ?? []).map { item in
            DICOMSRContentItem(attributes: item.elements,
                               relationship: item.element(withName: "RelationshipType")?.decodedTexts?.first)
        }
    }

    // MARK: Writing

    func write(to builder: DICOMDataSetBuilder, in item: DataItem?) {
        if let relationship { builder.set("RelationshipType", relationship, in: item) }
        if case .reference(let identifier) = value {
            builder.set("ReferencedContentItemIdentifier",
                        Data(identifier.flatMap { number -> [UInt8] in
                            (0..<4).map { UInt8(truncatingIfNeeded: UInt32(number) >> UInt32($0 * 8)) }
                        }), vr: .UL, in: item)
            return
        }
        builder.set("ValueType", value.valueType, in: item)
        if let conceptName { builder.code("ConceptNameCodeSequence", conceptName, in: item) }
        if let observationDateTime { builder.set("ObservationDateTime", observationDateTime, in: item) }
        if let observationUID { builder.set("ObservationUID", observationUID, in: item) }
        func reference(_ reference: DICOMSRReference) {
            builder.sequence("ReferencedSOPSequence", in: item, items: [{ entry in
                builder.set("ReferencedSOPClassUID", reference.sopClassUID, in: entry)
                builder.set("ReferencedSOPInstanceUID", reference.sopInstanceUID, in: entry)
                if !reference.frames.isEmpty {
                    builder.set("ReferencedFrameNumber", reference.frames.map(String.init), in: entry)
                }
                if !reference.segments.isEmpty {
                    builder.set("ReferencedSegmentNumber", Data(reference.segments.flatMap {
                        [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)]
                    }), vr: .US, in: entry)
                }
            }])
        }
        func floats(_ values: [Double]) -> Data {
            Data(values.flatMap { value -> [UInt8] in
                let bits = Float(value).bitPattern
                return (0..<4).map { UInt8(truncatingIfNeeded: bits >> UInt32($0 * 8)) }
            })
        }
        switch value {
        case .container(let continuity): builder.set("ContinuityOfContent", continuity, in: item)
        case .text(let text): builder.set("TextValue", text, in: item)
        case .code(let code): builder.code("ConceptCodeSequence", code, in: item)
        case .number(let number, let units, let qualifier):
            builder.sequence("MeasuredValueSequence", in: item, items: number == nil ? [] : [{ measured in
                builder.set("NumericValue", Self.decimalString(number!), in: measured)
                if let units { builder.code("MeasurementUnitsCodeSequence", units, in: measured) }
            }])
            if let qualifier { builder.code("NumericValueQualifierCodeSequence", qualifier, in: item) }
        case .dateTime(let value): builder.set("DateTime", value, in: item)
        case .date(let value): builder.set("Date", value, in: item)
        case .time(let value): builder.set("Time", value, in: item)
        case .uidReference(let value): builder.set("UID", value, in: item)
        case .personName(let value): builder.set("PersonName", value, in: item)
        case .composite(let value), .image(let value), .waveform(let value): reference(value)
        case .spatialCoordinates(let type, let points):
            builder.set("GraphicType", type, in: item)
            builder.set("GraphicData", floats(points), vr: .FL, in: item)
        case .spatialCoordinates3D(let type, let points, let frameOfReference):
            builder.set("GraphicType", type, in: item)
            builder.set("GraphicData", floats(points), vr: .FL, in: item)
            builder.set("ReferencedFrameOfReferenceUID", frameOfReference, in: item)
        case .temporalCoordinates(let rangeType, let samples, let offsets, let dateTimes):
            builder.set("TemporalRangeType", rangeType, in: item)
            if !samples.isEmpty {
                builder.set("ReferencedSamplePositions", Data(samples.flatMap { number -> [UInt8] in
                    (0..<4).map { UInt8(truncatingIfNeeded: UInt32(number) >> UInt32($0 * 8)) }
                }), vr: .UL, in: item)
            }
            if !offsets.isEmpty { builder.set("ReferencedTimeOffsets", offsets.map(Self.decimalString), in: item) }
            if !dateTimes.isEmpty { builder.set("ReferencedDateTime", dateTimes, in: item) }
        case .reference, .other: break
        }
        if !children.isEmpty {
            builder.sequence("ContentSequence", in: item, items: children.map { child in
                { entry in child.write(to: builder, in: entry) }
            })
        }
    }

    /// A Decimal String of at most 16 characters (PS3.5 6.2).
    static func decimalString(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        for digits in stride(from: 15, through: 1, by: -1) {
            let text = String(format: "%.\(digits)g", value)
            if text.count <= 16 { return text }
        }
        return "0"
    }
}

/// A Structured Report: its document attributes and content tree (PS3.3
/// A.35, C.17).
public struct DICOMStructuredReport: Sendable {
    public static let comprehensiveSR = "1.2.840.10008.5.1.4.1.1.88.33"
    public static let comprehensive3DSR = "1.2.840.10008.5.1.4.1.1.88.34"
    public static let enhancedSR = "1.2.840.10008.5.1.4.1.1.88.22"

    public var sopClassUID: String
    /// Completion Flag (0040,A491): PARTIAL or COMPLETE.
    public var completionFlag: String
    /// Verification Flag (0040,A493): UNVERIFIED or VERIFIED.
    public var verificationFlag: String
    /// Content Template Sequence (0040,A504): mapping resource and template
    /// identifier of the root, such as DCMR 1500.
    public var template: (mappingResource: String, identifier: String)?
    /// The root content item, a CONTAINER.
    public var root: DICOMSRContentItem

    public init(sopClassUID: String = DICOMStructuredReport.comprehensive3DSR, completionFlag: String = "COMPLETE",
                verificationFlag: String = "UNVERIFIED", template: (mappingResource: String, identifier: String)? = nil,
                root: DICOMSRContentItem) {
        self.sopClassUID = sopClassUID
        self.completionFlag = completionFlag
        self.verificationFlag = verificationFlag
        self.template = template
        self.root = root
    }

    /// Reads the document of an SR instance.
    public init?(dataSet: DataSet) {
        guard let sopClass = dataSet.string(forTag: "SOPClassUID"), sopClass.hasPrefix("1.2.840.10008.5.1.4.1.1.88."),
              dataSet.element(forTagName: "ValueType")?.decodedTexts?.first == "CONTAINER" else { return nil }
        sopClassUID = sopClass
        completionFlag = dataSet.element(forTagName: "CompletionFlag")?.decodedTexts?.first ?? ""
        verificationFlag = dataSet.element(forTagName: "VerificationFlag")?.decodedTexts?.first ?? ""
        if let item = (dataSet.element(forTagName: "ContentTemplateSequence") as? DataSequence)?.items.first {
            template = (item.element(withName: "MappingResource")?.decodedTexts?.first ?? "",
                        item.element(withName: "TemplateIdentifier")?.decodedTexts?.first ?? "")
        }
        root = DICOMSRContentItem(attributes: dataSet.datasetElements, relationship: nil)
    }

    /// A new SR instance of the document. The patient and study come from
    /// `context`, such as an image the report is about.
    public func dataSet(context: DataSet? = nil, seriesNumber: Int = 1, instanceNumber: Int = 1) -> DataSet {
        let builder = DICOMDataSetBuilder()
        let (day, time) = DICOMDataSetBuilder.dateAndTime()
        builder.set("SOPClassUID", sopClassUID)
        builder.set("SOPInstanceUID", DICOMDataSetBuilder.newUID())
        if let context {
            builder.copy(["PatientName", "PatientID", "PatientBirthDate", "PatientSex", "StudyDate", "StudyTime",
                          "ReferringPhysicianName", "StudyID", "AccessionNumber"], from: context)
            builder.copy(["SpecificCharacterSet"], from: context, empty: false)
            builder.set("StudyInstanceUID", context.string(forTag: "StudyInstanceUID") ?? DICOMDataSetBuilder.newUID())
        } else {
            for name in ["PatientName", "PatientID", "PatientBirthDate", "PatientSex", "ReferringPhysicianName",
                         "StudyID", "AccessionNumber"] {
                builder.set(name, "")
            }
            builder.set("StudyDate", day)
            builder.set("StudyTime", time)
            builder.set("StudyInstanceUID", DICOMDataSetBuilder.newUID())
        }
        // SR Document Series, General Equipment.
        builder.set("Modality", "SR")
        builder.set("SeriesInstanceUID", DICOMDataSetBuilder.newUID())
        builder.set("SeriesNumber", String(seriesNumber))
        builder.sequence("ReferencedPerformedProcedureStepSequence", items: [])
        builder.set("Manufacturer", "DcmSwift")
        // SR Document General.
        builder.set("InstanceNumber", String(instanceNumber))
        builder.set("CompletionFlag", completionFlag)
        builder.set("VerificationFlag", verificationFlag)
        builder.set("ContentDate", day)
        builder.set("ContentTime", time)
        builder.sequence("PerformedProcedureCodeSequence", items: [])
        // Current Requested Procedure Evidence: the instances referenced.
        let references = root.flattened().compactMap { entry -> DICOMSRReference? in
            switch entry.item.value {
            case .image(let reference), .composite(let reference), .waveform(let reference): return reference
            default: return nil
            }
        }
        if !references.isEmpty, let context {
            builder.sequence("CurrentRequestedProcedureEvidenceSequence", items: [{ study in
                builder.set("StudyInstanceUID", context.string(forTag: "StudyInstanceUID") ?? "", in: study)
                builder.sequence("ReferencedSeriesSequence", in: study, items: [{ series in
                    builder.set("SeriesInstanceUID", context.string(forTag: "SeriesInstanceUID") ?? "", in: series)
                    var seen = Set<String>()
                    let unique = references.filter { seen.insert($0.sopInstanceUID).inserted }
                    builder.sequence("ReferencedSOPSequence", in: series, items: unique.map { reference in
                        { item in
                            builder.set("ReferencedSOPClassUID", reference.sopClassUID, in: item)
                            builder.set("ReferencedSOPInstanceUID", reference.sopInstanceUID, in: item)
                        }
                    })
                }])
            }])
        }
        // SR Document Content: the root's attributes at the top level.
        if let template {
            builder.sequence("ContentTemplateSequence", items: [{ item in
                builder.set("MappingResource", template.mappingResource, in: item)
                builder.set("TemplateIdentifier", template.identifier, in: item)
            }])
        }
        root.write(to: builder, in: nil)
        return builder.finish()
    }
}
