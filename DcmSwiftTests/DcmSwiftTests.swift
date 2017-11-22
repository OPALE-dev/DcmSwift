//
//  DcmSwiftTests.swift
//  DcmSwiftTests
//
//  Created by Rafael Warnault on 29/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import XCTest
import DcmSwift


class DcmSwiftTests: XCTestCase {
    private var finderTestDir:String!
    private var printDatasets = false
    
    override func setUp() {
        super.setUp()

        // prepare a test folder for rewritten files
        let currentDate     = Date()
        let dateFormatter   = DateFormatter()
        
        dateFormatter.dateFormat = "yyyyMMddhhmmss"
        
        let finderPath = String(NSString(string: "~/Desktop/DcmSwiftTests").expandingTildeInPath)
        self.finderTestDir = "\(finderPath)/\(dateFormatter.string(from: currentDate))"
        
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
        self.readWriteFile(withName: fileName)
    }
    
    
    func test_CT_MONO2_16_chest_JPEG_70() {
        let fileName = "CT-MONO2-16-chest (JPEG (70))"
        self.readWriteFile(withName: fileName)
    }
    
    
    func test_US_RGB_8_esopecho_Little_Endian_Explicit() {
        let fileName = "US-RGB-8-esopecho (Little Endian Explicit VR)"
        self.readWriteFile(withName: fileName)
    }
    
    
    func test_US_RGB_8_epicard_Big_Endian_Explicit() {
        let fileName = "US-RGB-8-epicard (Big Endian Explicit VR)"
        self.readWriteFile(withName: fileName)
    }
    
    
    
    func test_MR_MONO2_8_16x_heart_Multiframe_Explicit_Little() {
        let fileName = "MR-MONO2-8-16x-heart (Multiframe Explicit Little)"
        self.readWriteFile(withName: fileName)
    }
    
    
    
    func test_MR_MONO2_16_knee_Little_Endian_Implicit() {
        let fileName = "MR-MONO2-16-knee (Little Endian Implicit VR)"
        self.readWriteFile(withName: fileName)
    }
    
    
    
    
    /*
     This method meseaure the loading time of a large DICOM file,
     using a 50MB mammographic image encoded in Little Endian Explicit VR
     */
    func test_MG_MONO2_16_Little_Endian_Explicit_Performances() {
        self.measure {
            let fileName = "MG-MONO2-16 (Little Endian Explicit VR)"
            self.readWriteFile(withName: fileName)
        }
    }
    
    
    
    
    private func readWriteFile(withName fileName:String) {
        let path = self.filePath(forName: fileName)
        let dicomFile = DicomFile(forPath: path)
        
        if printDatasets { Swift.print("\(dicomFile?.dataset.description ?? "")") }
        
//        let writePath = "\(self.finderTestDir)/\(fileName)-test.dcm"
//        
//        if (dicomFile?.write(atPath: writePath))! {
//            Swift.print("Write successfuly")
//        }
    }
    
    
    private func filePath(forName name:String) -> String {
        let bundle = Bundle(for: type(of: self))
        let path = bundle.path(forResource: name, ofType: "dcm")!
        
        return path
    }
    
}
