//
//  DcmSwiftTests.swift
//  DcmSwiftTests
//
//  Created by Rafael Warnault on 29/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import XCTest
import DcmSwift

/**
 This class provides a suite of unit tests to qualify DcmSwift framework features.
 
 It is sort of decomposed by categories using boolean attributes you can toggle to target some features
 more easily (`testDicomFileRead`, `testDicomFileWrite`, `testDicomImage`, etc.)

 Some of the tests, especially those done around actual files, are dynamically generated using NSInvocation
 for better integration and readability.
 
 */
class DcmSwiftTests: XCTestCase {
    // Configure the test suite with the following boolean attributes
    
    /// Run tests on DICOM Date and Time
    private static var testDicomDateAndTime     = true
    
    /// Run tests to read files (rely on embedded test files, dynamically generated)
    private static var testDicomFileRead        = true
    
    /// Run tests to write files (rely on embedded test files, dynamically generated)
    private static var testDicomFileWrite       = true
    
    /// Run tests to update dataset (rely on embedded test files, dynamically generated)
    private static var testDicomDataSet         = false
    
    /// Run tests to read image(s) (rely on embedded test files, dynamically generated)
    private static var testDicomImage           = false
    
    /// Run Age String (AS VR) related tests
    private static var testAgeString            = true
    
    /// Run
    private static var testUID                  = true
    
    /// Run DicomRT helpers tests
    private static var testRT                   = true

    
    internal var filePath:String!
    private var finderTestDir:String = ""
    private var printDatasets = false
    
    /**
     We mostly prepare the output directory for test to write test files back.
     */
    override func setUp() {
        super.setUp()
        
        // prepare a test output directory for rewritten files
        self.finderTestDir = String(NSString(string: "~/Desktop/DcmSwiftTests").expandingTildeInPath)
        
        do {
            try FileManager.default.createDirectory(atPath: self.finderTestDir, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            NSLog("Unable to create directory \(error.debugDescription)")
        }
    }
    
    override func tearDown() {
        // code here
        super.tearDown()
    }
    
    
    /**
     Override defaultTestSuite to ease generation of dynamic tests
     and coustomized configuration using boolean attributes
     */
    override class var defaultTestSuite: XCTestSuite {
        let suite = XCTestSuite(forTestCaseClass: DcmSwiftTests.self)
        let paths = Bundle.module.paths(forResourcesOfType: "dcm", inDirectory: nil)
                
        if testDicomDateAndTime {
            suite.addTest(DcmSwiftTests(selector: #selector(readDicomDate)))
            suite.addTest(DcmSwiftTests(selector: #selector(writeDicomDate)))
            suite.addTest(DcmSwiftTests(selector: #selector(dicomDateWrongLength)))
            suite.addTest(DcmSwiftTests(selector: #selector(readDicomTimeMidnight)))
            // TODO: fix it!?
            //suite.addTest(DcmSwiftTests(selector: #selector(dicomTimeWrongLength)))
            suite.addTest(DcmSwiftTests(selector: #selector(dicomTimeWeirdTime)))
            suite.addTest(DcmSwiftTests(selector: #selector(readDicomTime)))
            suite.addTest(DcmSwiftTests(selector: #selector(writeDicomTime)))
            suite.addTest(DcmSwiftTests(selector: #selector(combineDateAndTime)))
            suite.addTest(DcmSwiftTests(selector: #selector(readWriteDicomRange)))
        }
        
        
        if testAgeString {
            suite.addTest(DcmSwiftTests(selector: #selector(ageStringPositiveAge)))
            suite.addTest(DcmSwiftTests(selector: #selector(ageStringNegativeAge)))
            suite.addTest(DcmSwiftTests(selector: #selector(ageStringInitWithString)))
            suite.addTest(DcmSwiftTests(selector: #selector(ageStringAge)))
            suite.addTest(DcmSwiftTests(selector: #selector(ageStringValidate)))
            suite.addTest(DcmSwiftTests(selector: #selector(ageStringVariations)))
        }
        
        if testUID {
            suite.addTest(DcmSwiftTests(selector: #selector(validateUID)))
            suite.addTest(DcmSwiftTests(selector: #selector(generateUID)))
        }
        
        if testDicomFileRead {
            paths.forEach { path in
                let block: @convention(block) (DcmSwiftTests) -> Void = { t in
                    _ = t.readFile(withPath: path)
                }
                
                DcmSwiftTests.addFileTest(withName: "FileRead", inSuite: suite, withPath:path, block: block)
            }
        }
        
        
        if testDicomFileWrite {
            /**
             This test suite performs a read/write on a set of DICOM files without
             modifying them, them check the MD5 checksum to ensure the I/O features
             of DcmSwift work properly.
             */
            paths.forEach { path in
                let block: @convention(block) (DcmSwiftTests) -> Void = { t in
                    t.readWriteTest()
                }
                
                DcmSwiftTests.addFileTest(withName: "FileWrite", inSuite: suite, withPath:path, block: block)
            }
        }
        
        
        
        if testDicomDataSet {
            paths.forEach { path in
                let block: @convention(block) (DcmSwiftTests) -> Void = { t in
                    t.readUpdateWriteTest()
                }
                
                DcmSwiftTests.addFileTest(withName: "DataSet", inSuite: suite, withPath:path, block: block)
            }
        }
        
        if testDicomImage {
            paths.forEach { path in
                let block: @convention(block) (DcmSwiftTests) -> Void = { t in
                    t.readImageTest()
                }
                
                DcmSwiftTests.addFileTest(withName: "DicomImage", inSuite: suite, withPath:path, block: block)
            }
        }
        
        if testRT {
            suite.addTest(DcmSwiftTests(selector: #selector(testIsValid)))
            suite.addTest(DcmSwiftTests(selector: #selector(testGetDoseImageWidth)))
            suite.addTest(DcmSwiftTests(selector: #selector(testGetDoseImageHeight)))
        }
        
        return suite
    }
    
    
    private class func addFileTest(withName name: String, inSuite suite: XCTestSuite, withPath path:String, block: Any) {
        var fileName = String((path as NSString).deletingPathExtension.split(separator: "/").last!)
        fileName = (fileName as NSString).replacingOccurrences(of: "-", with: "_")
                 
        // with help of ObjC runtime we add new test method to class
        let implementation = imp_implementationWithBlock(block)
        let selectorName = "test_\(name)_\(fileName)"
        let selector = NSSelectorFromString(selectorName)
                        
        class_addMethod(DcmSwiftTests.self, selector, implementation, "v@:")
        
        // Generate a test for our specific selector
        let test = DcmSwiftTests(selector: selector)
        
        // Each test will take the size argument and use the instance variable in the test
        test.filePath = path
        
        // Add it to the suite, and the defaults handle the rest
        suite.addTest(test)
    }
    
    
    
    
    //MARK: -
    public func ageStringPositiveAge() {
        let currentDate = Date()
        var dateComponent = DateComponents()
        
        // two years in the past
        dateComponent.year = -2
                
        if let futureDate = Calendar.current.date(byAdding: dateComponent, to: currentDate) {
            // should not be nil
            XCTAssertNotNil(AgeString(birthdate: futureDate))
        }
    }
    
    public func ageStringNegativeAge() {
        let currentDate = Date()
        var dateComponent = DateComponents()
        
        // two years in the future
        dateComponent.year = 2
                
        if let futureDate = Calendar.current.date(byAdding: dateComponent, to: currentDate) {
            // should be nil
            XCTAssertNil(AgeString(birthdate: futureDate))
        }
    }

    // Tests Colombe
    
    func ageStringInitWithString() {
        let works = "005D"
        if let res = AgeString.init(ageString: works) {
            XCTAssertNotNil(res)
        }
        
        let dsntWorks = "marche pas"
        if let res = AgeString.init(ageString: dsntWorks) {
            XCTAssertNil(res)
        }
    }

    
    func ageStringValidate() {
        let works = "005D"
        if let astrWorks = AgeString.init(ageString: works) {
            XCTAssertTrue(astrWorks.validate(age: works))
        }
        
        let dsntWorks = "hello"
        if let astrDsntWorks = AgeString.init(ageString: dsntWorks) {
            XCTAssertFalse(astrDsntWorks.validate(age: dsntWorks))
        }
    }
    
    func ageStringAge() {
        let works = "005D"
        let astrWorks = AgeString.init(ageString: works)
        XCTAssertNotNil(astrWorks?.age(withPrecision: .days))
        
        let dsntWorks = "hello"
        let astrDsntWorks = AgeString.init(ageString: dsntWorks)
        XCTAssertNil(astrDsntWorks?.age(withPrecision: .days))
    }
    
    func ageStringVariations() {
        let ages = ["012A", "220M", "034W", "005D"]
        for age in ages  {
            if let astrWorks = AgeString.init(ageString: age) {
                XCTAssertTrue(astrWorks.validate(age: age))
            }
        }
    }
    
    func ageStringFormat() {
        let source  = ["334D", "034Y", "111W", "002D"]
        let dest    = ["10 months", "34 ans", "2 years", "2 days"]
        
        var index = 0
        
        for s in source {
            let agStr = AgeString.init(ageString: s)
            
            if let a = agStr  {
                XCTAssertEqual(a.format(), dest[index])
            }
            
            index += 1
        }
    }
    
    
    // UID
    public func validateUID() {
        let valUID = "1.102.99"
        XCTAssertTrue(UID.validate(uid: valUID))
        
        let invalUID1 = "1.012.5"
        let invalUID2 = "coucou"
        
        XCTAssertFalse(UID.validate(uid: invalUID1))
        XCTAssertFalse(UID.validate(uid: invalUID2))
    }
    
    public func generateUID() {
        let valUID = "1.102.99"
        XCTAssertNotNil(UID.generate(root: valUID))
    }
    
    
    // MARK: -
    public func readDicomDate() {
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
    
    
    public func writeDicomDate() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        
        let ds1 = "2012/01/24"
        let d1  = dateFormatter.date(from: ds1)
        let dd1 = d1!.dicomDateString()
        
        XCTAssert(dd1 == "20120124")
    }

    public func dicomDateWrongLength() {
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
    
    
    public func readDicomTime() {
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


    public func readDicomTimeMidnight() {
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

    public func dicomTimeWeirdTime() {
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
    
    public func writeDicomTime() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        
        let ds1 = "14:32:50"
        let d1  = dateFormatter.date(from: ds1)
        let dd1 = d1!.dicomTimeString()
                
        XCTAssert(dd1 == "143250.000000")
    }

    
    public func combineDateAndTime() {
        let df = DateFormatter()
        df.dateFormat = "yyyy/MM/dd HH:mm:ss"
        let expected_res = "2000/12/01 14:32:50"

        let ds1 = "20001201"
        let ts1 = "143250"
        
        let dateAndTime = Date(dicomDate: ds1, dicomTime: ts1)

        XCTAssert(expected_res == df.string(from: dateAndTime!))
    }
    
    
    
    
    public func readWriteDicomRange() {
        let ds1 = "20001201"
        let ds2 = "20021201"
        
        let dicomRange = "\(ds1)-\(ds2)"
        let dateRange = DateRange(dicomRange: dicomRange, type: VR.VR.DA)
        
        XCTAssert(dateRange!.range          == .between)
        XCTAssert(dateRange!.description    == "20001201-20021201")
    }
    
    

    public func readWriteTest() {
        XCTAssert(self.readWriteFile(withPath: self.filePath))
    }
    
    
    
    public func readTest() {
        XCTAssert(self.readFile(withPath: self.filePath))
    }
    
    
    public func readUpdateWriteTest() {
        XCTAssert(self.readUpdateWriteFile(withPath: self.filePath))
    }
    
    
    public func readImageTest() {
        XCTAssert(self.readImageFile(withPath: self.filePath))
    }
    
    
    
    
    private func readImageFile(withPath path:String, checksum:Bool = true) -> Bool {
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
    }
    
    
    
    /**
     This test reads a source DICOM file, updates its PatientName attribute, then writes a DICOM file copy.
     Then it re-reads the just updated DICOM file to set back its original PatientName and then checks data integrity against the source DICOM file using MD5
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
                    
                    let originalSum = shell(launchPath: "/sbin/md5", arguments: ["-q", path]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    let savedSum = shell(launchPath: "/sbin/md5", arguments: ["-q", writePath]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    
                    Logger.info("# Source file MD5 : \(originalSum)")
                    Logger.info("# Dest. file MD5  : \(savedSum)")
                    Logger.info("#")
                    
                    if originalSum == savedSum {
                        Logger.info("# Checksum succeeded: \(originalSum) == \(savedSum)")
                    }
                    else {
                        Logger.info("# Error: wrong checksum: \(originalSum) != \(savedSum)")
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
                
                let originalSum = shell(launchPath: "/sbin/md5", arguments: ["-q", path]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                let savedSum = shell(launchPath: "/sbin/md5", arguments: ["-q", writePath]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                
                Logger.info("# Source file MD5 : \(originalSum)")
                Logger.info("# Dest. file MD5  : \(savedSum)")
                Logger.info("#")
                
                if originalSum == savedSum {
                    Logger.info("# Checksum succeeded: \(originalSum) == \(savedSum)")
                }
                else {
                    Logger.info("# Error: wrong checksum: \(originalSum) != \(savedSum)")
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
            let dict = attr as NSDictionary
            
            return dict.fileSize()
        } catch {
            print("Error: \(error)")
            
            return 0
        }
    }
    
    
    
    private func shell(launchPath: String, arguments: [String]) -> String {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = arguments
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output: String = String(data: data, encoding: String.Encoding.utf8)!
        
        return output
    }
    
    
    // Poulpy
    
    // RTDose tests
    
    public func testIsValid() {

        // TODO get files under RT folder, doesn't work atm; workaround, use filter to get "rt_" files
        var paths = Bundle.module.paths(forResourcesOfType: "dcm", inDirectory: nil)
        paths = paths.filter { $0.contains("rt_") }
        
        paths.forEach { path in
            let rtDose = RTDose.init(forPath: path)
            _ = rtDose?.isValid()
        }
        
        let path = Bundle.module.path(forResource: "rt_dose_1.2.826.0.1.3680043.8.274.1.1.6549911257.77961.3133305374.424", ofType: "dcm")
        guard let p = path else {
            return
        }
        
        if let rtDose = RTDose.init(forPath: p) {
            XCTAssertTrue(rtDose.isValid())
        }
        
        
        
        let path2 = Bundle.module.path(forResource: "rt_RTXPLAN.20110509.1010_Irregular", ofType: "dcm")
        guard let p2 = path2 else {
            return
        }
        
        if let rtDose = RTDose.init(forPath: p2) {
            XCTAssertFalse(rtDose.isValid())
        }
    }
    
    public func testGetDoseImageWidth() {
        
        let path = Bundle.module.path(forResource: "rt_dose_1.2.826.0.1.3680043.8.274.1.1.6549911257.77961.3133305374.424", ofType: "dcm")
        guard let p = path else {
            return
        }
        
        if let rtDose = RTDose.init(forPath: p) {
            XCTAssertEqual((rtDose.getDoseImageWidth()), 10)
        }
    }
    
    public func testGetDoseImageHeight() {
        let path = Bundle.module.path(forResource: "rt_dose_1.2.826.0.1.3680043.8.274.1.1.6549911257.77961.3133305374.424", ofType: "dcm")
        guard let p = path else {
            return
        }
        
        if let rtDose = RTDose.init(forPath: p) {
            XCTAssertEqual((rtDose.getDoseImageHeight()), 10)
        }
    }
    
    public func testToPNG() {
        // finderTestDir
        
        var paths = Bundle.module.paths(forResourcesOfType: "dcm", inDirectory: nil)
        paths = paths.filter { $0.contains("rt_") }
        
        paths.forEach { path in
            if let dcmFile = DicomFile(forPath: path) {
                if let dcmImage = DicomImage(dcmFile.dataset) {
                    dcmImage.toPNG(path: finderTestDir, baseName: dcmFile.fileName())
                }
            }
            
        }
        
        /*
        let path = Bundle.module.path(forResource: "rt_dose_1.2.826.0.1.3680043.8.274.1.1.6549911257.77961.3133305374.424", ofType: "dcm")
        if let p = path {
            
            if let dcmFile = DicomFile(forPath: p) {
                if let dcmImage = DicomImage(dcmFile.dataset) {
                    dcmImage.toPNG(path: finderTestDir, baseName: dcmFile.fileName())
                }
            }
        }
         */
    }
    
    public func testGetUnscaledDose() {
        let path = Bundle.module.path(forResource: "rt_dose_1.2.826.0.1.3680043.8.274.1.1.6549911257.77961.3133305374.424", ofType: "dcm")
        guard let p = path else {
            return
        }
        
        if let rtDose = RTDose.init(forPath: p) {
            XCTAssertNotNil(rtDose.getUnscaledDose(column: 1, row: 1, frame: 1))
            if let unscaledDose = rtDose.getUnscaledDose(column: 1, row: 1, frame: 1) {
                XCTAssertTrue(unscaledDose is UInt32)
            }
        }
    }
}

