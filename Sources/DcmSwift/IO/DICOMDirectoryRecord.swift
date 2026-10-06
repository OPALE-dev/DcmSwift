import Foundation

/// Extensible PS3.3 Annex F Directory Record Type identifier.
///
/// A struct is used instead of a closed enum so private and future standard
/// record types remain observable without losing their original value.
public struct DICOMDirectoryRecordType: RawRepresentable, Hashable, Sendable {
    public let rawValue:String

    public init(rawValue:String) {
        self.rawValue = rawValue
    }

    public static let patient = Self(rawValue: "PATIENT")
    public static let study = Self(rawValue: "STUDY")
    public static let series = Self(rawValue: "SERIES")
    public static let image = Self(rawValue: "IMAGE")
    public static let rtDose = Self(rawValue: "RT DOSE")
    public static let rtStructureSet = Self(rawValue: "RT STRUCTURE SET")
    public static let rtPlan = Self(rawValue: "RT PLAN")
    public static let rtTreatmentRecord = Self(rawValue: "RT TREAT RECORD")
    public static let presentation = Self(rawValue: "PRESENTATION")
    public static let waveform = Self(rawValue: "WAVEFORM")
    public static let structuredReport = Self(rawValue: "SR DOCUMENT")
    public static let keyObjectDocument = Self(rawValue: "KEY OBJECT DOC")
    public static let spectroscopy = Self(rawValue: "SPECTROSCOPY")
    public static let rawData = Self(rawValue: "RAW DATA")
    public static let registration = Self(rawValue: "REGISTRATION")
    public static let fiducial = Self(rawValue: "FIDUCIAL")
    public static let hangingProtocol = Self(rawValue: "HANGING PROTOCOL")
    public static let encapsulatedDocument = Self(rawValue: "ENCAP DOC")
    public static let valueMap = Self(rawValue: "VALUE MAP")
    public static let stereometric = Self(rawValue: "STEREOMETRIC")
    public static let palette = Self(rawValue: "PALETTE")
    public static let implant = Self(rawValue: "IMPLANT")
    public static let implantAssembly = Self(rawValue: "IMPLANT ASSY")
    public static let implantGroup = Self(rawValue: "IMPLANT GROUP")
    public static let plan = Self(rawValue: "PLAN")
    public static let measurement = Self(rawValue: "MEASUREMENT")
    public static let surface = Self(rawValue: "SURFACE")
    public static let surfaceScan = Self(rawValue: "SURFACE SCAN")
    public static let tract = Self(rawValue: "TRACT")
    public static let assessment = Self(rawValue: "ASSESSMENT")
    public static let radiotherapy = Self(rawValue: "RADIOTHERAPY")
    public static let annotation = Self(rawValue: "ANNOTATION")
    public static let inventory = Self(rawValue: "INVENTORY")
    public static let waveformPresentation = Self(rawValue: "WF PRESENTATION")
    public static let `private` = Self(rawValue: "PRIVATE")

    /// Current standard values from PS3.3 2026d Table F.4-1.
    public static let standard2026d:Set<Self> = [
        .patient, .study, .series, .image, .rtDose, .rtStructureSet, .rtPlan,
        .rtTreatmentRecord, .presentation, .waveform, .structuredReport,
        .keyObjectDocument, .spectroscopy, .rawData, .registration, .fiducial,
        .hangingProtocol, .encapsulatedDocument, .valueMap, .stereometric,
        .palette, .implant, .implantAssembly, .implantGroup, .plan,
        .measurement, .surface, .surfaceScan, .tract, .assessment,
        .radiotherapy, .annotation, .inventory, .waveformPresentation, .private
    ]
}

/// Lossless view of one item in a Directory Record Sequence.
public struct DICOMDirectoryRecord {
    public let item:DataItem

    public init(item:DataItem) {
        self.item = item
    }

    public var type:DICOMDirectoryRecordType? {
        guard let value = item.element(withName: "DirectoryRecordType")?.value as? String else {
            return nil
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return normalized.isEmpty ? nil : DICOMDirectoryRecordType(rawValue: normalized)
    }

    public var isInUse:Bool? {
        guard let value = item.element(withName: "RecordInUseFlag")?.value as? UInt16 else {
            return nil
        }
        return value == UInt16.max
    }

    public var nextRecordOffset:UInt32? {
        return item.element(withName: "OffsetOfTheNextDirectoryRecord")?.value as? UInt32
    }

    public var lowerLevelRecordOffset:UInt32? {
        return item.element(withName: "OffsetOfReferencedLowerLevelDirectoryEntity")?.value as? UInt32
    }

    /// Includes both standard and unknown/private attributes exactly as parsed.
    public var elements:[DataElement] {
        return item.elements
    }
}

private enum DICOMDirectoryKeyType: Equatable {
    case type1
    case type2
}

private enum DICOMDirectoryRecordSchemas {
    typealias Requirements = [String:DICOMDirectoryKeyType]

    /// Unconditional top-level keys from PS3.3 2026d Tables F.5-1 through
    /// F.5-4 and F.5-19 through F.5-22. Conditional and included macro keys
    /// are intentionally validated separately as their conditions are added.
    static let requirements:[DICOMDirectoryRecordType:Requirements] = [
        .patient: ["PatientName": .type2, "PatientID": .type1],
        .study: [
            "StudyDate": .type1, "StudyTime": .type1,
            "StudyDescription": .type2, "StudyInstanceUID": .type1,
            "StudyID": .type1, "AccessionNumber": .type2
        ],
        .series: [
            "Modality": .type1, "SeriesInstanceUID": .type1,
            "SeriesNumber": .type1
        ],
        .image: ["InstanceNumber": .type1],
        .rtDose: ["InstanceNumber": .type1, "DoseSummationType": .type1],
        .rtStructureSet: [
            "InstanceNumber": .type1, "StructureSetLabel": .type1,
            "StructureSetDate": .type2, "StructureSetTime": .type2
        ],
        .rtPlan: [
            "InstanceNumber": .type1, "RTPlanLabel": .type1,
            "RTPlanDate": .type2, "RTPlanTime": .type2
        ],
        .rtTreatmentRecord: [
            "InstanceNumber": .type1, "TreatmentDate": .type2,
            "TreatmentTime": .type2
        ]
    ]
}

extension DicomDir {
    /// Flat, byte-preserving access to every parsed Directory Record. Use the
    /// offset properties to traverse record relationships.
    public var directoryRecords:[DICOMDirectoryRecord] {
        guard let sequence = dataset?.element(forTagName: "DirectoryRecordSequence") as? DataSequence else {
            return []
        }
        return sequence.items.map(DICOMDirectoryRecord.init(item:))
    }

    /// Validates unconditional Type 1 and Type 2 keys covered by the current
    /// PS3.3 Annex F schema registry. This is independent of media-profile and
    /// conditional-key validation.
    public func validateDirectoryRecordKeys() -> [ValidationResult] {
        var results:[ValidationResult] = []

        for record in directoryRecords {
            guard let type = record.type,
                  let requirements = DICOMDirectoryRecordSchemas.requirements[type] else {
                continue
            }
            for (name, requirement) in requirements.sorted(by: { $0.key < $1.key }) {
                guard let element = record.item.element(withName: name) else {
                    results.append(ValidationResult(
                        record.item,
                        message: "Directory Record Type \(type.rawValue) is missing Type \(requirement == .type1 ? "1" : "2") key \(name)",
                        severity: .Error
                    ))
                    continue
                }
                if requirement == .type1 && isEmptyDirectoryValue(element) {
                    results.append(ValidationResult(
                        element,
                        message: "Directory Record Type \(type.rawValue) has an empty Type 1 key \(name)",
                        severity: .Error
                    ))
                }
            }
        }
        return results
    }

    private func isEmptyDirectoryValue(_ element:DataElement) -> Bool {
        if let sequence = element as? DataSequence {
            return sequence.items.isEmpty
        }
        if let value = element.value as? String {
            return value.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).isEmpty
        }
        return element.length == 0
    }
}
