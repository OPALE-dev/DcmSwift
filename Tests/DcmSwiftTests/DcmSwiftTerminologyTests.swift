import XCTest
@testable import DcmSwift

/// The PS3.16 2026d terminology: Coding Schemes, DICOM Controlled
/// Terminology, and Context Groups.
final class DcmSwiftTerminologyTests: XCTestCase {
    let terminology = DICOMTerminology.shared

    func testCodingSchemesAndDICOMCodes() {
        XCTAssertEqual(terminology.edition, "2026d")
        XCTAssertEqual(terminology.codingScheme("DCM")?.uid, "1.2.840.10008.2.16.4", "invisible spaces are removed")
        XCTAssertEqual(terminology.codingScheme(uid: "2.16.840.1.113883.6.1")?.designator, "LN")
        XCTAssertEqual(terminology.dicomCode("CT")?.meaning, "Computed Tomography")
        XCTAssertTrue(terminology.isRetiredDICOMCode("AS"))
        XCTAssertFalse(terminology.isRetiredDICOMCode("CT"))
        XCTAssertNil(terminology.dicomCode("NOT-A-CODE"))
    }

    func testContextGroupMetadataAndClosure() throws {
        let group = try XCTUnwrap(terminology.contextGroup(4031))
        XCTAssertEqual(group.keyword, "CommonAnatomicRegion")
        XCTAssertEqual(group.uid, "1.2.840.10008.6.1.308")
        XCTAssertEqual(group.isExtensible, true)
        XCTAssertEqual(group.version, "20250709")
        XCTAssertEqual(terminology.contextGroup(keyword: "CommonAnatomicRegion")?.cid, 4031)
        XCTAssertEqual(terminology.contextGroup(uid: "1.2.840.10008.6.1.308")?.cid, 4031)

        let abdomen = DICOMCode("818981001", scheme: "SCT", meaning: "Abdomen")
        XCTAssertTrue(group.codes.contains(abdomen))
        // CID 4 includes groups that include CID 4031.
        XCTAssertTrue(try XCTUnwrap(terminology.contextGroup(4)).includedGroups.contains(4030))
        XCTAssertEqual(terminology.membership(of: abdomen, in: 4), .member)
        let closure = terminology.codes(in: 4)
        XCTAssertEqual(closure.count, Set(closure.map { $0.scheme + "|" + $0.value }).count, "each concept once")
        // Meanings are not compared; other codes are allowed by extension.
        XCTAssertEqual(terminology.membership(of: DICOMCode("818981001", scheme: "SCT", meaning: "Belly"), in: 4031), .member)
        XCTAssertEqual(terminology.membership(of: DICOMCode("1", scheme: "99LOCAL", meaning: "Local"), in: 4031),
                       .allowedByExtension)
        XCTAssertEqual(terminology.meaning(of: DICOMCode("818981001", scheme: "SCT", meaning: "")), "Abdomen")
    }

    func testNonExtensibleRuleBasedAndVersionedGroups() throws {
        let nonExtensible = try XCTUnwrap(terminology.contextGroupIDs.lazy.compactMap { self.terminology.contextGroup($0) }
            .first { $0.isExtensible == false && !$0.codes.isEmpty })
        XCTAssertEqual(terminology.membership(of: DICOMCode("1", scheme: "99LOCAL", meaning: "x"), in: nonExtensible.cid),
                       .notAllowed)
        // All LOINC document names: defined by a rule.
        XCTAssertNotNil(terminology.contextGroup(7020)?.definition)
        XCTAssertEqual(terminology.membership(of: DICOMCode("18748-4", scheme: "LN", meaning: ""), in: 7020), .undetermined)
        // NCDR codes carry their Coding Scheme Version.
        let versioned = try XCTUnwrap(terminology.contextGroup(3747)?.codes.first { $0.value == "75-0" })
        XCTAssertEqual(versioned.scheme, "NCDR")
        XCTAssertEqual(versioned.schemeVersion, "2.0b")
        // Codes from tables with cells spanning rows: CID 3227 keeps both
        // rows PS3.16 gives for one code.
        let qtc = try XCTUnwrap(terminology.contextGroup(3227)).codes.filter { $0.value == "2:15880" }
        XCTAssertEqual(Set(qtc.map(\.meaning)), ["QTc global using Bazett formula", "QTc global using Framingham formula"])
        XCTAssertEqual(terminology.meaning(of: qtc[0], in: 3227), "QTc global using Bazett formula", "the first row")
    }

    func testCodeFromACodeSequenceItem() throws {
        let identifier = DataSet()
        _ = identifier.set(value: "STUDY", forTagName: "QueryRetrieveLevel")
        let json: [String: Any] = ["00081032": ["vr": "SQ", "Value": [[
            "00080100": ["vr": "SH", "Value": ["818981001"]],
            "00080102": ["vr": "SH", "Value": ["SCT"]],
            "00080104": ["vr": "LO", "Value": ["Abdomen"]],
        ]]]]
        let dataSet = try DICOMJSON.dataSet(json)
        let item = try XCTUnwrap(dataSet.sequence(forTagName: "ProcedureCodeSequence")?.items.first)
        let code = try XCTUnwrap(DICOMCode(item: item))
        XCTAssertEqual(code, DICOMCode("818981001", scheme: "SCT", meaning: "Abdomen"))
        XCTAssertEqual(terminology.membership(of: code, in: 4031), .member)
    }
}
