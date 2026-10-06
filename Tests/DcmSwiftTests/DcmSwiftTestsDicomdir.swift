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

        let directory = makeDirectory()
        directory.images["1.2.3.4"]?["ReferencedFileID"] = "bad-name"
        XCTAssertFalse(directory.writeDicomDir(atPath: FileManager.default.temporaryDirectory.path))
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

}
