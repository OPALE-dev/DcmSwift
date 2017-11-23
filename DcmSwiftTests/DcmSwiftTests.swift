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
import SwiftHash

class DcmSwiftTests: XCTestCase {
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
    
    
    
    
    
    
    func test_CT_MONO2_16_Little_Endian_Explicit() {
        let fileName = "CT-MONO2-16 (Little Endian Explicit VR)"
        XCTAssert(self.readWriteFile(withName: fileName))
    }
    
    
    func test_CT_MONO2_16_chest_JPEG_70() {
        let fileName = "CT-MONO2-16-chest (JPEG (70))"
        XCTAssert(self.readWriteFile(withName: fileName))
    }
    
    
    func test_US_RGB_8_esopecho_Little_Endian_Explicit() {
        let fileName = "US-RGB-8-esopecho (Little Endian Explicit VR)"
        XCTAssert(self.readWriteFile(withName: fileName))
    }
    
    
    func test_US_RGB_8_epicard_Big_Endian_Explicit() {
        let fileName = "US-RGB-8-epicard (Big Endian Explicit VR)"
        XCTAssert(self.readWriteFile(withName: fileName))
    }
    
    
    
    func test_MR_MONO2_8_16x_heart_Multiframe_Explicit_Little() {
        let fileName = "MR-MONO2-8-16x-heart (Multiframe Explicit Little)"
        XCTAssert(self.readWriteFile(withName: fileName))
    }
    
    
    
    func test_MR_MONO2_16_knee_Little_Endian_Implicit() {
        let fileName = "MR-MONO2-16-knee (Little Endian Implicit VR)"
        XCTAssert(self.readWriteFile(withName: fileName))
    }
    
    
    
    
    /*
     This method meseaure the loading time of a large DICOM file,
     using a 50MB mammographic image encoded in Little Endian Explicit VR
     */
    func test_MG_MONO2_16_Little_Endian_Explicit_Performances() {
        //self.measure {
            let fileName = "MG-MONO2-16 (Little Endian Explicit VR)"
            XCTAssert(self.readWriteFile(withName: fileName))
        //}
    }
    
    
    
    
    private func readWriteFile(withName fileName:String, checksum:Bool = true) -> Bool {
        let path = self.filePath(forName: fileName)
        let writePath = "\(self.finderTestDir)/\(fileName)-test.dcm"
        
        Swift.print("#########################################################")
        Swift.print("# READ/WRITE INTEGRITY TEST")
        Swift.print("#")
        Swift.print("# Source file : \(path)")
        Swift.print("# Destination file : \(writePath)")
        Swift.print("#")
        
        let dicomFile = DicomFile(forPath: path)
        
        if printDatasets { Swift.print("\(dicomFile?.dataset.description ?? "")") }
        
        Swift.print("# Read succeeded")
        
        

        if (dicomFile?.write(atPath: writePath))! {
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
    
    
    
    
    private func filePath(forName name:String) -> String {
        let bundle = Bundle(for: type(of: self))
        let path = bundle.path(forResource: name, ofType: "dcm")!

        return path
    }
    
    
    
    func fileSize(filePath:String) -> UInt64 {
        var fileSize : UInt64
        
        do {
            //return [FileAttributeKey : Any]
            let attr = try FileManager.default.attributesOfItem(atPath: filePath)
            fileSize = attr[FileAttributeKey.size] as! UInt64
            
            //if you convert to NSDictionary, you can get file size old way as well.
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
