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
        XCTAssertTrue(UID.validate(uid: "1.0.840.10008"))
        
        let invalUID1 = "1.012.5"
        let invalUID2 = "coucou"
        
        XCTAssertFalse(UID.validate(uid: invalUID1))
        XCTAssertFalse(UID.validate(uid: invalUID2))
        XCTAssertFalse(UID.validate(uid: "1..2"))
        XCTAssertFalse(UID.validate(uid: "1.2 "))
    }
    
    public func testGenerateUID() {
        let valUID = "1.102.99"
        let generated = (0..<100).map { _ in UID.generate(root: valUID) }
        XCTAssertEqual(Set(generated).count, generated.count)
        XCTAssertTrue(generated.allSatisfy { UID.validate(uid: $0) && $0.utf8.count <= 64 })
    }

    /// PS3.5 B.2: the example of the standard, and random UUIDs.
    public func testUUIDDerivedUID() throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "f81d4fae-7dec-11d0-a765-00a0c91e6bf6"))
        XCTAssertEqual(UID.derived(from: uuid), "2.25.329800735698586629295641978511506172918")
        XCTAssertEqual(UID.derived(from: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))), "2.25.0")
        let generated = (0..<200).map { _ in UID.derived() }
        XCTAssertEqual(Set(generated).count, generated.count)
        XCTAssertTrue(generated.allSatisfy { $0.hasPrefix("2.25.") && UID.validate(uid: $0) && $0.utf8.count <= 44 })
    }

}
