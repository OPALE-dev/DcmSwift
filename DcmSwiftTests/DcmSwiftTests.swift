//
//  DcmSwiftTests.swift
//  DcmSwiftTests
//
//  Created by Rafael Warnault on 29/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import XCTest
import Cocoa
import DcmSwift
import SwiftyBeaver


class DcmSwiftTests: XCTestCase {
    // Configure the test suite
    private static var testDicomDateAndTime     = false
    private static var testDicomFileIO          = true
    private static var testDicomDataSet         = true
    private static var testDicomImage           = false
    
    public var filePath:String!
    
    private var finderTestDir:String = ""
    private var printDatasets = false
    
    
    override func setUp() {
        super.setUp()
        
        // prepare a test folder for rewritten files
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
     */
    override class var defaultTestSuite: XCTestSuite {
        let suite = XCTestSuite(forTestCaseClass: DcmSwiftTests.self)
        
        let bundle = Bundle(for: DcmSwiftTests.self)
        let paths = bundle.paths(forResourcesOfType: "", inDirectory: nil)
        
        if testDicomDateAndTime {
            suite.addTest(DcmSwiftTests(selector: #selector(testReadDicomDate)))
            suite.addTest(DcmSwiftTests(selector: #selector(testWriteDicomDate)))
            suite.addTest(DcmSwiftTests(selector: #selector(testReadDicomTime)))
            suite.addTest(DcmSwiftTests(selector: #selector(testWriteDicomTime)))
            suite.addTest(DcmSwiftTests(selector: #selector(testCombineDateAndTime)))
            suite.addTest(DcmSwiftTests(selector: #selector(testReadWriteDicomRange)))

        }
        
        
        if testDicomFileIO {
            /**
             This test suite performs a read/write on a set of DICOM files without
             modifying them, them check the MD5 checksum to ensure the I/O features
             of DcmSwift work properly.
             */
            paths.forEach { path in
                print(path)
                // Generate a test for our specific selector
                let test = DcmSwiftTests(selector: #selector(readWriteTest))
                
                // Each test will take the size argument and use the instance variable in the test
                test.filePath = path
                
                // Add it to the suite, and the defaults handle the rest
                suite.addTest(test)
            }
        }
        
        if testDicomDataSet {
            paths.forEach { path in
                print(path)
                // Generate a test for our specific selector
                let test = DcmSwiftTests(selector: #selector(readUpdateWriteTest))
                
                // Each test will take the size argument and use the instance variable in the test
                test.filePath = path
                
                // Add it to the suite, and the defaults handle the rest
                suite.addTest(test)
            }
        }
        
        if testDicomImage {
            paths.forEach { path in
                print(path)
                // Generate a test for our specific selector
                let test = DcmSwiftTests(selector: #selector(readImageTest))
                
                // Each test will take the size argument and use the instance variable in the test
                test.filePath = path
                
                // Add it to the suite, and the defaults handle the rest
                suite.addTest(test)
            }
        }
        
        return suite
    }
    
    
    
    
    public func testReadDicomDate() {
        let ds1 = "20001201"
        let dd1 = Date(dicomDate: ds1)
        let desc1 = dd1!.description(with: .current)
        let r1 = "vendredi 1 décembre 2000 à 00:00:00 heure normale d’Europe centrale"
        
        assert(desc1 == r1)
        
        // ACR-NEMA date format
        let ds2 = "2000.12.01"
        let dd2 = Date(dicomDate: ds2)
        let desc2 = dd2!.description(with: .current)
        let r2 = "vendredi 1 décembre 2000 à 00:00:00 heure normale d’Europe centrale"
        
        assert(desc2 == r2)
    }
    
    
    public func testWriteDicomDate() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        
        let ds1 = "2012/01/24"
        let d1  = dateFormatter.date(from: ds1)
        let dd1 = d1!.dicomDateString()
        
        assert(dd1 == "20120124")
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
            assert(dd == nil)

            ds += "1"
        }
    }
    
    
    public func testReadDicomTime() {
        let ds1 = "143250"
        let dd1 = Date(dicomTime: ds1)
        let desc1 = dd1!.description(with: .current)
        let r1 = "samedi 1 janvier 2000 à 14:32:50 heure normale d’Europe centrale"
        
        assert(desc1 == r1)
        
        // ACR-NEMA time format
        let ds2 = "14:32:50"
        let dd2 = Date(dicomTime: ds2)
        let desc2 = dd2?.description(with: .current)
        let r2 = "samedi 1 janvier 2000 à 14:32:50 heure normale d’Europe centrale"
        
        assert(desc2 == r2)
    }


    public func testReadDicomTimeMidnight() {
        let ds1 = "240000"
        let dd1 = Date(dicomTime: ds1)

        assert(dd1 == nil)

        // ACR-NEMA time format
        let ds2 = "24:00:00"
        let dd2 = Date(dicomTime: ds2)

        assert(dd2 == nil)
    }


    public func testDicomTimeWrongLength() {
        var ds1 = "1"
        for _ in 0...3 {
            let dd1 = Date(dicomTime: ds1)
            assert(dd1 == nil)
            ds1 += "11"
        }
    }

    public func testDicomTimeWeirdTime() {
        let ds1 = "236000"
        let dd1 = Date(dicomTime: ds1)

        assert(dd1 == nil)

        let ds2 = "235099"
        let dd2 = Date(dicomTime: ds2)

        assert(dd2 == nil)



        let ds3 = "255009"
        let dd3 = Date(dicomTime: ds3)

        assert(dd3 == nil)
    }
    
    public func testWriteDicomTime() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        
        let ds1 = "14:32:50"
        let d1  = dateFormatter.date(from: ds1)
        let dd1 = d1!.dicomTimeString()
        
        assert(dd1 == "143250.00000")
    }

    
    public func testCombineDateAndTime() {
        let ds1 = "20001201"
        let ts1 = "143250"
        
        let dateAndTime = Date(dicomDate: ds1, dicomTime: ts1)
        let dts = dateAndTime?.description(with: .current)
        
        assert(dts == "vendredi 1 décembre 2000 à 14:32:50 heure normale d’Europe centrale")
    }
    
    
    
    
    public func testReadWriteDicomRange() {
        let ds1 = "20001201"
        let ds2 = "20021201"
        
        let dicomRange = "\(ds1)-\(ds2)"
        let dateRange = DateRange(dicomRange: dicomRange, type: DicomConstants.VR.DA)
        
        assert(dateRange!.range     == .between)
        assert(dateRange!.description   == "20001201-20021201")
    }
    
    


    
    
    
    public func readWriteTest() {
        //print(self.filePath)
        XCTAssert(self.readWriteFile(withPath: self.filePath))
    }
    
    
    public func readUpdateWriteTest() {
        //print(self.filePath)
        XCTAssert(self.readUpdateWriteFile(withPath: self.filePath))
    }
    
    
    public func readImageTest() {
        //print(self.filePath)
        XCTAssert(self.readImageFile(withPath: self.filePath))
    }
    
    
    
    
    private func readImageFile(withPath path:String, checksum:Bool = true) -> Bool {
        let fileName = path.components(separatedBy: "/").last!.replacingOccurrences(of: ".dcm", with: "")
        var writePath = "\(self.finderTestDir)/\(fileName)-rwi-test.png"
        
        SwiftyBeaver.info("#########################################################")
        SwiftyBeaver.info("# PIXEL DATA TEST")
        SwiftyBeaver.info("#")
        SwiftyBeaver.info("# Source file : \(path)")
        SwiftyBeaver.info("# Destination file : \(writePath)")
        SwiftyBeaver.info("#")
        
        if let dicomFile = DicomFile(forPath: path) {
            if printDatasets { SwiftyBeaver.info("\(dicomFile.dataset.description )") }
            
            SwiftyBeaver.info("# Read succeeded")
            
            if let dicomImage = dicomFile.dicomImage {
                for i in 0 ..< 1 {
                    writePath = "\(self.finderTestDir)/\(fileName)-rwi-test-\(i)"
                    
                    if let image = dicomImage.image(forFrame: i) {
                        if dicomFile.dataset.transferSyntax == DicomConstants.JPEG2000 ||
                           dicomFile.dataset.transferSyntax == DicomConstants.JPEG2000Part2 ||
                           dicomFile.dataset.transferSyntax == DicomConstants.JPEG2000LosslessOnly ||
                           dicomFile.dataset.transferSyntax == DicomConstants.JPEG2000Part2Lossless {
                            _ = image.writeToFile(file: writePath, atomically: true, usingType: NSBitmapImageRep.FileType.jpeg2000)
                        }
                        else if dicomFile.dataset.transferSyntax == DicomConstants.JPEGLossless ||
                                dicomFile.dataset.transferSyntax == DicomConstants.JPEGLosslessNonhierarchical {
                            _ = image.writeToFile(file: writePath, atomically: true, usingType: NSBitmapImageRep.FileType.jpeg)
                        }
                        else {
                            _ = image.writeToFile(file: writePath, atomically: true, usingType: NSBitmapImageRep.FileType.bmp)
                        }
                    } else {
                        SwiftyBeaver.info("# Error: while extracting Pixel Data")
                        SwiftyBeaver.info("#")
                        SwiftyBeaver.info("#########################################################")
                        return false
                    }
                }
            } else {
                SwiftyBeaver.info("# Error: while extracting Pixel Data")
                SwiftyBeaver.info("#")
                SwiftyBeaver.info("#########################################################")
                return false
                
            }
            
            SwiftyBeaver.info("#")
            SwiftyBeaver.info("#########################################################")
            
            return true
        }
        
        return true
    }
    
    
    
    
    private func readUpdateWriteFile(withPath path:String, checksum:Bool = true) -> Bool {
        let fileName = path.components(separatedBy: "/").last!.replacingOccurrences(of: ".dcm", with: "")
        let writePath = "\(self.finderTestDir)/\(fileName)-rwu-test.dcm"
        
        SwiftyBeaver.info("#########################################################")
        SwiftyBeaver.info("# UPDATE INTEGRITY TEST")
        SwiftyBeaver.info("#")
        SwiftyBeaver.info("# Source file : \(path)")
        SwiftyBeaver.info("# Destination file : \(writePath)")
        SwiftyBeaver.info("#")
        
        if let dicomFile = DicomFile(forPath: path) {
            if printDatasets { SwiftyBeaver.info("\(dicomFile.dataset.description )") }
            
            SwiftyBeaver.info("# Read succeeded")
            
            if dicomFile.dataset.set(value: "Dicomix", forTagName: "PatientName") != nil {
                SwiftyBeaver.info("# Update succeeded")
            } else {
                SwiftyBeaver.info("# Update failed")
            }
            
            if (dicomFile.write(atPath: writePath)) {
                SwiftyBeaver.info("# Write succeeded")
                SwiftyBeaver.info("#")
                
                if DicomFile(forPath: writePath) != nil {
                    SwiftyBeaver.info("# Re-read updated file read succeeded !!!")
                    SwiftyBeaver.info("#")
                } else {
                    SwiftyBeaver.info("# Re-read updated file read failed…")
                    SwiftyBeaver.info("#")
                    SwiftyBeaver.info("#########################################################")
                    return false
                }
            }
            else {
                SwiftyBeaver.info("# Error: while writing file: \(writePath)")
                SwiftyBeaver.info("#")
                SwiftyBeaver.info("#########################################################")
                return false
            }
            
            SwiftyBeaver.info("#")
            SwiftyBeaver.info("#########################################################")
            
            return true
        }
        
        return true
    }
    
    
    
    
    private func readWriteFile(withPath path:String, checksum:Bool = true) -> Bool {
        let fileName = path.components(separatedBy: "/").last!.replacingOccurrences(of: ".dcm", with: "")
        let writePath = "\(self.finderTestDir)/\(fileName)-rw-test.dcm"
        
        SwiftyBeaver.info("#########################################################")
        SwiftyBeaver.info("# READ/WRITE INTEGRITY TEST")
        SwiftyBeaver.info("#")
        SwiftyBeaver.info("# Source file : \(path)")
        SwiftyBeaver.info("# Destination file : \(writePath)")
        SwiftyBeaver.info("#")
        
        if let dicomFile = DicomFile(forPath: path) {
            if printDatasets { SwiftyBeaver.info("\(dicomFile.dataset.description )") }
            
            SwiftyBeaver.info("# Read succeeded")
            
            if (dicomFile.write(atPath: writePath)) {
                SwiftyBeaver.info("# Write succeeded")
                SwiftyBeaver.info("#")
                
                SwiftyBeaver.info("# Source file size : \(self.fileSize(filePath: path))")
                SwiftyBeaver.info("# Dest. file size  : \(self.fileSize(filePath: writePath))")
                SwiftyBeaver.info("#")
                
                SwiftyBeaver.info("# Calculating checksum...")
                SwiftyBeaver.info("#")
                
                let originalSum = shell(launchPath: "/sbin/md5", arguments: ["-q", path]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                let savedSum = shell(launchPath: "/sbin/md5", arguments: ["-q", writePath]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                
                SwiftyBeaver.info("# Source file MD5 : \(originalSum)")
                SwiftyBeaver.info("# Dest. file MD5  : \(savedSum)")
                SwiftyBeaver.info("#")
                
                if originalSum == savedSum {
                    SwiftyBeaver.info("# Checksum succeeded: \(originalSum) == \(savedSum)")
                }
                else {
                    SwiftyBeaver.info("# Error: wrong checksum: \(originalSum) != \(savedSum)")
                    SwiftyBeaver.info("#")
                    SwiftyBeaver.info("#########################################################")
                    return false
                }
            }
            else {
                SwiftyBeaver.info("# Error: while writing file: \(writePath)")
                SwiftyBeaver.info("#")
                SwiftyBeaver.info("#########################################################")
                return false
            }
            
            SwiftyBeaver.info("#")
            SwiftyBeaver.info("#########################################################")
            
            return true
        }
        
        return true
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
}
