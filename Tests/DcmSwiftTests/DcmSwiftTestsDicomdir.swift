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
        
    }
    
    func testWriteDicomDir() {
        let _ = Bundle.module.paths(forResourcesOfType: "dicomdir", inDirectory: nil)
    }
    
}


