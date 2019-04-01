//
//  DcmSwiftTests.swift
//  DcmSwiftTests
//
//  Created by Rafael Warnault on 29/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import XCTest
import Cocoa
import DcmSwift


class DcmSwiftTests: XCTestCase {
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
    
    
    override class var defaultTestSuite: XCTestSuite {
        let suite = XCTestSuite(forTestCaseClass: DcmSwiftTests.self)
        
        let bundle = Bundle(for: DcmSwiftTests.self)
        let paths = bundle.paths(forResourcesOfType: "", inDirectory: nil)
        
        paths.forEach { path in
            print(path)
            // Generate a test for our specific selector
            let test = DcmSwiftTests(selector: #selector(readWriteTest))
            
            // Each test will take the size argument and use the instance variable in the test
            test.filePath = path
            
            // Add it to the suite, and the defaults handle the rest
            suite.addTest(test)
        }
        
        paths.forEach { path in
            print(path)
            // Generate a test for our specific selector
            let test = DcmSwiftTests(selector: #selector(readUpdateWriteTest))
            
            // Each test will take the size argument and use the instance variable in the test
            test.filePath = path
            
            // Add it to the suite, and the defaults handle the rest
            suite.addTest(test)
        }
        return suite
    }
    
    
    public func readWriteTest() {
        print(self.filePath)
        XCTAssert(self.readWriteFile(withPath: self.filePath))
    }
    
    
    public func readUpdateWriteTest() {
        print(self.filePath)
        XCTAssert(self.readUpdateWriteFile(withPath: self.filePath))
    }
    
    
    
    private func readUpdateWriteFile(withPath path:String, checksum:Bool = true) -> Bool {
        let fileName = path.components(separatedBy: "/").last!.replacingOccurrences(of: ".dcm", with: "")
        let writePath = "\(self.finderTestDir)/\(fileName)-rwu-test.dcm"
        
        Swift.print("#########################################################")
        Swift.print("# UPDATE INTEGRITY TEST")
        Swift.print("#")
        Swift.print("# Source file : \(path)")
        Swift.print("# Destination file : \(writePath)")
        Swift.print("#")
        
        if let dicomFile = DicomFile(forPath: path) {
            if printDatasets { Swift.print("\(dicomFile.dataset.description )") }
            
            Swift.print("# Read succeeded")
            
            if dicomFile.dataset.set(value: "Dicomix", forTagName: "PatientName") != nil {
                Swift.print("# Update succeeded")
            } else {
                Swift.print("# Update failed")
            }
            
            if (dicomFile.write(atPath: writePath)) {
                Swift.print("# Write succeeded")
                Swift.print("#")
                
                if DicomFile(forPath: writePath) != nil {
                    Swift.print("# Re-read updated file read succeeded !!!")
                    Swift.print("#")
                } else {
                    Swift.print("# Re-read updated file read failed…")
                    Swift.print("#")
                    Swift.print("#########################################################")
                    return false
                }
            }
            else {
                Swift.print("# Error: while writing file: \(writePath)")
                Swift.print("#")
                Swift.print("#########################################################")
                return false
            }
            
            Swift.print("#")
            Swift.print("#########################################################")
            
            return true
        }
        
        return true
    }
    

    
    
    private func readWriteFile(withPath path:String, checksum:Bool = true) -> Bool {
        let fileName = path.components(separatedBy: "/").last!.replacingOccurrences(of: ".dcm", with: "")
        let writePath = "\(self.finderTestDir)/\(fileName)-rw-test.dcm"
        
        Swift.print("#########################################################")
        Swift.print("# READ/WRITE INTEGRITY TEST")
        Swift.print("#")
        Swift.print("# Source file : \(path)")
        Swift.print("# Destination file : \(writePath)")
        Swift.print("#")
        
        if let dicomFile = DicomFile(forPath: path) {
            if printDatasets { Swift.print("\(dicomFile.dataset.description )") }
            
            Swift.print("# Read succeeded")
            
            if (dicomFile.write(atPath: writePath)) {
                Swift.print("# Write succeeded")
                Swift.print("#")
                
                Swift.print("# Source file size : \(self.fileSize(filePath: path))")
                Swift.print("# Dest. file size  : \(self.fileSize(filePath: writePath))")
                Swift.print("#")
                
                Swift.print("# Calculating checksum...")
                Swift.print("#")
                
                let originalSum = shell(launchPath: "/sbin/md5", arguments: ["-q", path]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                let savedSum = shell(launchPath: "/sbin/md5", arguments: ["-q", writePath]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                
                Swift.print("# Source file MD5 : \(originalSum)")
                Swift.print("# Dest. file MD5  : \(savedSum)")
                Swift.print("#")
                
                if originalSum == savedSum {
                    Swift.print("# Checksum succeeded: \(originalSum) == \(savedSum)")
                }
                else {
                    Swift.print("# Error: wrong checksum: \(originalSum) != \(savedSum)")
                    Swift.print("#")
                    Swift.print("#########################################################")
                    return false
                }
            }
            else {
                Swift.print("# Error: while writing file: \(writePath)")
                Swift.print("#")
                Swift.print("#########################################################")
                return false
            }
            
            Swift.print("#")
            Swift.print("#########################################################")
            
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
