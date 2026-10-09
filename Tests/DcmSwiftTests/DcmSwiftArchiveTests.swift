import XCTest
@testable import DcmSwift

/// Pluggable archive storage: the neutral query model, the archive index
/// implementations, and their conformance kit.
final class DcmSwiftArchiveTests: XCTestCase {
    typealias W = DcmSwiftWorkflowTests

    func testQueryConditionsFromAnIdentifier() throws {
        let identifier = try W.dataSet([
            "00080005": ("CS", ["ISO_IR 192"]),
            "00100010": ("PN", ["Müller*"]),
            "00100020": ("LO", []),
            "0020000D": ("UI", ["1.2.3", "1.2.4"]),
            "00400100": ("SQ", [[
                "00080060": ("CS", ["CT"]),
                "00400001": ("AE", ["CT?"]),
                "00400002": ("DA", ["20240705-20240707"]),
                "00400003": ("TM", ["1000-1800"]),
            ]]),
        ])
        let query = try DICOMQuery(identifier: identifier, matcher: .modalityWorklist)
        let byPath = Dictionary(uniqueKeysWithValues: query.conditions.map { ($0.path.joined(separator: "."), $0.constraint) })
        XCTAssertEqual(byPath.count, 5, "universal keys give no condition")
        XCTAssertEqual(byPath["00100010"], .personName("muller*"))
        XCTAssertEqual(byPath["0020000D"], .equals(["1.2.3", "1.2.4"]))
        XCTAssertEqual(byPath["00400100.00080060"], .equals(["CT"]))
        XCTAssertEqual(byPath["00400100.00400001"], .wildcard("CT?"))
        guard case .dateTime(let time, let range)? = byPath["00400100.00400002"] else {
            return XCTFail("the date and time ranges are combined")
        }
        XCTAssertEqual(time, "00400003")
        XCTAssertEqual(range, DICOMQuery.normalizedRange("202407051000", vr: "DT")!.lowerBound
                       ... DICOMQuery.normalizedRange("202407071800", vr: "DT")!.upperBound)
        // Without the worklist matcher, each range is its own condition.
        XCTAssertEqual(try DICOMQuery(identifier: identifier).conditions.count, 6)
    }
}
