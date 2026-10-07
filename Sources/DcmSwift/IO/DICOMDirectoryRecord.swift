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

enum DICOMDirectoryKeyType: Equatable {
    case type1
    case type2
}

enum DICOMDirectoryRecordSchemas {
    typealias Requirements = [String:DICOMDirectoryKeyType]

    /// Unconditional top-level keys from the PS3.3 2026d F.5 tables and their
    /// included macros. Conditional keys are validated separately as their
    /// conditions are added.
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
        ],
        .presentation: [
            "PresentationCreationDate": .type1,
            "PresentationCreationTime": .type1,
            "InstanceNumber": .type1, "ContentLabel": .type1,
            "ContentDescription": .type2
        ],
        .waveform: [
            "InstanceNumber": .type1, "ContentDate": .type1,
            "ContentTime": .type1
        ],
        .structuredReport: [
            "InstanceNumber": .type1, "CompletionFlag": .type1,
            "VerificationFlag": .type1, "ContentDate": .type1,
            "ContentTime": .type1, "ConceptNameCodeSequence": .type1
        ],
        .keyObjectDocument: [
            "InstanceNumber": .type1, "ContentDate": .type1,
            "ContentTime": .type1, "ConceptNameCodeSequence": .type1
        ],
        .spectroscopy: [
            "ImageType": .type1, "ContentDate": .type1,
            "ContentTime": .type1, "InstanceNumber": .type1,
            "NumberOfFrames": .type1, "Rows": .type1, "Columns": .type1,
            "DataPointRows": .type1, "DataPointColumns": .type1
        ],
        .rawData: [
            "ContentDate": .type1, "ContentTime": .type1,
            "InstanceNumber": .type2
        ],
        .registration: [
            "ContentDate": .type1, "ContentTime": .type1,
            "InstanceNumber": .type1, "ContentLabel": .type1,
            "ContentDescription": .type2
        ],
        .fiducial: [
            "ContentDate": .type1, "ContentTime": .type1,
            "InstanceNumber": .type1, "ContentLabel": .type1,
            "ContentDescription": .type2
        ],
        .hangingProtocol: [
            "HangingProtocolName": .type1,
            "HangingProtocolDescription": .type1,
            "HangingProtocolLevel": .type1,
            "HangingProtocolCreator": .type1,
            "HangingProtocolCreationDateTime": .type1,
            "HangingProtocolDefinitionSequence": .type1,
            "NumberOfPriorsReferenced": .type1,
            "HangingProtocolUserIdentificationCodeSequence": .type2
        ],
        .encapsulatedDocument: [
            "ContentDate": .type2, "ContentTime": .type2,
            "InstanceNumber": .type1, "DocumentTitle": .type2,
            "ConceptNameCodeSequence": .type2,
            "MIMETypeOfEncapsulatedDocument": .type1
        ],
        .valueMap: [
            "ContentDate": .type1, "ContentTime": .type1,
            "InstanceNumber": .type1, "ContentLabel": .type1,
            "ContentDescription": .type2
        ],
        .stereometric: [:],
        .palette: ["ContentLabel": .type1, "ContentDescription": .type2],
        .implant: [
            "Manufacturer": .type1, "ImplantName": .type1,
            "ImplantPartNumber": .type1
        ],
        .implantAssembly: [
            "ImplantAssemblyTemplateName": .type1,
            "Manufacturer": .type1, "ProcedureTypeCodeSequence": .type1
        ],
        .implantGroup: [
            "ImplantTemplateGroupName": .type1,
            "ImplantTemplateGroupIssuer": .type1
        ],
        .plan: [:],
        .measurement: [
            "ContentDate": .type1, "ContentTime": .type1,
            "InstanceNumber": .type1, "ContentLabel": .type1,
            "ContentDescription": .type2
        ],
        .surface: [
            "ContentDate": .type1, "ContentTime": .type1,
            "InstanceNumber": .type1, "ContentLabel": .type1,
            "ContentDescription": .type2
        ],
        .surfaceScan: ["ContentDate": .type1, "ContentTime": .type1],
        .tract: [
            "ContentDate": .type1, "ContentTime": .type1,
            "InstanceNumber": .type1, "ContentLabel": .type1,
            "ContentDescription": .type2
        ],
        .assessment: [
            "InstanceNumber": .type1, "InstanceCreationDate": .type1,
            "InstanceCreationTime": .type2
        ],
        .radiotherapy: [
            "InstanceNumber": .type1, "ContentDescription": .type2,
            "ContentCreatorName": .type2
        ],
        .annotation: [
            "ContentDate": .type1, "ContentTime": .type1,
            "InstanceNumber": .type1, "ContentLabel": .type1,
            "ContentDescription": .type2
        ],
        .inventory: [
            "ContentDate": .type1, "ContentTime": .type1,
            "InventoryPurpose": .type2, "InventoryLevel": .type1,
            "InventoryCompletionStatus": .type1,
            "TotalNumberOfStudyRecords": .type1,
            "ScopeOfInventorySequence": .type2
        ],
        .waveformPresentation: [
            "PresentationCreationDate": .type1,
            "PresentationCreationTime": .type1,
            "InstanceNumber": .type1, "ContentLabel": .type1,
            "ContentDescription": .type2
        ],
        .private: [:]
    ]

    /// F.5 record definitions that make Specific Character Set (0008,0005)
    /// Type 1C when an extended or replacement repertoire is used in a key.
    static let specificCharacterSetTypes:Set<DICOMDirectoryRecordType> = [
        .patient, .study, .series, .image, .rtDose, .rtStructureSet,
        .rtPlan, .rtTreatmentRecord, .presentation, .waveform,
        .structuredReport, .keyObjectDocument, .spectroscopy, .rawData,
        .registration, .fiducial, .hangingProtocol, .encapsulatedDocument,
        .valueMap, .stereometric, .palette, .plan, .measurement, .surface,
        .surfaceScan, .tract, .assessment, .radiotherapy, .annotation,
        .inventory, .waveformPresentation
    ]

    static let referencedSOPKeys = [
        "ReferencedFileID",
        "ReferencedSOPClassUIDInFile",
        "ReferencedSOPInstanceUIDInFile",
        "ReferencedTransferSyntaxUIDInFile"
    ]

    /// F.5 Sequences whose Items include the PS3.3 Table 10-11 SOP Instance
    /// Reference Macro.
    static let sopInstanceReferenceSequenceNames:Set<String> = [
        "ReferencedImageSequence",
        "ReferencedInstanceSequence",
        "ReferencedWaveformSequence"
    ]

    /// Type 1C keys whose value, when present, is always non-empty. Their
    /// presence condition may still depend on the referenced SOP Instance.
    static let conditionalType1Keys:[DICOMDirectoryRecordType:Set<String>] = [
        .presentation: ["ReferencedSeriesSequence", "BlendingSequence"],
        .structuredReport: ["VerificationDateTime", "ContentSequence"],
        .keyObjectDocument: ["ContentSequence"],
        .spectroscopy: ["ReferencedImageEvidenceSequence"],
        .encapsulatedDocument: ["HL7InstanceIdentifier"],
        .implant: ["ImplantSize"],
        .radiotherapy: ["UserContentLabel", "UserContentLongLabel"],
        .waveformPresentation: ["ReferencedSeriesSequence"]
    ]

    /// F.5 Type 1C keys whose presence is conditioned by the same Attribute
    /// being present in the referenced SOP Instance.
    static let referencedInstanceConditionalKeys:[DICOMDirectoryRecordType:Set<String>] = [
        .presentation: ["ReferencedSeriesSequence", "BlendingSequence"],
        .spectroscopy: ["ReferencedImageEvidenceSequence"],
        .encapsulatedDocument: ["HL7InstanceIdentifier"],
        .implant: ["ImplantSize"],
        .radiotherapy: ["UserContentLabel", "UserContentLongLabel"],
        .waveformPresentation: ["ReferencedSeriesSequence"]
    ]
}

extension DICOMDirectoryRecordType {
    /// Types whose unconditional top-level PS3.3 F.5 and included-macro keys
    /// are represented by the validator. Conditional keys remain separate.
    public static var unconditionalKeyValidation2026d:Set<Self> {
        return Set(DICOMDirectoryRecordSchemas.requirements.keys)
    }
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

    /// Validates the represented Type 1, Type 2 and common Type 1C keys from
    /// PS3.3 Annex F. This is independent of media-profile validation.
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

            if type == .private {
                appendMissingOrEmptyConditionalKey(
                    "PrivateRecordUID",
                    reason: "Directory Record Type PRIVATE requires Type 1C key PrivateRecordUID",
                    record: record,
                    results: &results
                )
            }

            let hasReferencedSOPKey = DICOMDirectoryRecordSchemas.referencedSOPKeys
                .dropFirst()
                .contains { record.item.element(withName: $0) != nil }
            if hasReferencedSOPKey {
                for name in DICOMDirectoryRecordSchemas.referencedSOPKeys {
                    appendMissingOrEmptyConditionalKey(
                        name,
                        reason: "Directory Record references a SOP Instance and requires Type 1C key \(name)",
                        record: record,
                        results: &results
                    )
                }
            }

            if DICOMDirectoryRecordSchemas.specificCharacterSetTypes.contains(type),
               recordUsesExtendedCharacterSet(record) {
                appendMissingOrEmptyConditionalKey(
                    "SpecificCharacterSet",
                    reason: "Directory Record Type \(type.rawValue) uses an extended character set in a key and requires Type 1C key SpecificCharacterSet",
                    record: record,
                    results: &results
                )
            }

            for name in DICOMDirectoryRecordSchemas.conditionalType1Keys[type] ?? [] {
                if let element = record.item.element(withName: name), isEmptyDirectoryValue(element) {
                    results.append(ValidationResult(
                        element,
                        message: "Directory Record Type \(type.rawValue) has an empty Type 1C key \(name)",
                        severity: .Error
                    ))
                }
            }

            if type == .structuredReport,
               normalizedDirectoryString(record.item.element(withName: "VerificationFlag")) == "VERIFIED" {
                appendMissingOrEmptyConditionalKey(
                    "VerificationDateTime",
                    reason: "SR DOCUMENT with VerificationFlag VERIFIED requires Type 1C key VerificationDateTime",
                    record: record,
                    results: &results
                )
            }

            if type == .hangingProtocol {
                validateHangingProtocolDefinitionItems(record, results: &results)
            }
            if type == .inventory {
                validateScopeOfInventory(record, results: &results)
            }

            validateIncludedMacros(record.elements, results: &results)
        }
        return results
    }

    private func validateIncludedMacros(
        _ elements:[DataElement],
        results:inout [ValidationResult]
    ) {
        for element in elements {
            guard let sequence = element as? DataSequence else { continue }
            if sequence.name == "IconImageSequence" {
                validateIconImageSequence(sequence, results: &results)
            }
            if DICOMDirectoryRecordSchemas.sopInstanceReferenceSequenceNames.contains(sequence.name) {
                validateSOPInstanceReferenceSequence(sequence, results: &results)
            }
            if sequence.name.hasSuffix("CodeSequence") || sequence.name == "AnatomicRegionSequence" {
                for item in sequence.items {
                    validateCodedEntry(item, sequenceName: sequence.name, results: &results)
                }
            }
            for item in sequence.items {
                validateIncludedMacros(item.elements, results: &results)
            }
        }
    }

    private func validateIconImageSequence(
        _ sequence:DataSequence,
        results:inout [ValidationResult]
    ) {
        guard sequence.items.count == 1 else {
            results.append(ValidationResult(
                sequence,
                message: "Icon Image Sequence requires exactly one Item",
                severity: .Error
            ))
            return
        }
        let item = sequence.items[0]
        let required = [
            "SamplesPerPixel", "PhotometricInterpretation", "Rows", "Columns",
            "BitsAllocated", "BitsStored", "HighBit", "PixelRepresentation",
            "PixelData"
        ]
        for name in required {
            appendRequiredMacroValue(
                name,
                reason: "Icon Image Item requires Type 1 key \(name)",
                item: item,
                results: &results
            )
        }

        if let samples = directoryUInt16(item, name: "SamplesPerPixel"), samples != 1 {
            appendIconError(item, "SamplesPerPixel shall be 1", results: &results)
        }
        let photometric = normalizedDirectoryString(item.element(withName: "PhotometricInterpretation"))
        if let photometric,
           !["MONOCHROME1", "MONOCHROME2", "PALETTE COLOR"].contains(photometric) {
            appendIconError(
                item,
                "PhotometricInterpretation shall be MONOCHROME1, MONOCHROME2, or PALETTE COLOR",
                results: &results
            )
        }
        if let rows = directoryUInt16(item, name: "Rows"), rows == 0 {
            appendIconError(item, "Rows shall be greater than zero", results: &results)
        }
        if let columns = directoryUInt16(item, name: "Columns"), columns == 0 {
            appendIconError(item, "Columns shall be greater than zero", results: &results)
        }
        if let bitsAllocated = directoryUInt16(item, name: "BitsAllocated"),
           bitsAllocated != 1 && bitsAllocated != 8 {
            appendIconError(item, "BitsAllocated shall be 1 or 8", results: &results)
        }
        if let bitsStored = directoryUInt16(item, name: "BitsStored"),
           bitsStored != 1 && bitsStored != 8 {
            appendIconError(item, "BitsStored shall be 1 or 8", results: &results)
        }
        if let bitsStored = directoryUInt16(item, name: "BitsStored"),
           let highBit = directoryUInt16(item, name: "HighBit"),
           bitsStored == 0 || highBit != bitsStored - 1 {
            appendIconError(item, "HighBit shall equal BitsStored minus one", results: &results)
        }
        if let representation = directoryUInt16(item, name: "PixelRepresentation"),
           representation != 0 {
            appendIconError(item, "PixelRepresentation shall be unsigned (0)", results: &results)
        }
        if item.element(withName: "PlanarConfiguration") != nil {
            appendIconError(item, "PlanarConfiguration shall not be present", results: &results)
        }
        if let aspectRatio = normalizedDirectoryString(item.element(withName: "PixelAspectRatio")),
           aspectRatio != "1\\1" {
            appendIconError(item, "PixelAspectRatio shall be 1\\1 when present", results: &results)
        }
        if photometric == "PALETTE COLOR" {
            if directoryUInt16(item, name: "BitsAllocated") != 8 {
                appendIconError(
                    item,
                    "PALETTE COLOR requires BitsAllocated of 8",
                    results: &results
                )
            }
            for name in [
                "RedPaletteColorLookupTableDescriptor",
                "GreenPaletteColorLookupTableDescriptor",
                "BluePaletteColorLookupTableDescriptor",
                "RedPaletteColorLookupTableData",
                "GreenPaletteColorLookupTableData",
                "BluePaletteColorLookupTableData"
            ] {
                appendRequiredMacroValue(
                    name,
                    reason: "PALETTE COLOR Icon Image Item requires \(name)",
                    item: item,
                    results: &results
                )
            }
        }
        validateIconPixelDataLength(item, results: &results)
    }

    private func validateIconPixelDataLength(
        _ item:DataItem,
        results:inout [ValidationResult]
    ) {
        guard let rows = directoryUInt16(item, name: "Rows"), rows > 0,
              let columns = directoryUInt16(item, name: "Columns"), columns > 0,
              let bitsAllocated = directoryUInt16(item, name: "BitsAllocated"),
              bitsAllocated == 1 || bitsAllocated == 8,
              let pixelData = item.element(withName: "PixelData"),
              pixelData.length >= 0 else { return }
        let bitCount = UInt64(rows) * UInt64(columns) * UInt64(bitsAllocated)
        let unpaddedByteCount = (bitCount + 7) / 8
        let expectedByteCount = unpaddedByteCount + (unpaddedByteCount % 2)
        if UInt64(pixelData.length) != expectedByteCount {
            appendIconError(
                pixelData,
                "PixelData length \(pixelData.length) does not match the expected \(expectedByteCount) bytes",
                results: &results
            )
        }
    }

    private func appendIconError(
        _ source:DataElement,
        _ detail:String,
        results:inout [ValidationResult]
    ) {
        results.append(ValidationResult(
            source,
            message: "Icon Image \(detail)",
            severity: .Error
        ))
    }

    private func directoryUInt16(_ item:DataItem, name:String) -> UInt16? {
        return item.element(withName: name)?.value as? UInt16
    }

    private func validateSOPInstanceReferenceSequence(
        _ sequence:DataSequence,
        results:inout [ValidationResult]
    ) {
        if sequence.items.isEmpty {
            results.append(ValidationResult(
                sequence,
                message: "\(sequence.name) requires one or more Items",
                severity: .Error
            ))
        }
        for item in sequence.items {
            appendRequiredMacroValue(
                "ReferencedSOPClassUID",
                reason: "\(sequence.name) SOP Instance Reference Item requires ReferencedSOPClassUID",
                item: item,
                results: &results
            )
            appendRequiredMacroValue(
                "ReferencedSOPInstanceUID",
                reason: "\(sequence.name) SOP Instance Reference Item requires ReferencedSOPInstanceUID",
                item: item,
                results: &results
            )
        }
    }

    private func validateCodedEntry(
        _ item:DataItem,
        sequenceName:String,
        results:inout [ValidationResult]
    ) {
        let valueNames = ["CodeValue", "LongCodeValue", "URNCodeValue"]
        let presentValues = valueNames.filter {
            guard let element = item.element(withName: $0) else { return false }
            return !isEmptyDirectoryValue(element)
        }
        if presentValues.count != 1 {
            results.append(ValidationResult(
                item,
                message: "\(sequenceName) coded entry requires exactly one of CodeValue, LongCodeValue, or URNCodeValue",
                severity: .Error
            ))
        }
        appendRequiredMacroValue(
            "CodeMeaning",
            reason: "\(sequenceName) coded entry requires CodeMeaning",
            item: item,
            results: &results
        )
        if presentValues.contains("CodeValue") || presentValues.contains("LongCodeValue") {
            appendRequiredMacroValue(
                "CodingSchemeDesignator",
                reason: "\(sequenceName) coded entry with CodeValue or LongCodeValue requires CodingSchemeDesignator",
                item: item,
                results: &results
            )
        }
        if item.element(withName: "CodingSchemeDesignator") == nil,
           item.element(withName: "CodingSchemeVersion") != nil {
            results.append(ValidationResult(
                item,
                message: "\(sequenceName) coded entry shall not contain CodingSchemeVersion without CodingSchemeDesignator",
                severity: .Error
            ))
        }
        if item.element(withName: "ContextIdentifier") != nil {
            appendRequiredMacroValue(
                "MappingResource",
                reason: "\(sequenceName) coded entry with ContextIdentifier requires MappingResource",
                item: item,
                results: &results
            )
            appendRequiredMacroValue(
                "ContextGroupVersion",
                reason: "\(sequenceName) coded entry with ContextIdentifier requires ContextGroupVersion",
                item: item,
                results: &results
            )
        }
        if normalizedDirectoryString(item.element(withName: "ContextGroupExtensionFlag")) == "Y" {
            appendRequiredMacroValue(
                "ContextGroupLocalVersion",
                reason: "\(sequenceName) extended coded entry requires ContextGroupLocalVersion",
                item: item,
                results: &results
            )
            appendRequiredMacroValue(
                "ContextGroupExtensionCreatorUID",
                reason: "\(sequenceName) extended coded entry requires ContextGroupExtensionCreatorUID",
                item: item,
                results: &results
            )
        }
    }

    private func appendRequiredMacroValue(
        _ name:String,
        reason:String,
        item:DataItem,
        results:inout [ValidationResult]
    ) {
        guard let element = item.element(withName: name), !isEmptyDirectoryValue(element) else {
            results.append(ValidationResult(item, message: reason, severity: .Error))
            return
        }
    }

    private func validateHangingProtocolDefinitionItems(
        _ record:DICOMDirectoryRecord,
        results:inout [ValidationResult]
    ) {
        guard let sequence = record.item.element(withName: "HangingProtocolDefinitionSequence") as? DataSequence else {
            return
        }
        for item in sequence.items {
            let modality = item.element(withName: "Modality")
            let anatomicRegion = item.element(withName: "AnatomicRegionSequence")
            let hasModality = modality.map { !isEmptyDirectoryValue($0) } ?? false
            let hasAnatomicRegion = anatomicRegion.map { !isEmptyDirectoryValue($0) } ?? false

            if !hasModality && !hasAnatomicRegion {
                results.append(ValidationResult(
                    item,
                    message: "Hanging Protocol Definition Item requires Modality or AnatomicRegionSequence",
                    severity: .Error
                ))
            }
            if let modality, isEmptyDirectoryValue(modality) {
                results.append(ValidationResult(
                    modality,
                    message: "Hanging Protocol Definition Item has an empty Type 1C key Modality",
                    severity: .Error
                ))
            }
            if let anatomicRegion, isEmptyDirectoryValue(anatomicRegion) {
                results.append(ValidationResult(
                    anatomicRegion,
                    message: "Hanging Protocol Definition Item has an empty Type 1C key AnatomicRegionSequence",
                    severity: .Error
                ))
            }
            if hasAnatomicRegion && item.element(withName: "Laterality") == nil {
                results.append(ValidationResult(
                    item,
                    message: "Hanging Protocol Definition Item with AnatomicRegionSequence requires Type 2C key Laterality",
                    severity: .Error
                ))
            }
        }
    }

    private func validateScopeOfInventory(
        _ record:DICOMDirectoryRecord,
        results:inout [ValidationResult]
    ) {
        guard let scope = record.item.element(withName: "ScopeOfInventorySequence") as? DataSequence else {
            return
        }
        if scope.items.count > 1 {
            results.append(ValidationResult(
                scope,
                message: "ScopeOfInventorySequence permits zero or one Item",
                severity: .Error
            ))
        }
        for item in scope.items {
            let mechanisms = normalizedDirectoryStrings(
                item.element(withName: "ExtendedMatchingMechanisms")
            )
            if item.element(withName: "ExtendedMatchingMechanisms") != nil && mechanisms.isEmpty {
                results.append(ValidationResult(
                    item,
                    message: "Scope of Inventory Item has an empty Type 1C key ExtendedMatchingMechanisms",
                    severity: .Error
                ))
            }
            if mechanisms.contains("TIMEZONE_ADJUST") {
                appendRequiredMacroValue(
                    "TimezoneOffsetFromUTC",
                    reason: "Scope of Inventory Item using TIMEZONE_ADJUST requires TimezoneOffsetFromUTC",
                    item: item,
                    results: &results
                )
            }
            if mechanisms.contains("RELATIONAL") {
                appendRequiredMacroValue(
                    "QueryRetrieveLevel",
                    reason: "Scope of Inventory Item using RELATIONAL requires QueryRetrieveLevel",
                    item: item,
                    results: &results
                )
            }
            validateSequenceCardinality(
                "RangeMatchingSequence",
                in: item,
                minimum: 2,
                maximum: 2,
                results: &results
            )
            validateSequenceCardinality(
                "ListOfUIDMatchingSequence",
                in: item,
                minimum: 1,
                maximum: nil,
                results: &results
            )
            validateSequenceCardinality(
                "EmptyValueMatchingSequence",
                in: item,
                minimum: 1,
                maximum: 1,
                results: &results
            )
            validateSequenceCardinality(
                "GeneralMatchingSequence",
                in: item,
                minimum: 1,
                maximum: 1,
                results: &results
            )
        }
    }

    private func validateSequenceCardinality(
        _ name:String,
        in item:DataItem,
        minimum:Int,
        maximum:Int?,
        results:inout [ValidationResult]
    ) {
        guard let sequence = item.element(withName: name) as? DataSequence else { return }
        let isInvalid = sequence.items.count < minimum || maximum.map {
            sequence.items.count > $0
        } ?? false
        if isInvalid {
            let expected = maximum == minimum ? "exactly \(minimum)" : "at least \(minimum)"
            results.append(ValidationResult(
                sequence,
                message: "\(name) requires \(expected) Item\(minimum == 1 && maximum == 1 ? "" : "s")",
                severity: .Error
            ))
        }
    }

    private func appendMissingOrEmptyConditionalKey(
        _ name:String,
        reason:String,
        record:DICOMDirectoryRecord,
        results:inout [ValidationResult]
    ) {
        guard let element = record.item.element(withName: name) else {
            results.append(ValidationResult(record.item, message: reason, severity: .Error))
            return
        }
        if isEmptyDirectoryValue(element) {
            results.append(ValidationResult(
                element,
                message: "\(reason) and it shall not be empty",
                severity: .Error
            ))
        }
    }

    private func recordUsesExtendedCharacterSet(_ record:DICOMDirectoryRecord) -> Bool {
        return directoryElementsUseExtendedCharacterSet(record.elements)
    }

    private func directoryElementsUseExtendedCharacterSet(_ elements:[DataElement]) -> Bool {
        return elements.contains { element in
            if directoryKeyUsesSpecificCharacterSet(element), let data = element.data,
               data.contains(where: { $0 > 0x7f || $0 == 0x1b }) {
                return true
            }
            if let sequence = element as? DataSequence {
                return sequence.items.contains {
                    directoryElementsUseExtendedCharacterSet($0.elements)
                }
            }
            return false
        }
    }

    private func directoryKeyUsesSpecificCharacterSet(_ element:DataElement) -> Bool {
        switch element.vr {
        case .LO, .LT, .PN, .SH, .ST, .UC, .UT:
            return true
        default:
            return false
        }
    }

    private func normalizedDirectoryString(_ element:DataElement?) -> String? {
        guard let value = element?.value as? String else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedDirectoryStrings(_ element:DataElement?) -> Set<String> {
        guard let value = element?.value as? String else { return [] }
        return Set(value.split(separator: "\\", omittingEmptySubsequences: true).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        }.filter { !$0.isEmpty })
    }

    private func isEmptyDirectoryValue(_ element:DataElement) -> Bool {
        if let sequence = element as? DataSequence {
            return sequence.items.isEmpty
        }
        switch element.vr {
        case .AE, .AS, .CS, .DS, .IS, .LO, .LT, .PN, .SH, .ST, .UC, .UI,
             .UR, .UT:
            guard let value = element.value as? String else { return true }
            return value.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).isEmpty
        default:
            return element.length == 0
        }
    }
}
