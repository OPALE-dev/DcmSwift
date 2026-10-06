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

    /// Preserves the original public construction API. Offsets are assigned
    /// only when the surrounding Part 10 file layout is known during writing.
    public func createDirectoryRecordSequence() -> DataSequence? {
        return buildDirectoryRecords(dataSet: dataset ?? DataSet()).0
    }

    /// Builds and writes a PS3.10 Basic Directory object. Directory Record
    /// offsets are calculated from the final Explicit VR Little Endian byte
    /// layout and point to Item Tags, not Item Value Fields.
    public func writeDicomDir(atPath folderPath:String) -> Bool {
        guard imagesKeys.allSatisfy({ sopInstanceUID in
            guard let image = images[sopInstanceUID],
                  let fileID = image["ReferencedFileID"] as? String,
                  DicomDir.isValidFileID(fileID),
                  image["ReferencedSOPClassUIDInFile"] as? String != nil,
                  image["ReferencedTransferSyntaxUIDInFile"] as? String != nil else {
                return false
            }
            return true
        }) else { return false }

        let dataSet = DataSet()
        dataSet.hasPreamble = true
        dataSet.transferSyntax = TransferSyntax(TransferSyntax.explicitVRLittleEndian)

        _ = dataSet.set(value: Data([0x00, 0x01]), forTagName: "FileMetaInformationVersion")
        _ = dataSet.set(value: "1.2.840.10008.1.3.10", forTagName: "MediaStorageSOPClassUID")
        _ = dataSet.set(value: UID.generate(), forTagName: "MediaStorageSOPInstanceUID")
        _ = dataSet.set(value: TransferSyntax.explicitVRLittleEndian, forTagName: "TransferSyntaxUID")
        _ = dataSet.set(value: orgRoot, forTagName: "ImplementationClassUID")
        _ = dataSet.set(value: "DCMSWIFT_2", forTagName: "ImplementationVersionName")
        _ = dataSet.set(value: "", forTagName: "FileSetID")
        let firstRoot = dataSet.set(value: UInt32(0), forTagName: "OffsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity")
        let lastRoot = dataSet.set(value: UInt32(0), forTagName: "OffsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity")
        _ = dataSet.set(value: UInt16(0), forTagName: "FileSetConsistencyFlag")

        let (sequence, roots, orderedNodes) = buildDirectoryRecords(dataSet: dataSet)
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
        let output = URL(fileURLWithPath: folderPath, isDirectory: true)
            .appendingPathComponent("DICOMDIR")
        return write(atPath: output.path)
    }

    private func buildDirectoryRecords(
        dataSet:DataSet
    ) -> (DataSequence, [DICOMDirectoryRecordNode], [DICOMDirectoryRecordNode]) {
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
