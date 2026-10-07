//
//  DcmSwiftTests.swift
//  DcmSwiftTests
//
//  Created by Rafael Warnault, OPALE on 29/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import XCTest
@testable import DcmSwift

/**
 This class provides a suite of unit tests to qualify DcmSwift framework features.
 
 Mandatory regression tests use synthetic inputs. The two explicitly named
 external-corpus tests are an optional interoperability qualification run and
 read their input from `DCMSWIFT_INTEROP_CORPUS`.
 
 */
class DcmSwiftTests: XCTestCase {
    internal var filePath:String!
    private var finderTestDir:String = ""
    private var printDatasets = false
    
    /**
     We mostly prepare the output directory for test to write test files back.
     */
    override func setUp() {
        super.setUp()
        
        // Keep generated files isolated from the user's Desktop and other tests.
        self.finderTestDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dcmswift-tests-\(UUID().uuidString)", isDirectory: true)
            .path
        
        do {
            try FileManager.default.createDirectory(atPath: self.finderTestDir, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            NSLog("Unable to create directory \(error.debugDescription)")
        }
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(atPath: finderTestDir)
        super.tearDown()
    }
    
    // MARK: -
    public func testReadDicomDate() {
        let ds1 = "20001201"
        let dd1 = Date(dicomDate: ds1)

        let df = DateFormatter()
        df.dateFormat = "yyyy/MM/dd HH:mm:ss"
        let expected_res = "2000/12/01 00:00:00"

        XCTAssert(expected_res == df.string(from: dd1!))
        
        // ACR-NEMA date format
        let ds2 = "2000.12.01"
        let dd2 = Date(dicomDate: ds2)

        XCTAssert(expected_res == df.string(from: dd2!))
    }
    
    
    public func testWriteDicomDate() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        
        let ds1 = "2012/01/24"
        let d1  = dateFormatter.date(from: ds1)
        let dd1 = d1!.dicomDateString()
        
        XCTAssert(dd1 == "20120124")
    }

    public func testDicomDateWrongLength() {
        // Must be 8 or 10 bytes
        var ds = ""
        for i in 0...11 {
            if i == 8 || i == 10 {
                ds += "1"
                continue
            }

            let dd = Date(dicomDate: ds)
            XCTAssert(dd == nil)

            ds += "1"
        }
    }
    
    
    public func testReadDicomTime() {
        let df = DateFormatter()
        df.dateFormat = "yyyy/MM/dd HH:mm:ss"
        let expected_res = "2000/01/01 14:32:50"

        let ds1 = "143250"
        let dd1 = Date(dicomTime: ds1)

        XCTAssert(expected_res == df.string(from: dd1!))



        // ACR-NEMA time format
        let ds2 = "14:32:50"
        let dd2 = Date(dicomTime: ds2)

        XCTAssert(expected_res == df.string(from: dd2!))
    }


    public func testReadDicomTimeMidnight() {
        let ds1 = "240000"
        let dd1 = Date(dicomTime: ds1)

        XCTAssert(dd1 == nil)

        // ACR-NEMA time format
        let ds2 = "24:00:00"
        let dd2 = Date(dicomTime: ds2)

        XCTAssert(dd2 == nil)
    }


//    public func dicomTimeWrongLength() {
//        var ds1 = "1"
//        for _ in 0...3 {
//            print("ds1  \(ds1)")
//            let dd1 = Date(dicomTime: ds1)
//            XCTAssert(dd1 == nil)
//            ds1 += "11"
//        }
//    }

    public func testDicomTimeWeirdTime() {
        let ds1 = "236000"
        let dd1 = Date(dicomTime: ds1)

        XCTAssert(dd1 == nil)

        let ds2 = "235099"
        let dd2 = Date(dicomTime: ds2)

        XCTAssert(dd2 == nil)

        let ds3 = "255009"
        let dd3 = Date(dicomTime: ds3)

        XCTAssert(dd3 == nil)
    }
    
    public func testWriteDicomTime() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        
        let ds1 = "14:32:50"
        let d1  = dateFormatter.date(from: ds1)
        let dd1 = d1!.dicomTimeString()
                
        XCTAssert(dd1 == "143250.000000")
    }

    
    public func testCombineDateAndTime() {
        let df = DateFormatter()
        df.dateFormat = "yyyy/MM/dd HH:mm:ss"
        let expected_res = "2000/12/01 14:32:50"

        let ds1 = "20001201"
        let ts1 = "143250"
        
        let dateAndTime = Date(dicomDate: ds1, dicomTime: ts1)

        XCTAssert(expected_res == df.string(from: dateAndTime!))
    }
    
    
    
    
    public func testReadWriteDicomRange() {
        let ds1 = "20001201"
        let ds2 = "20021201"
        
        let dicomRange = "\(ds1)-\(ds2)"
        let dateRange = DateRange(dicomRange: dicomRange, type: VR.VR.DA)
        
        XCTAssert(dateRange!.range          == .between)
        XCTAssert(dateRange!.description    == "20001201-20021201")
    }
    
    

    public func testExternalDICOMCorpusReads() throws {
        let paths = try externalDICOMCorpusPaths()
        for path in paths {
            XCTAssertTrue(readFile(withPath: path), path)
        }
    }

    public func testExternalDICOMCorpusRoundTrips() throws {
        let paths = try externalDICOMCorpusPaths()
        for path in paths {
            XCTAssertTrue(readWriteFile(withPath: path), path)
        }
    }

    private func externalDICOMCorpusPaths() throws -> [String] {
        let environment = ProcessInfo.processInfo.environment
        guard let root = environment["DCMSWIFT_INTEROP_CORPUS"], !root.isEmpty else {
            // CI sets DCMSWIFT_REQUIRE_INTEROP_CORPUS so a missing corpus fails
            // the qualification instead of reporting a green skipped run.
            if environment["DCMSWIFT_REQUIRE_INTEROP_CORPUS"] == "1" {
                XCTFail("DCMSWIFT_REQUIRE_INTEROP_CORPUS is set but DCMSWIFT_INTEROP_CORPUS is not")
                return []
            }
            throw XCTSkip("Set DCMSWIFT_INTEROP_CORPUS to run optional interoperability qualification")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            XCTFail("DCMSWIFT_INTEROP_CORPUS is not a readable directory: \(root)")
            return []
        }
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root, isDirectory: true),
            includingPropertiesForKeys: keys
        ) else {
            XCTFail("Unable to enumerate DICOM interoperability corpus: \(root)")
            return []
        }
        let paths = enumerator.compactMap { entry -> String? in
            guard let url = entry as? URL,
                  ["dcm", "dicomdir"].contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true else {
                return nil
            }
            return url.path
        }.sorted()
        guard !paths.isEmpty else {
            XCTFail("No .dcm or .dicomdir file found below DCMSWIFT_INTEROP_CORPUS: \(root)")
            return []
        }
        return paths
    }
    
    
    
    
    private func readImageFile(withPath path:String, checksum:Bool = true) -> Bool {
#if os(macOS)
        let fileName = path.components(separatedBy: "/").last!.replacingOccurrences(of: ".dcm", with: "")
        var writePath = "\(self.finderTestDir)/\(fileName)-rwi-test.png"
        
        Logger.info("#########################################################")
        Logger.info("# PIXEL DATA TEST")
        Logger.info("#")
        Logger.info("# Source file : \(path)")
        Logger.info("# Destination file : \(writePath)")
        Logger.info("#")
        
        if let dicomFile = DicomFile(forPath: path) {
            if printDatasets { Logger.info("\(dicomFile.dataset.description )") }
            
            Logger.info("# Read succeeded")
            
            if let dicomImage = dicomFile.dicomImage {
                for i in 0 ..< 1 {
                    writePath = "\(self.finderTestDir)/\(fileName)-rwi-test-\(i)"
                    
                    if let image = dicomImage.image(forFrame: i) {
                        if dicomFile.dataset.transferSyntax == TransferSyntax.JPEG2000 ||
                           dicomFile.dataset.transferSyntax == TransferSyntax.JPEG2000Part2 ||
                           dicomFile.dataset.transferSyntax == TransferSyntax.JPEG2000LosslessOnly ||
                           dicomFile.dataset.transferSyntax == TransferSyntax.JPEG2000Part2Lossless {
                            _ = image.writeToFile(file: writePath, atomically: true, usingType: NSBitmapImageRep.FileType.jpeg2000)
                        }
                        else if dicomFile.dataset.transferSyntax == TransferSyntax.JPEGLossless ||
                                dicomFile.dataset.transferSyntax == TransferSyntax.JPEGLosslessNonhierarchical {
                            _ = image.writeToFile(file: writePath, atomically: true, usingType: NSBitmapImageRep.FileType.jpeg)
                        }
                        else {
                            _ = image.writeToFile(file: writePath, atomically: true, usingType: NSBitmapImageRep.FileType.bmp)
                        }
                    } else {
                        Logger.info("# Error: while extracting Pixel Data")
                        Logger.info("#")
                        Logger.info("#########################################################")
                        return false
                    }
                }
            } else {
                Logger.info("# Error: while extracting Pixel Data")
                Logger.info("#")
                Logger.info("#########################################################")
                return false
                
            }
            
            Logger.info("#")
            Logger.info("#########################################################")
            
            return true
        }
        
        return true
#else
        return false
#endif
    }
    
    
    
    /**
     This test reads a source DICOM file, updates its PatientName attribute, then writes a DICOM file copy.
     Then it re-reads the just updated DICOM file to set back its original PatientName and checks byte-for-byte integrity against the source DICOM file.
     */
    private func readUpdateWriteFile(withPath path:String, checksum:Bool = true) -> Bool {
        let fileName = path.components(separatedBy: "/").last!.replacingOccurrences(of: ".dcm", with: "")
        let writePath = "\(self.finderTestDir)/\(fileName)-rwu-test.dcm"
        
        Logger.info("#########################################################")
        Logger.info("# UPDATE INTEGRITY TEST")
        Logger.info("#")
        Logger.info("# Source file : \(path)")
        Logger.info("# Destination file : \(writePath)")
        Logger.info("#")
        
        if let dicomFile = DicomFile(forPath: path) {
            if printDatasets { Logger.info("\(dicomFile.dataset.description )") }
            
            Logger.info("# Read succeeded")
            
            let oldPatientName = dicomFile.dataset.string(forTag: "PatientName")
            
            if dicomFile.dataset.set(value: "Dicomix", forTagName: "PatientName") != nil {
                Logger.info("# Update succeeded")
            } else {
                Logger.error("# Update failed")
            }
            
            if (dicomFile.write(atPath: writePath)) {
                Logger.info("# Write succeeded")
                Logger.info("#")
                
                if let newDicomFile = DicomFile(forPath: writePath) {
                    Logger.info("# Re-read updated file read succeeded !!!")
                    Logger.info("#")
                    
                    if oldPatientName == nil {
                        Logger.error("# DICOM object do not provide a PatientName")
                        return false
                    }
                
                    if newDicomFile.dataset.set(value: oldPatientName!, forTagName: "PatientName") != nil {
                        Logger.error("# Restore PatientName failed")
                        return false
                    }
                    
                    if !newDicomFile.write(atPath: writePath) {
                        Logger.error("# Cannot write restored DICOM object")
                        return false
                    }
                    
                    if filesAreEqual(path, writePath) {
                        Logger.info("# Byte-for-byte comparison succeeded")
                    }
                    else {
                        Logger.info("# Error: files differ after restoring PatientName")
                        Logger.info("#")
                        Logger.info("#########################################################")
                        return false
                    }
                    
                } else {
                    Logger.error("# Re-read updated file read failed…")
                    Logger.info("#")
                    Logger.info("#########################################################")
                    return false
                }
            }
            else {
                Logger.error("# Error: while writing file: \(writePath)")
                Logger.info("#")
                Logger.info("#########################################################")
                return false
            }
            
            Logger.info("#")
            Logger.info("#########################################################")
            
            return true
        }
        
        return true
    }
    
    
    
    
    private func readWriteFile(withPath path:String, checksum:Bool = true) -> Bool {
        let fileName = path.components(separatedBy: "/").last!.replacingOccurrences(of: ".dcm", with: "")
        let writePath = "\(self.finderTestDir)/\(fileName)-rw-test.dcm"
        
        Logger.info("#########################################################")
        Logger.info("# READ/WRITE INTEGRITY TEST")
        Logger.info("#")
        Logger.info("# Source file : \(path)")
        Logger.info("# Destination file : \(writePath)")
        Logger.info("#")
        
        if let dicomFile = DicomFile(forPath: path) {
            if printDatasets { Logger.info("\(dicomFile.dataset.description )") }
            
            Logger.info("# Read succeeded")
            
            if (dicomFile.write(atPath: writePath)) {
                Logger.info("# Write succeeded")
                Logger.info("#")
                
                let sourceFileSize  = self.fileSize(filePath: path)
                let destFileSize    = self.fileSize(filePath: writePath)
                let deviationPercents = (Double(sourceFileSize) - Double(destFileSize)) / Double(sourceFileSize) * 100.0
                
                Logger.info("# Source file size : \(sourceFileSize) bytes")
                Logger.info("# Dest. file size  : \(destFileSize) bytes")
                
                if deviationPercents > 0.0 {
                    Logger.info("# Size deviation   : \(String(format:"%.8f", deviationPercents))%")
                }
                
                Logger.info("#")
                
                Logger.info("# Calculating checksum...")
                Logger.info("#")
                
                if filesAreEqual(path, writePath) {
                    Logger.info("# Byte-for-byte comparison succeeded")
                }
                else if onlyFileMetaInformationGroupLengthDiffers(sourcePath: path, destinationPath: writePath) {
                    Logger.info("# Source contained a non-conformant File Meta Information Group Length; normalized output accepted")
                }
                else {
                    Logger.info("# Error: files differ after round-trip")
                    Logger.info("#")
                    Logger.info("#########################################################")
                    return false
                }
            }
            else {
                Logger.info("# Error: while writing file: \(writePath)")
                Logger.info("#")
                Logger.info("#########################################################")
                return false
            }
            
            Logger.info("#")
            Logger.info("#########################################################")
            
            return true
        } else {
            Logger.info("# Error: cannot open file: \(writePath)")
            Logger.info("#")
            Logger.info("#########################################################")
            return false
        }
    }

    /// Retains byte-for-byte round-trip checks while allowing the writer to
    /// repair only the four-byte value of (0002,0000) in a Part 10 file.
    private func onlyFileMetaInformationGroupLengthDiffers(
        sourcePath: String,
        destinationPath: String
    ) -> Bool {
        guard let source = FileManager.default.contents(atPath: sourcePath),
              let destination = FileManager.default.contents(atPath: destinationPath),
              source.count == destination.count,
              source.count >= 144 else { return false }

        let differences = zip(source, destination).enumerated().compactMap {
            $0.element.0 == $0.element.1 ? nil : $0.offset
        }
        return !differences.isEmpty && differences.allSatisfy { (140..<144).contains($0) }
    }
    
    
    
    private func readFile(withPath path:String, checksum:Bool = true) -> Bool {
        let fileName = path.components(separatedBy: "/").last!.replacingOccurrences(of: ".dcm", with: "")
        let writePath = "\(self.finderTestDir)/\(fileName)-rw-test.dcm"
        
        Logger.info("#########################################################")
        Logger.info("# READ/WRITE INTEGRITY TEST")
        Logger.info("#")
        Logger.info("# Source file : \(path)")
        Logger.info("# Destination file : \(writePath)")
        Logger.info("#")
        
        if let dicomFile = DicomFile(forPath: path) {
            if printDatasets { Logger.info("\(dicomFile.dataset.description )") }
            
            Logger.info("# Read succeeded")
            Logger.info("#")
            
            if dicomFile.isCorrupted() {
                Logger.info("# WARNING : File is corrupted")
                Logger.info("#")
                return false
            }
            
            Logger.info("#########################################################")
            
            return true
        } else {
            Logger.info("# Error: cannot open file: \(writePath)")
            Logger.info("#")
            Logger.info("#########################################################")
            return false
        }
    }
    
    
    
    
    private func filePath(forName name:String) -> String {
        let bundle = Bundle(for: type(of: self))
        let path = bundle.path(forResource: name, ofType: "dcm")!
    
        return path
    }
    
    
    
    func fileSize(filePath:String) -> UInt64 {
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: filePath)
            return (attr[.size] as? NSNumber)?.uint64Value ?? 0
        } catch {
            print("Error: \(error)")
            
            return 0
        }
    }
    
    
    
    private func filesAreEqual(_ firstPath: String, _ secondPath: String) -> Bool {
        guard let first = FileManager.default.contents(atPath: firstPath),
              let second = FileManager.default.contents(atPath: secondPath) else {
            return false
        }
        return first == second
    }

    private func requireDICOMResource(_ name: String) throws -> String {
        let path = URL(fileURLWithPath: finderTestDir)
            .appendingPathComponent("\(name).dcm")
            .path
        if FileManager.default.fileExists(atPath: path) {
            return path
        }

        let dataset: DataSet
        if name.hasPrefix("rt_dose_") {
            dataset = syntheticRTDoseDataset()
        } else if name.hasPrefix("rt_RTXPLAN") {
            dataset = syntheticRTPlanDataset()
        } else if name.hasPrefix("rt_RTSTRUCT") {
            dataset = syntheticRTStructureSetDataset()
        } else {
            throw SyntheticFixtureError.unknownFixture(name)
        }
        let file = try XCTUnwrap(DicomFile(withDataset: dataset, hasPreamble: true))
        XCTAssertTrue(file.write(atPath: path), "Unable to write synthetic fixture \(name)")
        return path
    }

    private enum SyntheticFixtureError: Error {
        case unknownFixture(String)
    }

    private func syntheticBaseDataset(sopClassUID: String, modality: String) -> DataSet {
        let dataset = DataSet()
        dataset.hasPreamble = true
        dataset.transferSyntax = TransferSyntax(TransferSyntax.explicitVRLittleEndian)
        let instanceUID = "2.25.9990001"
        _ = dataset.set(value: Data([0x00, 0x01]), forTagName: "FileMetaInformationVersion")
        _ = dataset.set(value: sopClassUID, forTagName: "MediaStorageSOPClassUID")
        _ = dataset.set(value: instanceUID, forTagName: "MediaStorageSOPInstanceUID")
        _ = dataset.set(value: TransferSyntax.explicitVRLittleEndian, forTagName: "TransferSyntaxUID")
        _ = dataset.set(value: "2.25.9990000", forTagName: "ImplementationClassUID")
        _ = dataset.set(value: sopClassUID, forTagName: "SOPClassUID")
        _ = dataset.set(value: instanceUID, forTagName: "SOPInstanceUID")
        _ = dataset.set(value: modality, forTagName: "Modality")
        return dataset
    }

    private func syntheticRTDoseDataset() -> DataSet {
        let dataset = syntheticBaseDataset(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.481.2",
            modality: "RTDOSE"
        )
        _ = dataset.set(value: "2", forTagName: "NumberOfFrames")
        _ = dataset.set(value: UInt16(10), forTagName: "Rows")
        _ = dataset.set(value: UInt16(10), forTagName: "Columns")
        _ = dataset.set(value: UInt16(32), forTagName: "BitsAllocated")
        _ = dataset.set(value: UInt16(32), forTagName: "BitsStored")
        _ = dataset.set(value: UInt16(31), forTagName: "HighBit")
        _ = dataset.set(value: UInt16(0), forTagName: "PixelRepresentation")
        _ = dataset.set(value: UInt16(1), forTagName: "SamplesPerPixel")
        _ = dataset.set(value: "MONOCHROME2", forTagName: "PhotometricInterpretation")
        _ = dataset.set(value: "0.0000000107734", forTagName: "DoseGridScaling")

        var pixels = Data()
        for index in 0..<200 {
            let value: UInt32 = index == 143 ? 137_984_544 : 0
            pixels.append(uint32: value)
        }
        _ = dataset.set(value: pixels, forTagName: "PixelData")
        return dataset
    }

    private func syntheticRTPlanDataset() -> DataSet {
        let dataset = syntheticBaseDataset(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.481.5",
            modality: "RTPLAN"
        )
        addSequence(named: "ToleranceTableSequence", identifier: "ToleranceTableNumber", values: ["1", "2", "3"], to: dataset)
        addSequence(named: "FractionGroupSequence", identifier: "FractionGroupNumber", values: ["1"], to: dataset)
        addSequence(named: "BeamSequence", identifier: "BeamNumber", values: ["1", "2", "3"], to: dataset)
        addSequence(named: "PatientSetupSequence", identifier: "PatientSetupNumber", values: ["1"], to: dataset)
        return dataset
    }

    private func syntheticRTStructureSetDataset() -> DataSet {
        let dataset = syntheticBaseDataset(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.481.3",
            modality: "RTSTRUCT"
        )
        addSequence(
            named: "ReferencedFrameOfReferenceSequence",
            identifier: "FrameOfReferenceUID",
            values: ["1.2.840.113619.2.55.3.3767434740.12488.1173961280.931.803.0.11"],
            to: dataset
        )
        addSequence(
            named: "RTROIObservationsSequence",
            identifiers: [
                ["ObservationNumber": "1", "ReferencedROINumber": "1"],
                ["ObservationNumber": "2", "ReferencedROINumber": "2"],
                ["ObservationNumber": "3", "ReferencedROINumber": "3"]
            ],
            to: dataset
        )
        return dataset
    }

    private func addSequence(
        named name: String,
        identifier: String,
        values: [String],
        to dataset: DataSet
    ) {
        addSequence(named: name, identifiers: values.map { [identifier: $0] }, to: dataset)
    }

    private func addSequence(
        named name: String,
        identifiers: [[String: String]],
        to dataset: DataSet
    ) {
        guard let tag = DicomSpec.shared.dataTag(forName: name) else {
            XCTFail("Missing dictionary tag for synthetic sequence \(name)")
            return
        }
        let sequence = DataSequence(withTag: tag)
        sequence.vr = .SQ
        sequence.length = -1
        for identifiersByName in identifiers {
            let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
            item.length = -1
            for (identifierName, value) in identifiersByName.sorted(by: { $0.key < $1.key }) {
                guard let element = DataElement(withTagName: identifierName, dataset: dataset, parent: item) else {
                    XCTFail("Missing dictionary tag for synthetic identifier \(identifierName)")
                    continue
                }
                XCTAssertTrue(element.setValue(value))
                item.elements.append(element)
            }
            item.length = -1
            sequence.items.append(item)
        }
        sequence.length = -1
        dataset.add(element: sequence)
    }
    
    
    // Poulpy
    
    // RTDose tests
    
    public func testIsValid() throws {

        // TODO get files under RT folder, doesn't work atm; workaround, use filter to get "rt_" files
        var paths = Bundle.module.paths(forResourcesOfType: "dcm", inDirectory: nil)
        paths = paths.filter { $0.contains("rt_") }
        
        paths.forEach { path in
            if let dicomRT = DicomRT.init(forPath: path) {
                _ = Dose.isValid(dicomRT: dicomRT)
            }
        }
        
        let p = try requireDICOMResource("rt_dose_1.2.826.0.1.3680043.8.274.1.1.6549911257.77961.3133305374.424")
        
        if let dicomRT = DicomRT.init(forPath: p) {
            XCTAssertTrue(Dose.isValid(dicomRT: dicomRT))
        } else {
            XCTFail("Unable to read RT Dose fixture")
        }
        
        let p2 = try requireDICOMResource("rt_RTXPLAN.20110509.1010_Irregular")
        
        XCTAssertNil(DicomRT.init(forPath: p2), "RT Plan is not a pixel-based RT Dose object")
    }
    
    public func testGetDoseImageWidth() throws {
        
        let p = try requireDICOMResource("rt_dose_1.2.826.0.1.3680043.8.274.1.1.6549911257.77961.3133305374.424")
        
        if let dicomRT = DicomRT.init(forPath: p) {
            XCTAssertEqual(Dose.getDoseImageWidth(dicomRT: dicomRT), 10)
        } else {
            XCTFail("Unable to read RT Dose fixture")
        }
    }
    
    public func testGetDoseImageHeight() throws {
        let p = try requireDICOMResource("rt_dose_1.2.826.0.1.3680043.8.274.1.1.6549911257.77961.3133305374.424")
        
        if let dicomRT = DicomRT.init(forPath: p) {
            XCTAssertEqual(Dose.getDoseImageHeight(dicomRT: dicomRT), 10)
        } else {
            XCTFail("Unable to read RT Dose fixture")
        }
    }
    
#if os(macOS) || os(iOS)
    public func testToPNG() throws {
        let path = try requireDICOMResource("rt_dose_1.2.826.0.1.3680043.8.274.1.1.6549911257.77961.3133305374.424")
        let dcmFile = try XCTUnwrap(DicomFile(forPath: path))
        let dcmImage = try XCTUnwrap(DicomImage(dcmFile.dataset))
        dcmImage.toPNG(path: finderTestDir, baseName: dcmFile.fileName())
        let outputs = try FileManager.default.contentsOfDirectory(atPath: finderTestDir)
            .filter { $0.hasSuffix(".png") }
        XCTAssertEqual(outputs.count, 2)
    }
#endif
    
    public func testGetUnscaledDose() throws {
        let p = try requireDICOMResource("rt_dose_1.2.826.0.1.3680043.8.274.1.1.6549911257.77961.3133305374.424")
        
        if let dicomRT = DicomRT.init(forPath: p) {
            // 0
            let unscaledDose = Dose.unscaledDose(dicomRT: dicomRT, row: 1, column: 1, frame: 1)
            XCTAssertNotNil(unscaledDose)
            if let dose = unscaledDose {
                XCTAssertTrue(dose is UInt32)
                XCTAssertEqual(dose as! UInt32, 0)
            }
            
            // 137984544
            let unscaledDose2 = Dose.unscaledDose(dicomRT: dicomRT, row: 5, column: 4, frame: 2)
            XCTAssertNotNil(unscaledDose2)
            if let dose = unscaledDose2 {
                XCTAssertTrue(dose is UInt32)
                XCTAssertEqual(dose as! UInt32, 137984544)
            }
        } else {
            XCTFail("Unable to read RT Dose fixture")
        }
    }
    
    public func testGetDose() throws {
        let p = try requireDICOMResource("rt_dose_1.2.826.0.1.3680043.8.274.1.1.6549911257.77961.3133305374.424")
        
        if let dicomRT = DicomRT.init(forPath: p) {
            // 0
            let dose = Dose.getDose(dicomRT: dicomRT, row: 1, column: 1, frame: 1)
            XCTAssertNotNil(dose)
            XCTAssertEqual(dose!, 0)

            
            let dose2 = Dose.getDose(dicomRT: dicomRT, row: 5, column: 4, frame: 2)
            XCTAssertNotNil(dose2)
            XCTAssertEqual(dose2!, 1.4865626863296)
            
        } else {
            XCTFail("Unable to read RT Dose fixture")
        }
    }
    
    public func testGetDoseImage() throws {
        let p = try requireDICOMResource("rt_dose_1.2.826.0.1.3680043.8.274.1.1.6549911257.77961.3133305374.424")
        
        if let dicomRT = DicomRT.init(forPath: p) {
            let r = Dose.getDoseImage(dicomRT: dicomRT, atFrame: 1)
            
            XCTAssert(!r.isEmpty)
        } else {
            XCTFail("Unable to read RT Dose fixture")
        }
    }
    
    public func testGetDoseImages() throws {
        let p = try requireDICOMResource("rt_dose_1.2.826.0.1.3680043.8.274.1.1.6549911257.77961.3133305374.424")
        
        if let dicomRT = DicomRT.init(forPath: p) {
            let r = Dose.getDoseImages(dicomRT: dicomRT)
            
            XCTAssert(!r.isEmpty)
       
        } else {
            XCTFail("Unable to read RT Dose fixture")
        }
    }
    
    // test Plan
    
    public func testGetToleranceTableItem() throws {
        // rt_RTXPLAN.20110509.1010_Irregular.dcm
        
        let p = try requireDICOMResource("rt_RTXPLAN.20110509.1010_Irregular")
        
        if let dicomRT = DicomFile.init(forPath: p) {
            XCTAssertNotNil(Plan.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "ToleranceTableSequence", withNumber: "1"))
            XCTAssertNotNil(Plan.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "ToleranceTableSequence", withNumber: "2"))
            XCTAssertNotNil(Plan.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "ToleranceTableSequence", withNumber: "3"))
            
            XCTAssertNil(Plan.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "ToleranceTableSequence", withNumber: "4"))
       
        } else {
            XCTFail("Unable to read RT Plan fixture")
        }
    }
    
    public func testGetFractionGroupItem() throws {
        // rt_RTXPLAN.20110509.1010_Irregular.dcm
        
        let p = try requireDICOMResource("rt_RTXPLAN.20110509.1010_Irregular")
        
        if let dicomRT = DicomFile.init(forPath: p) {
            XCTAssertNotNil(Plan.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "FractionGroupSequence", withNumber: "1"))
            
            XCTAssertNil(Plan.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "FractionGroupSequence", withNumber: "2"))
            XCTAssertNil(Plan.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "FractionGroupSequence", withNumber: "3"))
            XCTAssertNil(Plan.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "FractionGroupSequence", withNumber: "4"))
       
        } else {
            XCTFail("Unable to read RT Plan fixture")
        }
    }
    
    public func testGetBeamItem() throws {
        // rt_RTXPLAN.20110509.1010_Irregular.dcm
        
        let p = try requireDICOMResource("rt_RTXPLAN.20110509.1010_Irregular")
        
        if let dicomRT = DicomFile.init(forPath: p) {
            XCTAssertNotNil(Plan.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "BeamSequence", withNumber: "1"))
            XCTAssertNotNil(Plan.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "BeamSequence", withNumber: "2"))
            XCTAssertNotNil(Plan.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "BeamSequence", withNumber: "3"))
            
            XCTAssertNil(Plan.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "BeamSequence", withNumber: "4"))
       
        } else {
            XCTFail("Unable to read RT Plan fixture")
        }
    }
    
    public func testGetPatientItem() throws {
        // rt_RTXPLAN.20110509.1010_Irregular.dcm
        
        let p = try requireDICOMResource("rt_RTXPLAN.20110509.1010_Irregular")
        
        if let dicomRT = DicomFile.init(forPath: p) {
            XCTAssertNotNil(Plan.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "PatientSetupSequence", withNumber: "1"))
            
            XCTAssertNil(Plan.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "PatientSetupSequence", withNumber: "2"))
            XCTAssertNil(Plan.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "PatientSetupSequence", withNumber: "3"))
            XCTAssertNil(Plan.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "PatientSetupSequence", withNumber: "4"))
       
        } else {
            XCTFail("Unable to read RT Plan fixture")
        }
    }
    
    
    // StructureSet
    
    public func testGetFrameOfReference() throws {
        // rt_RTSTRUCT.2.16.840.1.113669.2.931128.509887832.20120106104805.776010
        
        let path = try requireDICOMResource("rt_RTSTRUCT.2.16.840.1.113669.2.931128.509887832.20120106104805.776010")
        
        if let dicomRT = DicomFile.init(forPath: path) {
            XCTAssertNotNil(StructureSet.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "ReferencedFrameOfReferenceSequence", withNumber: "1.2.840.113619.2.55.3.3767434740.12488.1173961280.931.803.0.11"))
            
            // replaced 1 by 0 at the end
            XCTAssertNil(StructureSet.getItemInSequenceForNumber(dicomRT: dicomRT, forSequence: "PatientSetupSequence", withNumber: "1.2.840.113619.2.55.3.3767434740.12488.1173961280.931.803.0.10"))
            
        } else {
            XCTFail("Unable to read RT Structure Set fixture")
        }
    }
    
    public func testGetObservation() throws {
        // rt_RTSTRUCT.2.16.840.1.113669.2.931128.509887832.20120106104805.776010
        
        let path = try requireDICOMResource("rt_RTSTRUCT.2.16.840.1.113669.2.931128.509887832.20120106104805.776010")
        
        if let dicomRT = DicomFile.init(forPath: path) {
            XCTAssertNotNil(StructureSet.getObservation(dicomRT: dicomRT, observationNumber: "1"))
            XCTAssertNotNil(StructureSet.getObservation(dicomRT: dicomRT, observationNumber: "2"))
            XCTAssertNotNil(StructureSet.getObservation(dicomRT: dicomRT, observationNumber: "3"))
            
            XCTAssertNil(StructureSet.getObservation(dicomRT: dicomRT, observationNumber: "10"))
            
        } else {
            XCTFail("Unable to read RT Structure Set fixture")
        }
    }
    
    public func testGetObservationByROINumber() throws {
        // rt_RTSTRUCT.2.16.840.1.113669.2.931128.509887832.20120106104805.776010
        
        let path = try requireDICOMResource("rt_RTSTRUCT.2.16.840.1.113669.2.931128.509887832.20120106104805.776010")
        
        if let dicomRT = DicomFile.init(forPath: path) {
            XCTAssertNotNil(StructureSet.getObservationByROINumber(dicomRT: dicomRT, roiNumber: "1"))
            XCTAssertNotNil(StructureSet.getObservationByROINumber(dicomRT: dicomRT, roiNumber: "2"))
            XCTAssertNotNil(StructureSet.getObservationByROINumber(dicomRT: dicomRT, roiNumber: "3"))
            
            XCTAssertNil(StructureSet.getObservationByROINumber(dicomRT: dicomRT, roiNumber: "10"))
            
        } else {
            XCTFail("Unable to read RT Structure Set fixture")
        }
    }
}
