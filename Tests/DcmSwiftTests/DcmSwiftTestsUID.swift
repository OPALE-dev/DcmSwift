//
//  File.swift
//  
//
//  Created by Colombe on 09/07/2021.
//

import Foundation
import DcmSwift
import XCTest


class DcmSwiftTestsUID: XCTestCase {
    // UID
    public func testValidateUID() {
        let valUID = "1.102.99"
        XCTAssertTrue(UID.validate(uid: valUID))
        
        let invalUID1 = "1.012.5"
        let invalUID2 = "coucou"
        
        XCTAssertFalse(UID.validate(uid: invalUID1))
        XCTAssertFalse(UID.validate(uid: invalUID2))
    }
    
    public func testGenerateUID() {
        let valUID = "1.102.99"
        XCTAssertNotNil(UID.generate(root: valUID))
    }

}
