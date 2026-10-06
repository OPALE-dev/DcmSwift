import Foundation

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
        func visitEntity(startingAt start:Int, depth:Int = 0) -> Int? {
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

                if let lower = itemOffset("OffsetOfReferencedLowerLevelDirectoryEntity", item), lower != 0 {
                    _ = visitEntity(startingAt: lower, depth: depth + 1)
                }
                activePath.remove(current)
                guard let next = itemOffset("OffsetOfTheNextDirectoryRecord", item) else { return last }
                current = next
            }
            return last
        }

        let actualLastRoot = visitEntity(startingAt: firstRoot)
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

            let target = fileID.split(separator: "\\").reduce(root) {
                $0.appendingPathComponent(String($1))
            }.standardizedFileURL.resolvingSymlinksInPath()
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
        }
        return results
    }
}
