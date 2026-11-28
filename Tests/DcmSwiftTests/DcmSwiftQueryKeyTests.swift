import XCTest
@testable import DcmSwift

/// Query keys written as an expert types them (PS3.4 C.2.2.1).
final class DcmSwiftQueryKeyTests: XCTestCase {
    private func json(_ dataSet: DataSet) throws -> [String: Any] {
        let data = try DICOMJSON.encode(dataSet, options: .init(includesFileMetaInformation: false, prettyPrinted: false))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testKeywordsTagsAndValues() throws {
        let name = try DICOMQueryKey("PatientName=DOE*")
        XCTAssertEqual(name.path.map(\.tag), ["00100010"])
        XCTAssertEqual(name.value, "DOE*")
        XCTAssertEqual(name.vr, "PN")
        let id = try DICOMQueryKey("(0010,0020)")
        XCTAssertEqual(id.path.first?.keyword, "PatientID")
        XCTAssertEqual(id.value, "")
        XCTAssertEqual(try DICOMQueryKey("0008,0020=20240101-20241231").pathDescription, "StudyDate")
        // A value may hold an equals sign.
        XCTAssertEqual(try DICOMQueryKey("StudyDescription=A=B").value, "A=B")
    }

    func testSequencePaths() throws {
        let key = try DICOMQueryKey("ScheduledProcedureStepSequence[0].Modality=CT")
        XCTAssertEqual(key.pathDescription, "ScheduledProcedureStepSequence[0].Modality")
        XCTAssertEqual(key.path.map(\.item), [0, nil])
        XCTAssertEqual(try DICOMQueryKey("ReferencedStudySequence").vr, "SQ")
    }

    func testInvalidKeys() {
        XCTAssertThrowsError(try DICOMQueryKey("NotAKeyword"))
        XCTAssertThrowsError(try DICOMQueryKey("FFFF,FFFF"))
        XCTAssertThrowsError(try DICOMQueryKey(""))
        XCTAssertThrowsError(try DICOMQueryKey("PatientName[0].PatientID"), "not a sequence")
        XCTAssertThrowsError(try DICOMQueryKey("ScheduledProcedureStepSequence.Modality"), "needs an Item index")
        XCTAssertThrowsError(try DICOMQueryKey("ScheduledProcedureStepSequence[-1].Modality"))
    }

    func testIdentifier() throws {
        let keys = try ["PatientName=DOE^J*", "StudyDate", "SeriesNumber=3", "ModalitiesInStudy=CT\\MR",
                        "ScheduledProcedureStepSequence[0].Modality=CT",
                        "ScheduledProcedureStepSequence[0].ScheduledStationAETitle",
                        "ReferencedStudySequence"].map { try DICOMQueryKey($0) }
        let object = try json(DICOMQueryKey.identifier(keys, level: "STUDY"))
        XCTAssertEqual((object["00080052"] as? [String: Any])?["Value"] as? [String], ["STUDY"])
        XCTAssertEqual(((object["00100010"] as? [String: Any])?["Value"] as? [[String: Any]])?.first?["Alphabetic"] as? String, "DOE^J*")
        XCTAssertNil((object["00080020"] as? [String: Any])?["Value"], "a return key is empty")
        XCTAssertEqual((object["00200011"] as? [String: Any])?["Value"] as? [Int], [3])
        XCTAssertEqual((object["00080061"] as? [String: Any])?["Value"] as? [String], ["CT", "MR"])
        let items = try XCTUnwrap((object["00400100"] as? [String: Any])?["Value"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual((items[0]["00080060"] as? [String: Any])?["Value"] as? [String], ["CT"])
        XCTAssertNotNil(items[0]["00400001"])
        XCTAssertEqual((object["00081110"] as? [String: Any])?["vr"] as? String, "SQ")
        // Without level, as a worklist query.
        XCTAssertNil(try json(DICOMQueryKey.identifier(keys, level: nil))["00080052"])
        XCTAssertThrowsError(try DICOMQueryKey.identifier([DICOMQueryKey("Rows=three")], level: "IMAGE"))
    }
}
