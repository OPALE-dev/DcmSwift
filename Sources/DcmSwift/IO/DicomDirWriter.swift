import Foundation

private final class DICOMDirectoryRecordNode {
    let item:DataItem
    var children:[DICOMDirectoryRecordNode] = []
    var offset:Int = 0

    init(item:DataItem) {
        self.item = item
    }
}

extension DicomDir {
    /// Returns whether a PS3.10 File ID uses one to eight components, each
    /// containing one to eight characters from the mandated repertoire.
    public static func isValidFileID(_ value:String) -> Bool {
        let normalized = value.replacingOccurrences(of: "/", with: "\\")
        let components = normalized.split(separator: "\\", omittingEmptySubsequences: false)
        guard (1...8).contains(components.count) else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        return components.allSatisfy { component in
            guard (1...8).contains(component.count) else { return false }
            return component.unicodeScalars.allSatisfy(allowed.contains)
        }
    }

    /// PS3.10 permits an empty File-set ID or up to sixteen characters from
    /// the same restricted repertoire used by File ID components.
    public static func isValidFileSetID(_ value:String) -> Bool {
        guard value.count <= 16 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// Preserves the original public construction API. Offsets are assigned
    /// only when the surrounding Part 10 file layout is known during writing.
    public func createDirectoryRecordSequence() -> DataSequence? {
        let dataSet = dataset ?? DataSet()
        if directoryRecordRoots.isEmpty {
            return buildDirectoryRecords(dataSet: dataSet).0
        }
        return buildDirectoryRecords(from: directoryRecordRoots, dataSet: dataSet)?.0
    }

    /// Builds and writes a PS3.10 Basic Directory object. Directory Record
    /// offsets are calculated from the final Explicit VR Little Endian byte
    /// layout and point to Item Tags, not Item Value Fields.
    public func writeDicomDir(atPath folderPath:String) -> Bool {
        guard DicomDir.isValidFileSetID(fileSetID),
              fileSetDescriptorFileID.map(DicomDir.isValidFileID) ?? true,
              fileSetDescriptorCharacterSet == nil || fileSetDescriptorFileID != nil,
              directoryRecordRoots.isEmpty || validReferencedFileIDs(in: directoryRecordRoots),
              (!directoryRecordRoots.isEmpty || imagesKeys.allSatisfy({ sopInstanceUID in
            guard let image = images[sopInstanceUID],
                  let fileID = image["ReferencedFileID"] as? String,
                  DicomDir.isValidFileID(fileID),
                  image["ReferencedSOPClassUIDInFile"] as? String != nil,
                  image["ReferencedTransferSyntaxUIDInFile"] as? String != nil else {
                return false
            }
            return true
        })) else { return false }

        let dataSet = DataSet()
        dataSet.hasPreamble = true
        dataSet.transferSyntax = TransferSyntax(TransferSyntax.explicitVRLittleEndian)

        _ = dataSet.set(value: Data([0x00, 0x01]), forTagName: "FileMetaInformationVersion")
        _ = dataSet.set(value: "1.2.840.10008.1.3.10", forTagName: "MediaStorageSOPClassUID")
        _ = dataSet.set(value: UID.generate(), forTagName: "MediaStorageSOPInstanceUID")
        _ = dataSet.set(value: TransferSyntax.explicitVRLittleEndian, forTagName: "TransferSyntaxUID")
        _ = dataSet.set(value: orgRoot, forTagName: "ImplementationClassUID")
        _ = dataSet.set(value: "DCMSWIFT_2", forTagName: "ImplementationVersionName")
        _ = dataSet.set(value: fileSetID, forTagName: "FileSetID")
        if let fileSetDescriptorFileID {
            _ = dataSet.set(value: normalizedFileID(fileSetDescriptorFileID), forTagName: "FileSetDescriptorFileID")
        }
        if let fileSetDescriptorCharacterSet {
            _ = dataSet.set(value: fileSetDescriptorCharacterSet, forTagName: "SpecificCharacterSetOfFileSetDescriptorFile")
        }
        let firstRoot = dataSet.set(value: UInt32(0), forTagName: "OffsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity")
        let lastRoot = dataSet.set(value: UInt32(0), forTagName: "OffsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity")
        _ = dataSet.set(value: UInt16(0), forTagName: "FileSetConsistencyFlag")

        let records:DICOMDirectoryRecordBuildResult
        if directoryRecordRoots.isEmpty {
            records = buildDirectoryRecords(dataSet: dataSet)
        } else {
            guard let genericRecords = buildDirectoryRecords(
                from: directoryRecordRoots,
                dataSet: dataSet
            ) else { return false }
            records = genericRecords
        }
        let (sequence, roots, orderedNodes) = records
        dataSet.add(element: sequence)
        dataSet.sortElements()
        _ = dataSet.recalculateFileMetaInformationGroupLength()

        guard assignDirectoryOffsets(
            dataSet: dataSet,
            sequence: sequence,
            roots: roots,
            orderedNodes: orderedNodes,
            firstRoot: firstRoot,
            lastRoot: lastRoot
        ) else { return false }

        dataset = dataSet
        hasPreamble = true
        guard validateDirectoryStructure().allSatisfy({ $0.severity != .Error }),
              validateDirectoryRecordKeys().allSatisfy({ $0.severity != .Error }) else {
            return false
        }
        let output = URL(fileURLWithPath: folderPath, isDirectory: true)
            .appendingPathComponent("DICOMDIR")
        return write(atPath: output.path)
    }

    private func buildDirectoryRecords(
        dataSet:DataSet
    ) -> DICOMDirectoryRecordBuildResult {
        let sequence = DataSequence(
            withTag: DataTag(withGroup: "0004", element: "1220"),
            parent: nil
        )
        sequence.vr = .SQ
        sequence.vrMethod = .Explicit
        var roots:[DICOMDirectoryRecordNode] = []
        var ordered:[DICOMDirectoryRecordNode] = []

        for patientID in patientsKeys {
            let patient = makeRecord(type: "PATIENT", sequence: sequence, dataSet: dataSet)
            append(value: patients[patientID] ?? "", name: "PatientName", to: patient.item, dataSet: dataSet)
            append(value: patientID, name: "PatientID", to: patient.item, dataSet: dataSet)
            roots.append(patient)
            ordered.append(patient)

            for studyUID in studiesKeys where studies[studyUID]?["PatientID"] as? String == patientID {
                let study = makeRecord(type: "STUDY", sequence: sequence, dataSet: dataSet)
                if let value = studies[studyUID]?["StudyDate"] { appendDirectoryValue(value, name: "StudyDate", to: study.item, dataSet: dataSet) }
                if let value = studies[studyUID]?["StudyTime"] { appendDirectoryValue(value, name: "StudyTime", to: study.item, dataSet: dataSet) }
                if let value = studies[studyUID]?["AccessionNumber"] { appendDirectoryValue(value, name: "AccessionNumber", to: study.item, dataSet: dataSet) }
                if let value = studies[studyUID]?["StudyDescription"] { appendDirectoryValue(value, name: "StudyDescription", to: study.item, dataSet: dataSet) }
                append(value: studyUID, name: "StudyInstanceUID", to: study.item, dataSet: dataSet)
                if let value = studies[studyUID]?["StudyID"] { appendDirectoryValue(value, name: "StudyID", to: study.item, dataSet: dataSet) }
                patient.children.append(study)
                ordered.append(study)

                for seriesUID in seriesKeys where series[seriesUID]?["StudyInstanceUID"] == studyUID {
                    let seriesNode = makeRecord(type: "SERIES", sequence: sequence, dataSet: dataSet)
                    append(value: series[seriesUID]?["Modality"] ?? "", name: "Modality", to: seriesNode.item, dataSet: dataSet)
                    append(value: seriesUID, name: "SeriesInstanceUID", to: seriesNode.item, dataSet: dataSet)
                    if let value = series[seriesUID]?["SeriesNumber"] { append(value: value, name: "SeriesNumber", to: seriesNode.item, dataSet: dataSet) }
                    study.children.append(seriesNode)
                    ordered.append(seriesNode)

                    for sopInstanceUID in imagesKeys where images[sopInstanceUID]?["SeriesInstanceUID"] as? String == seriesUID {
                        guard let image = images[sopInstanceUID] else { continue }
                        let imageNode = makeRecord(type: "IMAGE", sequence: sequence, dataSet: dataSet)
                        if let fileID = image["ReferencedFileID"] as? String {
                            append(value: normalizedFileID(fileID), name: "ReferencedFileID", to: imageNode.item, dataSet: dataSet)
                        }
                        if let value = image["ReferencedSOPClassUIDInFile"] as? String {
                            append(value: value, name: "ReferencedSOPClassUIDInFile", to: imageNode.item, dataSet: dataSet)
                        }
                        append(value: sopInstanceUID, name: "ReferencedSOPInstanceUIDInFile", to: imageNode.item, dataSet: dataSet)
                        if let value = image["ReferencedTransferSyntaxUIDInFile"] as? String {
                            append(value: value, name: "ReferencedTransferSyntaxUIDInFile", to: imageNode.item, dataSet: dataSet)
                        }
                        if let value = image["InstanceNumber"] { appendDirectoryValue(value, name: "InstanceNumber", to: imageNode.item, dataSet: dataSet) }
                        seriesNode.children.append(imageNode)
                        ordered.append(imageNode)
                    }
                }
            }
        }

        sequence.items = ordered.map(\.item)
        prepareLengths(sequence)
        return (sequence, roots, ordered)
    }

    private typealias DICOMDirectoryRecordBuildResult = (
        DataSequence,
        [DICOMDirectoryRecordNode],
        [DICOMDirectoryRecordNode]
    )

    private func buildDirectoryRecords(
        from definitions:[DICOMDirectoryRecordDefinition],
        dataSet:DataSet
    ) -> DICOMDirectoryRecordBuildResult? {
        let sequence = DataSequence(
            withTag: DataTag(withGroup: "0004", element: "1220"),
            parent: nil
        )
        sequence.dataset = dataSet
        sequence.vr = .SQ
        sequence.vrMethod = .Explicit
        var ordered:[DICOMDirectoryRecordNode] = []

        func build(
            _ definition:DICOMDirectoryRecordDefinition,
            depth:Int = 0
        ) -> DICOMDirectoryRecordNode? {
            guard depth <= 256,
                  DICOMDirectoryRecordType.standard2026d.contains(definition.type),
                  definition.elements.keys.allSatisfy({ !Self.generatedDirectoryElementNames.contains($0) }) else {
                return nil
            }
            let node = makeRecord(
                type: definition.type.rawValue,
                sequence: sequence,
                dataSet: dataSet
            )
            if case .string(let identifier)? = definition.elements["SpecificCharacterSet"] {
                node.item.characterSet = DICOMCharacterSet(specificCharacterSet: identifier)
            }
            for name in definition.elements.keys.sorted() {
                guard let value = definition.elements[name],
                      append(value: value, name: name, to: node.item, dataSet: dataSet) else {
                    return nil
                }
            }
            ordered.append(node)
            for childDefinition in definition.children {
                guard let child = build(childDefinition, depth: depth + 1) else { return nil }
                node.children.append(child)
            }
            return node
        }

        var roots:[DICOMDirectoryRecordNode] = []
        for definition in definitions {
            guard let root = build(definition) else { return nil }
            roots.append(root)
        }
        sequence.items = ordered.map(\.item)
        prepareLengths(sequence)
        return (sequence, roots, ordered)
    }

    private static let generatedDirectoryElementNames:Set<String> = [
        "OffsetOfTheNextDirectoryRecord",
        "RecordInUseFlag",
        "OffsetOfReferencedLowerLevelDirectoryEntity",
        "DirectoryRecordType"
    ]

    private func makeRecord(type:String, sequence:DataSequence, dataSet:DataSet) -> DICOMDirectoryRecordNode {
        let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
        append(value: UInt32(0), name: "OffsetOfTheNextDirectoryRecord", to: item, dataSet: dataSet)
        append(value: UInt16.max, name: "RecordInUseFlag", to: item, dataSet: dataSet)
        append(value: UInt32(0), name: "OffsetOfReferencedLowerLevelDirectoryEntity", to: item, dataSet: dataSet)
        append(value: type, name: "DirectoryRecordType", to: item, dataSet: dataSet)
        return DICOMDirectoryRecordNode(item: item)
    }

    private func append(value:Any, name:String, to item:DataItem, dataSet:DataSet) {
        guard let element = DataElement(withTagName: name, dataset: dataSet, parent: item),
              element.setValue(value) else { return }
        item.elements.append(element)
    }

    @discardableResult
    private func append(
        value:DICOMDirectoryValue,
        name:String,
        to item:DataItem,
        dataSet:DataSet,
        depth:Int = 0
    ) -> Bool {
        guard depth <= 256,
              let tag = DicomSpec.shared.dataTag(forName: name) else { return false }
        if case .sequence(let itemDefinitions) = value {
            guard DicomSpec.shared.vrForTag(withCode: tag.code) == .SQ else { return false }
            let sequence = DataSequence(withTag: tag, parent: item)
            sequence.dataset = dataSet
            sequence.vr = .SQ
            sequence.vrMethod = .Explicit
            sequence.length = -1
            for itemDefinition in itemDefinitions {
                let sequenceItem = DataItem(
                    withTag: DataTag(withGroup: "fffe", element: "e000"),
                    parent: sequence
                )
                sequenceItem.dataset = dataSet
                sequenceItem.characterSet = item.effectiveCharacterSet
                if case .string(let identifier)? = itemDefinition["SpecificCharacterSet"] {
                    sequenceItem.characterSet = DICOMCharacterSet(specificCharacterSet: identifier)
                }
                for childName in itemDefinition.keys.sorted() {
                    guard let childValue = itemDefinition[childName],
                          append(
                            value: childValue,
                            name: childName,
                            to: sequenceItem,
                            dataSet: dataSet,
                            depth: depth + 1
                          ) else { return false }
                }
                sequenceItem.elements.sort { $0.tagCode() < $1.tagCode() }
                sequenceItem.length = -1
                sequence.items.append(sequenceItem)
            }
            sequence.length = -1
            item.elements.append(sequence)
            return true
        }

        let element = DataElement(withTag: tag, dataset: dataSet, parent: item)
        element.vr = DicomSpec.shared.vrForTag(withCode: tag.code) ?? .UN
        element.characterSet = item.effectiveCharacterSet
        let rawValue:Any
        switch value {
        case .string(let value): rawValue = value
        case .data(let value): rawValue = value
        case .int16(let value): rawValue = value
        case .int32(let value): rawValue = value
        case .int64(let value): rawValue = value
        case .uint16(let value): rawValue = value
        case .uint32(let value): rawValue = value
        case .uint64(let value): rawValue = value
        case .float32(let value): rawValue = value
        case .float64(let value): rawValue = value
        case .int16Values(let value): rawValue = value
        case .int32Values(let value): rawValue = value
        case .int64Values(let value): rawValue = value
        case .uint16Values(let value): rawValue = value
        case .uint32Values(let value): rawValue = value
        case .uint64Values(let value): rawValue = value
        case .float32Values(let value): rawValue = value
        case .float64Values(let value): rawValue = value
        case .attributeTags(let value): rawValue = value
        case .sequence: return false
        }
        guard element.setValue(rawValue) else { return false }
        item.elements.append(element)
        return true
    }

    private func validReferencedFileIDs(
        in definitions:[DICOMDirectoryRecordDefinition]
    ) -> Bool {
        for definition in definitions {
            if let value = definition.elements["ReferencedFileID"] {
                guard case .string(let fileID) = value, DicomDir.isValidFileID(fileID) else {
                    return false
                }
            }
            if !validReferencedFileIDs(in: definition.children) { return false }
        }
        return true
    }

    private func appendDirectoryValue(_ value:Any, name:String, to item:DataItem, dataSet:DataSet) {
        if let date = value as? Date {
            let encoded = name == "StudyTime" ? date.dicomTimeString() : date.dicomDateString()
            append(value: encoded, name: name, to: item, dataSet: dataSet)
        } else {
            append(value: String(describing: value), name: name, to: item, dataSet: dataSet)
        }
    }

    private func prepareLengths(_ sequence:DataSequence) {
        for item in sequence.items {
            item.elements.sort { $0.tagCode() < $1.tagCode() }
            item.length = item.elements.reduce(0) {
                $0 + $1.toData(vrMethod: .Explicit, byteOrder: .LittleEndian).count
            }
        }
        sequence.length = sequence.items.reduce(0) { $0 + 8 + $1.length }
    }

    private func assignDirectoryOffsets(
        dataSet:DataSet,
        sequence:DataSequence,
        roots:[DICOMDirectoryRecordNode],
        orderedNodes:[DICOMDirectoryRecordNode],
        firstRoot:DataElement?,
        lastRoot:DataElement?
    ) -> Bool {
        prepareLengths(sequence)
        let sequenceStart = 132
            + dataSet.metaInformationHeaderElements.reduce(0) { $0 + $1.toData(vrMethod: .Explicit, byteOrder: .LittleEndian).count }
            + dataSet.datasetElements.prefix { $0 !== sequence }.reduce(0) { $0 + $1.toData(vrMethod: .Explicit, byteOrder: .LittleEndian).count }
        var itemOffset = sequenceStart + 12
        for node in orderedNodes {
            node.offset = itemOffset
            node.item.startOffset = itemOffset
            itemOffset += 8 + node.item.length
        }
        guard itemOffset <= Int(UInt32.max) else { return false }

        func assign(_ siblings:[DICOMDirectoryRecordNode]) {
            for (index, node) in siblings.enumerated() {
                let next = index + 1 < siblings.count ? siblings[index + 1].offset : 0
                let lower = node.children.first?.offset ?? 0
                _ = node.item.element(withName: "OffsetOfTheNextDirectoryRecord")?.setValue(UInt32(next))
                _ = node.item.element(withName: "OffsetOfReferencedLowerLevelDirectoryEntity")?.setValue(UInt32(lower))
                assign(node.children)
            }
        }
        assign(roots)
        _ = firstRoot?.setValue(UInt32(roots.first?.offset ?? 0))
        _ = lastRoot?.setValue(UInt32(roots.last?.offset ?? 0))
        prepareLengths(sequence)
        return true
    }

    private func normalizedFileID(_ value:String) -> String {
        return value.replacingOccurrences(of: "/", with: "\\")
            .split(separator: "\\", omittingEmptySubsequences: true)
            .map(String.init)
            .joined(separator: "\\")
    }
}
