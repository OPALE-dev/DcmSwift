import Foundation

private enum DICOMDirectoryHierarchy {
    static let root:Set<String> = [
        "PATIENT", "HANGING PROTOCOL", "PALETTE", "IMPLANT", "IMPLANT ASSY",
        "IMPLANT GROUP", "INVENTORY", "PRIVATE"
    ]
    static let seriesChildren:Set<String> = [
        "IMAGE", "RT DOSE", "RT STRUCTURE SET", "RT PLAN", "RT TREAT RECORD",
        "PRESENTATION", "WAVEFORM", "SR DOCUMENT", "KEY OBJECT DOC",
        "SPECTROSCOPY", "RAW DATA", "REGISTRATION", "FIDUCIAL", "ENCAP DOC",
        "VALUE MAP", "STEREOMETRIC", "PLAN", "MEASUREMENT", "SURFACE",
        "SURFACE SCAN", "TRACT", "ASSESSMENT", "RADIOTHERAPY", "ANNOTATION",
        "WF PRESENTATION", "PRIVATE"
    ]
    static let allCurrent:Set<String> = Set(
        DICOMDirectoryRecordType.standard2026d.map(\.rawValue)
    )
    static let retired:Set<String> = [
        "PRINT QUEUE", "FILM SESSION", "FILM BOX", "IMAGE BOX", "OVERLAY",
        "MODALITY LUT", "VOI LUT", "CURVE", "TOPIC", "VISIT", "RESULTS",
        "INTERPRETATION", "STUDY COMPONENT", "STORED PRINT", "MRDR"
    ]

    static func children(of type:String) -> Set<String> {
        switch type {
        case "PATIENT": return ["STUDY", "PRIVATE"]
        case "STUDY": return ["SERIES", "PRIVATE"]
        case "SERIES": return seriesChildren
        case "PRIVATE": return allCurrent.union(retired)
        default: return ["PRIVATE"]
        }
    }
}

extension DicomDir {
    /// Validates the Basic Directory container and offset graph independently
    /// from any PS3.11 application profile or PS3.12 media format.
    public func validateDirectoryStructure() -> [ValidationResult] {
        guard let dataSet = dataset else {
            return [ValidationResult(self, message: "DICOMDIR has no Data Set", severity: .Error)]
        }

        var results:[ValidationResult] = []
        func error(_ object:Any, _ message:String) {
            results.append(ValidationResult(object, message: message, severity: .Error))
        }

        func warning(_ object:Any, _ message:String) {
            results.append(ValidationResult(object, message: message, severity: .Warning))
        }

        if dataSet.string(forTag: "MediaStorageSOPClassUID") != "1.2.840.10008.1.3.10" {
            error(dataSet, "DICOMDIR File Meta Information does not identify the Media Storage Directory SOP Class")
        }
        if dataSet.string(forTag: "TransferSyntaxUID") != TransferSyntax.explicitVRLittleEndian {
            error(dataSet, "DICOMDIR must use Explicit VR Little Endian")
        }
        guard let fileSetElement = dataSet.element(forTagName: "FileSetID") else {
            error(dataSet, "DICOMDIR is missing the Type 2 FileSetID element")
            return results
        }
        let fileSetID = (fileSetElement.value as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !DicomDir.isValidFileSetID(fileSetID) {
            error(fileSetElement, "FileSetID violates the PS3.10 character or 16-character limit")
        }
        let descriptorElement = dataSet.element(forTagName: "FileSetDescriptorFileID")
        if let descriptorElement,
           let rawDescriptorID = descriptorElement.value as? String {
            let descriptorID = rawDescriptorID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !DicomDir.isValidFileID(descriptorID) {
                error(descriptorElement, "FileSetDescriptorFileID violates PS3.10")
            }
        }
        if dataSet.element(forTagName: "SpecificCharacterSetOfFileSetDescriptorFile") != nil,
           descriptorElement == nil {
            error(dataSet, "Descriptor character set requires FileSetDescriptorFileID")
        }

        guard let sequence = dataSet.element(forTagName: "DirectoryRecordSequence") as? DataSequence else {
            // The Directory Information Module is optional for primitive
            // environments; File-set Identification remains mandatory.
            return results
        }
        guard let consistency = dataSet.element(forTagName: "FileSetConsistencyFlag") else {
            error(dataSet, "Directory Information Module is missing FileSetConsistencyFlag")
            return results
        }
        if consistency.value as? UInt16 != 0 {
            error(consistency, "FileSetConsistencyFlag must be 0000H")
        }

        let itemsByOffset = Dictionary(uniqueKeysWithValues: sequence.items.map { ($0.startOffset, $0) })
        func itemOffset(_ name:String, _ item:DataItem) -> Int? {
            guard let element = item.element(withName: name),
                  let value = element.value as? UInt32 else {
                error(item, "Directory Record is missing required UL element \(name)")
                return nil
            }
            return Int(value)
        }

        for item in sequence.items {
            _ = itemOffset("OffsetOfTheNextDirectoryRecord", item)
            _ = itemOffset("OffsetOfReferencedLowerLevelDirectoryEntity", item)
            guard let flag = item.element(withName: "RecordInUseFlag"),
                  let flagValue = flag.value as? UInt16 else {
                error(item, "Directory Record is missing RecordInUseFlag")
                continue
            }
            if flagValue == 0 {
                error(flag, "RecordInUseFlag 0000H is retired and shall never be present")
            }
            if item.element(withName: "DirectoryRecordType") == nil {
                error(item, "Directory Record is missing DirectoryRecordType")
            }
        }

        guard let firstElement = dataSet.element(forTagName: "OffsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity"),
              let firstValue = firstElement.value as? UInt32,
              let lastElement = dataSet.element(forTagName: "OffsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity"),
              let lastValue = lastElement.value as? UInt32 else {
            error(dataSet, "Directory Information Module is missing root Directory Record offsets")
            return results
        }
        let firstRoot = Int(firstValue)
        let declaredLastRoot = Int(lastValue)

        if sequence.items.isEmpty {
            if firstRoot != 0 || declaredLastRoot != 0 {
                error(sequence, "Empty Directory Record Sequence must have zero root offsets")
            }
            return results
        }
        if firstRoot == 0 || declaredLastRoot == 0 {
            error(sequence, "Non-empty Directory Record Sequence must have non-zero first and last root offsets")
            return results
        }

        var visited:Set<Int> = []
        var activePath:Set<Int> = []
        func recordType(of item:DataItem) -> String? {
            return (item.element(withName: "DirectoryRecordType")?.value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func visitEntity(
            startingAt start:Int,
            allowedTypes:Set<String>,
            parentDescription:String,
            depth:Int = 0
        ) -> Int? {
            guard depth <= 256 else {
                error(sequence, "Directory Record hierarchy exceeds the validation depth limit")
                return nil
            }
            var current = start
            var last:Int?
            while current != 0 {
                guard let item = itemsByOffset[current] else {
                    error(sequence, "Directory Record offset \(current) does not point to an Item")
                    return last
                }
                if activePath.contains(current) || visited.contains(current) {
                    error(item, "Directory Record graph contains a cycle or duplicate reference at offset \(current)")
                    return last
                }
                visited.insert(current)
                activePath.insert(current)
                last = current

                guard let type = recordType(of: item), !type.isEmpty else {
                    activePath.remove(current)
                    return last
                }
                if DICOMDirectoryHierarchy.retired.contains(type) {
                    warning(item, "Directory Record Type \(type) is retired")
                } else if !DICOMDirectoryHierarchy.allCurrent.contains(type) {
                    error(item, "Unknown Directory Record Type \(type)")
                }
                if !allowedTypes.contains(type) {
                    error(item, "Directory Record Type \(type) is not permitted below \(parentDescription)")
                }
                if type == "PRIVATE", item.element(withName: "PrivateRecordUID") == nil {
                    error(item, "PRIVATE Directory Record requires PrivateRecordUID")
                }

                if let lower = itemOffset("OffsetOfReferencedLowerLevelDirectoryEntity", item), lower != 0 {
                    _ = visitEntity(
                        startingAt: lower,
                        allowedTypes: DICOMDirectoryHierarchy.children(of: type),
                        parentDescription: type,
                        depth: depth + 1
                    )
                }
                activePath.remove(current)
                guard let next = itemOffset("OffsetOfTheNextDirectoryRecord", item) else { return last }
                current = next
            }
            return last
        }

        let actualLastRoot = visitEntity(
            startingAt: firstRoot,
            allowedTypes: DICOMDirectoryHierarchy.root,
            parentDescription: "the Root Directory Entity"
        )
        if actualLastRoot != declaredLastRoot {
            error(lastElement, "Last root Directory Record offset does not match the root sibling chain")
        }
        if visited.count != sequence.items.count {
            error(sequence, "Directory Record Sequence contains unreachable or orphan Items")
        }
        return results
    }

    /// Verifies referenced Part 10 files and their identity attributes. This is
    /// file-set integrity validation, not PS3.11 application-profile validation.
    public func validateReferencedFiles() -> [ValidationResult] {
        guard let dataSet = dataset,
              let sequence = dataSet.element(forTagName: "DirectoryRecordSequence") as? DataSequence,
              let filepath else { return [] }

        var results:[ValidationResult] = []
        let root = URL(fileURLWithPath: filepath).deletingLastPathComponent()
            .standardizedFileURL.resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var seenFileIDs:Set<String> = []

        func error(_ object:Any, _ message:String) {
            results.append(ValidationResult(object, message: message, severity: .Error))
        }

        func isEmpty(_ element:DataElement) -> Bool {
            if let sequence = element as? DataSequence { return sequence.items.isEmpty }
            if let value = element.value as? String {
                return value.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).isEmpty
            }
            return element.length == 0
        }

        func resolvedURL(for fileID:String) -> URL {
            return fileID.split(separator: "\\").reduce(root) {
                $0.appendingPathComponent(String($1))
            }.standardizedFileURL.resolvingSymlinksInPath()
        }

        if let descriptorElement = dataSet.element(forTagName: "FileSetDescriptorFileID"),
           let rawDescriptorID = descriptorElement.value as? String {
            let descriptorID = rawDescriptorID.trimmingCharacters(in: .whitespacesAndNewlines)
            if DicomDir.isValidFileID(descriptorID) {
                seenFileIDs.insert(descriptorID)
                let descriptorURL = resolvedURL(for: descriptorID)
                if !descriptorURL.path.hasPrefix(rootPrefix) {
                    error(descriptorElement, "File-set Descriptor resolves outside the File-set")
                } else if !FileManager.default.fileExists(atPath: descriptorURL.path) {
                    error(descriptorElement, "File-set Descriptor file does not exist")
                }
            }
        }

        for item in sequence.items {
            guard let fileElement = item.element(withName: "ReferencedFileID"),
                  let rawFileID = fileElement.value as? String else { continue }
            let fileID = rawFileID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard DicomDir.isValidFileID(fileID) else {
                error(fileElement, "ReferencedFileID violates PS3.10")
                continue
            }
            if !seenFileIDs.insert(fileID).inserted {
                error(fileElement, "ReferencedFileID is not unique within the File-set")
            }

            let target = resolvedURL(for: fileID)
            guard target.path.hasPrefix(rootPrefix) else {
                error(fileElement, "ReferencedFileID resolves outside the File-set")
                continue
            }
            guard FileManager.default.fileExists(atPath: target.path) else {
                error(fileElement, "Referenced file does not exist in the File-set")
                continue
            }
            guard let referenced = DicomFile(forPath: target.path), let referencedDataSet = referenced.dataset else {
                error(fileElement, "Referenced file is not a readable DICOM Part 10 file")
                continue
            }

            let identities = [
                (record: "ReferencedSOPClassUIDInFile", file: "MediaStorageSOPClassUID"),
                (record: "ReferencedSOPInstanceUIDInFile", file: "MediaStorageSOPInstanceUID"),
                (record: "ReferencedTransferSyntaxUIDInFile", file: "TransferSyntaxUID")
            ]
            for identity in identities {
                guard let recordElement = item.element(withName: identity.record),
                      let recordValue = recordElement.value as? String else {
                    error(item, "Referenced file record is missing \(identity.record)")
                    continue
                }
                let expected = recordValue.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
                let actual = referencedDataSet.string(forTag: identity.file)
                if actual != expected {
                    error(recordElement, "\(identity.record) does not match the referenced Part 10 file")
                }
            }


            if let relatedGeneral = referencedDataSet.element(forTagName: "RelatedGeneralSOPClassUID") {
                if let recordElement = item.element(withName: "ReferencedRelatedGeneralSOPClassUIDInFile"),
                   !isEmpty(recordElement) {
                    let expected = (recordElement.value as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
                    let actual = (relatedGeneral.value as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
                    if expected != actual {
                        error(recordElement, "ReferencedRelatedGeneralSOPClassUIDInFile does not match the referenced Part 10 file")
                    }
                } else {
                    error(item, "Referenced SOP Instance encodes RelatedGeneralSOPClassUID and requires ReferencedRelatedGeneralSOPClassUIDInFile")
                }
            }

            let recordType = (item.element(withName: "DirectoryRecordType")?.value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            if let recordType,
               let conditionalKeys = DICOMDirectoryRecordSchemas.referencedInstanceConditionalKeys[
                    DICOMDirectoryRecordType(rawValue: recordType)
               ] {
                for name in conditionalKeys where referencedDataSet.element(forTagName: name) != nil {
                    guard let recordElement = item.element(withName: name), !isEmpty(recordElement) else {
                        error(item, "Referenced SOP Instance contains \(name) and requires the Directory Record Type 1C key")
                        continue
                    }
                    if !(recordElement is DataSequence),
                       let expected = recordElement.value as? String,
                       let actual = referencedDataSet.element(forTagName: name)?.value as? String,
                       expected.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)) !=
                        actual.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)) {
                        error(recordElement, "Directory Record key \(name) does not match the referenced Part 10 file")
                    }
                }
            }

            if recordType == DICOMDirectoryRecordType.structuredReport.rawValue ||
                recordType == DICOMDirectoryRecordType.keyObjectDocument.rawValue {
                let hasRootConceptModifier = (referencedDataSet.element(forTagName: "ContentSequence") as? DataSequence)?
                    .items.contains {
                        let relationship = ($0.element(withName: "RelationshipType")?.value as? String)?
                            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
                        return relationship == "HAS CONCEPT MOD"
                    } ?? false
                if hasRootConceptModifier {
                    guard let content = item.element(withName: "ContentSequence"), !isEmpty(content) else {
                        error(item, "Referenced SR root has HAS CONCEPT MOD children and requires Directory Record ContentSequence")
                        continue
                    }
                }
            }
        }
        return results
    }
}
