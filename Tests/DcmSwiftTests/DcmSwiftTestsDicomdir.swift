//
//  DcmSwiftTestsDicomdir.swift
//  
//
//  Created by Colombe on 09/07/2021.
//

import XCTest
import DcmSwift

/**
 */
class DcmSwiftTestsDicomdir: XCTestCase {
    //MARK: TESTS DICOMDIR

    func testParseDicomDir() {
        
    }
    
    func testIsDicomDir() {
        let dicomDirPaths       = Bundle.module.paths(forResourcesOfType: "dicomdir", inDirectory: nil)
        let notDicomDirPaths    = Bundle.module.paths(forResourcesOfType: "notdicomdir", inDirectory: nil)
        
        
        if let pathTrue = dicomDirPaths.first {
            let b:Bool = DicomDir.isDicomDir(forPath:pathTrue)
            XCTAssertTrue(b)
        }
        
        if let pathFalse = notDicomDirPaths.first {
            let p:Bool = DicomDir.isDicomDir(forPath:pathFalse)
            XCTAssertFalse(p)
        }
    }
    
    func testIndex() {
        let pathFolder = "/Users/home/Documents/2_skull_ct/DICOM"
        if let dir = DicomDir.parse(atPath: pathFolder) {
            for(a,b) in dir.studies {
                Logger.info("a : \(a) b : \(b)")
            }
        }
    }
    
    func testIndexForStudy() {
        
    }
    
    func testAmputation() {
        let path = "/Users/home/Desktop/DICOM Example/TEST_DICOMDIR/DICOMDIR"
        let path_2 = "/Users/home/Desktop/DICOM Example/TEST_DICOMDIR"
        XCTAssertEqual(DicomDir.amputation(forPath: path),path_2)
    }
    
    func testCreateDirectoryRecordSequence() {
        let directory = makeDirectory()
        let sequence = directory.createDirectoryRecordSequence()

        XCTAssertEqual(sequence?.items.count, 5)
        XCTAssertEqual(
            (sequence?.items.first?.element(withName: "DirectoryRecordType")?.value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "PATIENT"
        )
    }
    
    func testWriteDicomDir() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let directory = makeDirectory()
        directory.fileSetID = "MEDIA_01"
        directory.fileSetDescriptorFileID = "README"
        directory.fileSetDescriptorCharacterSet = "ISO_IR 192"
        try Data("DICOM file-set description".utf8).write(
            to: temporaryDirectory.appendingPathComponent("README")
        )
        let referencedURL = temporaryDirectory
            .appendingPathComponent("PAT00001", isDirectory: true)
            .appendingPathComponent("IMG00001")
        try writeReferencedFile(to: referencedURL, sopInstanceUID: "1.2.3.4")
        XCTAssertTrue(directory.writeDicomDir(atPath: temporaryDirectory.path))

        let outputURL = temporaryDirectory.appendingPathComponent("DICOMDIR")
        let input = DicomInputStream(filePath: outputURL.path)
        let decoded = try XCTUnwrap(try input.readDataset())
        let sequence = decoded.element(forTagName: "DirectoryRecordSequence") as? DataSequence
        let items = try XCTUnwrap(sequence?.items)
        XCTAssertEqual(items.count, 5)
        guard items.count == 5 else { return }

        XCTAssertEqual(
            decoded.unsignedInteger32(forTag: "OffsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity"),
            UInt32(items[0].startOffset)
        )
        XCTAssertEqual(
            decoded.unsignedInteger32(forTag: "OffsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity"),
            UInt32(items[4].startOffset)
        )
        XCTAssertEqual(offset(named: "OffsetOfTheNextDirectoryRecord", in: items[0]), UInt32(items[4].startOffset))
        XCTAssertEqual(offset(named: "OffsetOfReferencedLowerLevelDirectoryEntity", in: items[0]), UInt32(items[1].startOffset))
        XCTAssertEqual(offset(named: "OffsetOfReferencedLowerLevelDirectoryEntity", in: items[1]), UInt32(items[2].startOffset))
        XCTAssertEqual(offset(named: "OffsetOfReferencedLowerLevelDirectoryEntity", in: items[2]), UInt32(items[3].startOffset))
        XCTAssertEqual(offset(named: "OffsetOfTheNextDirectoryRecord", in: items[4]), 0)
        XCTAssertEqual(offset(named: "OffsetOfReferencedLowerLevelDirectoryEntity", in: items[4]), 0)
        XCTAssertEqual(
            (items[3].element(withName: "ReferencedFileID")?.value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "PAT00001\\IMG00001"
        )
        XCTAssertTrue(items.allSatisfy { $0.length >= 0 })
        XCTAssertNotEqual(sequence?.length, -1)

        let bytes = try Data(contentsOf: outputURL)
        for item in items {
            XCTAssertEqual(bytes.subdata(in: item.startOffset..<(item.startOffset + 4)), Data([0xfe, 0xff, 0x00, 0xe0]))
            XCTAssertEqual(item.element(withName: "RecordInUseFlag")?.value as? UInt16, UInt16.max)
        }

        let reloaded = try XCTUnwrap(DicomDir(forPath: outputURL.path))
        XCTAssertEqual(reloaded.fileSetID, "MEDIA_01")
        XCTAssertEqual(reloaded.fileSetDescriptorFileID, "README")
        XCTAssertEqual(reloaded.fileSetDescriptorCharacterSet, "ISO_IR 192")
        XCTAssertTrue(reloaded.validateDirectoryStructure().isEmpty)
        XCTAssertTrue(reloaded.validateReferencedFiles().isEmpty)
        XCTAssertEqual(reloaded.patientsKeys, ["P1", "P2"])
        XCTAssertEqual(reloaded.studies["1.2.3"]?["PatientID"] as? String, "P1")
        XCTAssertEqual(reloaded.series["1.2.3.1"]?["StudyInstanceUID"], "1.2.3")
        XCTAssertEqual(reloaded.images["1.2.3.4"]?["SeriesInstanceUID"] as? String, "1.2.3.1")
        XCTAssertEqual(reloaded.index, [temporaryDirectory
            .appendingPathComponent("PAT00001")
            .appendingPathComponent("IMG00001").path])

        let nextOffsetElement = try XCTUnwrap(items[0].element(withName: "OffsetOfTheNextDirectoryRecord"))
        var malformedBytes = bytes
        malformedBytes.replaceSubrange(
            nextOffsetElement.dataOffset..<(nextOffsetElement.dataOffset + 4),
            with: Data([0x01, 0x00, 0x00, 0x00])
        )
        let malformedURL = temporaryDirectory.appendingPathComponent("BROKEN")
        try malformedBytes.write(to: malformedURL)
        XCTAssertNil(DicomDir(forPath: malformedURL.path))

        try writeReferencedFile(to: referencedURL, sopInstanceUID: "1.2.3.999")
        XCTAssertTrue(reloaded.validateReferencedFiles().contains {
            $0.message.contains("ReferencedSOPInstanceUIDInFile does not match")
        })
    }

    func testWriteDicomDirRejectsInvalidFileIDs() {
        let invalid = [
            "lowercase",
            "TOO_LONG_9",
            "BAD.NAME",
            "A\\B\\C\\D\\E\\F\\G\\H\\I",
            "A\\\\B"
        ]
        for value in invalid {
            XCTAssertFalse(DicomDir.isValidFileID(value), value)
        }
        XCTAssertTrue(DicomDir.isValidFileID("PAT00001/IMG00001"))
        XCTAssertTrue(DicomDir.isValidFileSetID("MEDIA_01"))
        XCTAssertTrue(DicomDir.isValidFileSetID(""))
        XCTAssertFalse(DicomDir.isValidFileSetID("lowercase"))
        XCTAssertFalse(DicomDir.isValidFileSetID("12345678901234567"))

        let directory = makeDirectory()
        directory.images["1.2.3.4"]?["ReferencedFileID"] = "bad-name"
        XCTAssertFalse(directory.writeDicomDir(atPath: FileManager.default.temporaryDirectory.path))
        directory.images["1.2.3.4"]?["ReferencedFileID"] = "PAT00001\\IMG00001"
        directory.fileSetID = "INVALID-LABEL"
        XCTAssertFalse(directory.writeDicomDir(atPath: FileManager.default.temporaryDirectory.path))
        directory.fileSetID = ""
        directory.fileSetDescriptorCharacterSet = "ISO_IR 192"
        XCTAssertFalse(directory.writeDicomDir(atPath: FileManager.default.temporaryDirectory.path))
    }

    func testDirectoryStructureValidationRejectsSemanticGraphErrors() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let directory = makeDirectory()
        XCTAssertTrue(directory.writeDicomDir(atPath: temporaryDirectory.path))
        let outputURL = temporaryDirectory.appendingPathComponent("DICOMDIR")
        let decoded = try XCTUnwrap(try DicomInputStream(filePath: outputURL.path).readDataset())
        let sequence = try XCTUnwrap(decoded.element(forTagName: "DirectoryRecordSequence") as? DataSequence)
        XCTAssertGreaterThan(sequence.items.count, 1)

        XCTAssertTrue(decoded.element(forTagName: "OffsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity")?
            .setValue(UInt32(sequence.items[1].startOffset)) == true)
        XCTAssertTrue(decoded.element(forTagName: "FileSetConsistencyFlag")?.setValue(UInt16.max) == true)
        XCTAssertTrue(sequence.items[3].element(withName: "OffsetOfTheNextDirectoryRecord")?
            .setValue(UInt32(sequence.items[3].startOffset)) == true)
        XCTAssertTrue(sequence.items[1].element(withName: "DirectoryRecordType")?.setValue("IMAGE") == true)
        XCTAssertTrue(sequence.items[4].element(withName: "DirectoryRecordType")?.setValue("PRIVATE") == true)
        let invalid = DicomDir()
        invalid.dataset = decoded
        invalid.filepath = outputURL.path
        let messages = invalid.validateDirectoryStructure().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("Last root Directory Record offset") })
        XCTAssertTrue(messages.contains { $0.contains("FileSetConsistencyFlag must be 0000H") })
        XCTAssertTrue(messages.contains { $0.contains("cycle or duplicate reference") })
        XCTAssertTrue(messages.contains { $0.contains("IMAGE is not permitted below PATIENT") })
        XCTAssertTrue(messages.contains { $0.contains("PRIVATE Directory Record requires PrivateRecordUID") })
    }

    func testPrimitiveDICOMDIRWithoutDirectoryInformationIsAccepted() throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let dataSet = DataSet()
        dataSet.hasPreamble = true
        dataSet.transferSyntax = TransferSyntax(TransferSyntax.explicitVRLittleEndian)
        _ = dataSet.set(value: Data([0x00, 0x01]), forTagName: "FileMetaInformationVersion")
        _ = dataSet.set(value: "1.2.840.10008.1.3.10", forTagName: "MediaStorageSOPClassUID")
        _ = dataSet.set(value: "2.25.123", forTagName: "MediaStorageSOPInstanceUID")
        _ = dataSet.set(value: TransferSyntax.explicitVRLittleEndian, forTagName: "TransferSyntaxUID")
        _ = dataSet.set(value: "2.25.22010055", forTagName: "ImplementationClassUID")
        _ = dataSet.set(value: "PRIMITIVE", forTagName: "FileSetID")
        let file = try XCTUnwrap(DicomFile(withDataset: dataSet, hasPreamble: true))
        XCTAssertTrue(file.write(atPath: temporaryURL.path))
        XCTAssertTrue(DicomDir.isDicomDir(forPath: temporaryURL.path))
        let directory = try XCTUnwrap(DicomDir(forPath: temporaryURL.path))
        XCTAssertEqual(directory.fileSetID, "PRIMITIVE")
        XCTAssertTrue(directory.validateDirectoryStructure().isEmpty)
    }

    private func makeDirectory() -> DicomDir {
        let directory = DicomDir()
        directory.patientsKeys = ["P1", "P2"]
        directory.patients = ["P1": "DOE^JANE", "P2": "DOE^JOHN"]
        directory.studiesKeys = ["1.2.3"]
        directory.studies = [
            "1.2.3": ["PatientID": "P1", "StudyID": "STUDY1"]
        ]
        directory.seriesKeys = ["1.2.3.1"]
        directory.series = [
            "1.2.3.1": [
                "StudyInstanceUID": "1.2.3",
                "Modality": "CT",
                "SeriesNumber": "1"
            ]
        ]
        directory.imagesKeys = ["1.2.3.4"]
        directory.images = [
            "1.2.3.4": [
                "SeriesInstanceUID": "1.2.3.1",
                "ReferencedFileID": "PAT00001/IMG00001",
                "ReferencedSOPClassUIDInFile": "1.2.840.10008.5.1.4.1.1.2",
                "ReferencedTransferSyntaxUIDInFile": TransferSyntax.explicitVRLittleEndian,
                "InstanceNumber": "1"
            ]
        ]
        return directory
    }

    private func offset(named name:String, in item:DataItem) -> UInt32? {
        return item.element(withName: name)?.value as? UInt32
    }

    private func writeReferencedFile(to url:URL, sopInstanceUID:String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let dataSet = DataSet()
        dataSet.hasPreamble = true
        dataSet.transferSyntax = TransferSyntax(TransferSyntax.explicitVRLittleEndian)
        let sopClassUID = "1.2.840.10008.5.1.4.1.1.2"
        _ = dataSet.set(value: Data([0x00, 0x01]), forTagName: "FileMetaInformationVersion")
        _ = dataSet.set(value: sopClassUID, forTagName: "MediaStorageSOPClassUID")
        _ = dataSet.set(value: sopInstanceUID, forTagName: "MediaStorageSOPInstanceUID")
        _ = dataSet.set(value: TransferSyntax.explicitVRLittleEndian, forTagName: "TransferSyntaxUID")
        _ = dataSet.set(value: "2.25.22010055", forTagName: "ImplementationClassUID")
        _ = dataSet.set(value: sopClassUID, forTagName: "SOPClassUID")
        _ = dataSet.set(value: sopInstanceUID, forTagName: "SOPInstanceUID")
        let file = try XCTUnwrap(DicomFile(withDataset: dataSet, hasPreamble: true))
        XCTAssertTrue(file.write(atPath: url.path))
    }

}
