import XCTest
@testable import DcmSwift

/// Names of DIMSE statuses, by service (PS3.7 C, PS3.4 B.2.3, C.4).
final class DcmSwiftStatusNameTests: XCTestCase {
    func testGeneralNames() {
        XCTAssertEqual(DICOMStatus.success.name(), "Success")
        XCTAssertEqual(DICOMStatus.cancel.name(for: .cFindResponse), "Cancel")
        XCTAssertEqual(DICOMStatus.sopClassNotSupported.name(for: .cEchoResponse), "Failure: Refused: SOP Class Not Supported")
        XCTAssertNil(DICOMStatus(code: 0xA700).name(), "service-specific")
    }

    func testTheSameCodeByService() {
        XCTAssertEqual(DICOMStatus(code: 0xB000).name(for: .cStoreResponse), "Warning: Coercion of Data Elements")
        XCTAssertEqual(DICOMStatus(code: 0xB000).name(for: .cMoveResponse),
                       "Warning: Sub-operations Complete – One or More Failures or Warnings")
        XCTAssertEqual(DICOMStatus(code: 0xA7F3).name(for: .cStoreResponse), "Refused: Out of Resources")
        XCTAssertNil(DICOMStatus(code: 0xA7F3).name(for: .cFindResponse))
        XCTAssertEqual(DICOMStatus(code: 0xC123).name(for: .cFindRequest), "Failed: Unable to Process")
        XCTAssertEqual(DICOMStatus(code: 0xFF01).name(for: .cFindResponse), "Pending: Optional Keys Not Supported")
        XCTAssertEqual(DICOMStatus(code: 0xA801).name(for: .cMoveResponse), "Refused: Move Destination Unknown")
        XCTAssertNil(DICOMStatus(code: 0xA801).name(for: .cGetResponse))
        XCTAssertEqual(DICOMStatus(code: 0xAA02).name(for: .cMoveResponse), "Failed: Unable to Extract Frames")
        XCTAssertEqual(DICOMStatus(code: 0xAA02).name(for: .cGetResponse), "Failed: Unable to Extract Frames")
        XCTAssertEqual(DICOMStatus(code: 0xB001).name(for: .cFindResponse), "Warning: Matching Reached Response Limit")
    }
}
