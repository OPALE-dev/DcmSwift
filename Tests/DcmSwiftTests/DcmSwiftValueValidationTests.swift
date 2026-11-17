import XCTest
@testable import DcmSwift

/// Lexical rules of PS3.5 Table 6.2-1.
final class DcmSwiftValueValidationTests: XCTestCase {
    func testValuesAreCheckedAgainstTheirVR() {
        let valid: [(VR.VR, String)] = [
            (.AE, " STORESCP "), (.AS, "018M"), (.CS, "ORIGINAL_1 A"), (.DA, "20240229"), (.DA, "20260101 "),
            (.DS, " -1.5e-3 "), (.DS, ".5"), (.DS, "+12"), (.DT, "2007-0500"), (.DT, "19530827111300.0"),
            (.DT, "20260101235960.123456+1400"), (.IS, " +2147483647"), (.IS, "-2147483648"), (.TM, "2359"),
            (.TM, "235960.5"), (.TM, "07 "), (.UI, "1.2.840.10008.1.2"), (.UI, "0.1"), (.UR, "http://x/y "),
            (.SH, "abc def"), (.LO, String(repeating: "é", count: 64)), (.PN, "Yamada^Tarou=山田^太郎=やまだ^たろう"),
            (.PN, "=山田"), (.ST, "line\r\nnext\tTAB"), (.UT, String(repeating: "x", count: 20_000)),
        ]
        for (vr, value) in valid {
            XCTAssertNil(DICOMValueValidation.problem(with: value, vr: vr), "\(vr) \(value)")
        }
        let invalid: [(VR.VR, String)] = [
            (.AE, "   "), (.AE, "SEVENTEEN_CHARS_X"), (.AE, "A\\B"), (.AS, "22Y"), (.AS, "022Q"), (.CS, "lower"),
            (.CS, "A-B"), (.DA, "20230229"), (.DA, "20241301"), (.DA, "2024010"), (.DS, "1.2.3"), (.DS, "1 2"),
            (.DS, "12345678901234567"), (.DS, "e5"), (.DT, "202601011"), (.DT, "20260101240000"), (.DT, "2026-0000"),
            (.DT, "2026+1500"), (.DT, "20260101.5"), (.IS, "2147483648"), (.IS, "1A"), (.IS, "1 2"),
            (.TM, "2400"), (.TM, "1260"), (.TM, "123"), (.TM, "1200.5"), (.TM, "120000.1234567"), (.UI, "1.02"),
            (.UI, "1..2"), (.UI, "abc"), (.UR, " http://x"), (.UR, "http://x y"), (.SH, String(repeating: "x", count: 17)),
            (.LO, "a\u{07}b"), (.PN, "A^B^C^D^E^F"), (.PN, "A=B=C=D"), (.ST, "bell\u{07}"),
        ]
        for (vr, value) in invalid {
            XCTAssertNotNil(DICOMValueValidation.problem(with: value, vr: vr), "\(vr) \(value)")
        }
    }

    func testValidationReportsLexicalProblems() {
        let dataSet = DataSet()
        _ = dataSet.set(value: "1997.04.24", forTagName: "StudyDate")
        _ = dataSet.set(value: "MR\\ct", forTagName: "ModalitiesInStudy")
        _ = dataSet.set(value: "20260101", forTagName: "SeriesDate")
        let results = DicomSpec.shared.validate(dataSet: dataSet).filter { $0.message.contains("is invalid for") }
        XCTAssertEqual(results.count, 2)
        // The ACR-NEMA date format stays readable: a warning only.
        XCTAssertEqual(results.first { $0.message.contains("StudyDate") }?.severity, .Warning)
        XCTAssertEqual(results.first { $0.message.contains("ModalitiesInStudy") }?.severity, .Error)
        XCTAssertTrue(results.contains { $0.message.contains("Value 2 of ModalitiesInStudy") })
    }
}
