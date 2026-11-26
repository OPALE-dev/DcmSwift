import Foundation
import XCTest
@testable import DcmSwift

/// Typed DA, TM, DT and AS Values (PS3.5 6.2, Table 6.2-1).
final class DcmSwiftTemporalValueTests: XCTestCase {
    func testDatesKeepTheirComponentsAndRefuseImpossibleDays() {
        XCTAssertEqual(DICOMDateTime(date: "20240229"), DICOMDateTime(year: 2024, month: 2, day: 29))
        XCTAssertNil(DICOMDateTime(date: "20230229"))
        XCTAssertNil(DICOMDateTime(date: "20241301"))
        XCTAssertNil(DICOMDateTime(date: "2024011"))
        XCTAssertNil(DICOMDateTime(date: "2024-01-01"))
        let legacy = DICOMDateTime(date: "1990.01.31")
        XCTAssertEqual(legacy?.day, 31)
        XCTAssertEqual(legacy?.isACRNEMA, true)
        XCTAssertEqual(legacy?.rawValue(for: .DA), "19900131")
    }

    func testTimesArePartialAndKeepTheirFractionAsWritten() {
        let hour = DICOMDateTime(time: "07")
        XCTAssertEqual(hour?.hour, 7)
        XCTAssertNil(hour?.minute)
        let precise = DICOMDateTime(time: "235960.010")
        XCTAssertEqual(precise?.second, 60)
        XCTAssertEqual(precise?.fraction, "010")
        XCTAssertEqual(precise?.dateComponents.nanosecond, 10_000_000)
        XCTAssertEqual(precise?.rawValue(for: .TM), "235960.010")
        XCTAssertNil(DICOMDateTime(time: "2400"))
        XCTAssertNil(DICOMDateTime(time: "1230.5"))
        XCTAssertNil(DICOMDateTime(time: "123000.1234567"))
        let legacy = DICOMDateTime(time: "12:30:00")
        XCTAssertEqual(legacy?.minute, 30)
        XCTAssertEqual(legacy?.isACRNEMA, true)
    }

    func testDateTimesCarryTheirOffsetAndNoImplicitZone() throws {
        let value = try XCTUnwrap(DICOMDateTime(dateTime: "20240131123005.5-0130"))
        XCTAssertEqual(value.utcOffset, -90)
        XCTAssertEqual(value.fraction, "5")
        XCTAssertEqual(value.dateComponents.timeZone?.secondsFromGMT(), -5400)
        XCTAssertEqual(value.rawValue(for: .DT), "20240131123005.5-0130")
        let year = try XCTUnwrap(DICOMDateTime(dateTime: "2024"))
        XCTAssertNil(year.month)
        XCTAssertNil(year.dateComponents.timeZone)
        XCTAssertNil(DICOMDateTime(dateTime: "202401311230+2500"))
        XCTAssertNil(DICOMDateTime(dateTime: "20240131.5"))
        XCTAssertNil(DICOMDateTime(dateTime: "202"))
    }

    func testRangesAreOpenAtEitherEnd() {
        XCTAssertEqual(DICOMTemporalValue("20240101-20241231", vr: .DA),
                       .range(from: DICOMDateTime(year: 2024, month: 1, day: 1), to: DICOMDateTime(year: 2024, month: 12, day: 31)))
        XCTAssertEqual(DICOMTemporalValue("-1200", vr: .TM), .range(from: nil, to: DICOMDateTime(hour: 12, minute: 0)))
        XCTAssertEqual(DICOMTemporalValue("2024-", vr: .DT), .range(from: DICOMDateTime(year: 2024), to: nil))
        // A DT offset is not a range.
        guard case .single(let single)? = DICOMTemporalValue("202401311230-0500", vr: .DT) else { return XCTFail() }
        XCTAssertEqual(single.utcOffset, -300)
        XCTAssertEqual(DICOMTemporalValue("2024-2025", vr: .DT), .range(from: DICOMDateTime(year: 2024), to: DICOMDateTime(year: 2025)))
        XCTAssertNil(DICOMTemporalValue("-", vr: .DA))
        XCTAssertNil(DICOMTemporalValue("2024-13", vr: .DA))
    }

    func testAgesReadEveryUnitAndRefuseOtherForms() {
        XCTAssertEqual(DICOMAge(rawValue: "045Y")?.dateComponents, DateComponents(year: 45))
        XCTAssertEqual(DICOMAge(rawValue: "003W")?.unit, .weeks)
        XCTAssertEqual(DICOMAge(count: 7, unit: .days)?.rawValue, "007D")
        XCTAssertNil(DICOMAge(rawValue: "45Y"))
        XCTAssertNil(DICOMAge(rawValue: "045y"))
        XCTAssertNil(DICOMAge(count: 1000, unit: .years))
    }

    func testElementsGiveTypedValuesOnlyWhenEveryValueFollowsTheVR() throws {
        let dataset = DataSet()
        _ = dataset.set(value: "20240101\\19900131", forTagName: "CalibrationDate")
        let dates = try XCTUnwrap(dataset.element(forTagName: "CalibrationDate"))
        XCTAssertEqual(dates.temporalValues?.count, 2)
        _ = dataset.set(value: "045Y", forTagName: "PatientAge")
        XCTAssertEqual(dataset.element(forTagName: "PatientAge")?.ageValues, [DICOMAge(count: 45, unit: .years)!])
        _ = dataset.set(value: "2024013", forTagName: "StudyDate")
        XCTAssertNil(dataset.element(forTagName: "StudyDate")?.temporalValues)
        XCTAssertNil(dataset.element(forTagName: "PatientAge")?.temporalValues)
    }
}
