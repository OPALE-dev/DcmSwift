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
    private static var testDicomFileIO          = false
    private static var testDicomDataSet         = false
    private static var testDicomImage           = true
    
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
            suite.addTest(DcmSwiftTests(selector: #selector(testReadWriteDicomDateRange)))
            suite.addTest(DcmSwiftTests(selector: #selector(testReadWriteDicomTimeRange)))
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
        let r1 = "Friday 1 December 2000 at 00:00:00 Central European Standard Time"
        
        assert(desc1 == r1)
        
        // ACR-NEMA date format
        let ds2 = "2000.12.02"
        let dd2 = Date(dicomDate: ds2)
        let desc2 = dd2!.description(with: .current)
        let r2 = "Saturday 2 December 2000 at 00:00:00 Central European Standard Time"
        
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
    
    
    public func testReadDicomTime() {
        let ds1 = "143250"
        let dd1 = Date(dicomTime: ds1)
        let desc1 = dd1!.description(with: .current)
        let r1 = "Saturday 1 January 2000 at 14:32:50 Central European Standard Time"
        
        assert(desc1 == r1)
        
        // ACR-NEMA time format
        let ds2 = "14:32:50"
        let dd2 = Date(dicomTime: ds2)
        let desc2 = dd2?.description(with: .current)
        let r2 = "Saturday 1 January 2000 at 14:32:50 Central European Standard Time"
        
        assert(desc2 == r2)
    }
    
    
    public func testWriteDicomTime() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        
        let ds1 = "14:32:50"
        let d1  = dateFormatter.date(from: ds1)
        let dd1 = d1!.dicomTimeString()
        
        assert(dd1 == "143250")
    }
    
    
    public func testCombineDateAndTime() {
        let ds1 = "20001201"
        let ts1 = "143250"
        
        let dateAndTime = Date(dicomDate: ds1, dicomTime: ts1)
        let dts = dateAndTime?.description(with: .current)
        
        assert(dts == "Friday 1 December 2000 at 14:32:50 Central European Standard Time")
    }
    
    
    
    
    public func testReadWriteDicomDateRange() {
        let ds1 = "20001201"
        let ds2 = "20021201"
        
        let dicomRange = "\(ds1)-\(ds2)"
        let dateRange = DateRange(dicomDateRange: dicomRange)
        
        assert(dateRange!.rangeType     == .betweenDate)
        assert(dateRange!.description   == "20001201-20021201")
    }
    
    
    
    public func testReadWriteDicomTimeRange() {
        let ts1 = "143250"
        let ts2 = "173250"
        
        let dicomRange = "\(ts1)-\(ts2)"
        let timeRange = DateRange(dicomTimeRange: dicomRange)
        
        assert(timeRange!.rangeType     == .betweenTime)
        assert(timeRange!.description   == "143250-173250")
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
