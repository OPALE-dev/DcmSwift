import XCTest
@testable import DcmSwift

/// The messages of DcmSwift with their templates and arguments, for
/// translation: the English message is unchanged, a translation renders
/// with its own order of arguments.
final class DcmSwiftDiagnosticTests: XCTestCase {
    func testTemplatesNumberTheirArgumentsInOrder() {
        let specifier = try! NSRegularExpression(pattern: "%(\\d+)\\$@")
        for template in DICOMDiagnosticTemplate.allCases {
            let text = template.rawValue
            let numbers = specifier.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
                Int((text as NSString).substring(with: $0.range(at: 1)))!
            }
            XCTAssertEqual(Set(numbers), Set(numbers.isEmpty ? [] : Array(1...numbers.max()!)), template.rawValue)
            XCTAssertFalse(text.replacingOccurrences(of: "%\\d+\\$@", with: "", options: .regularExpression).contains("%"),
                           "only %n$@ specifiers: \(text)")
        }
        XCTAssertEqual(Set(DICOMDiagnosticTemplate.allCases.map(\.rawValue)).count, DICOMDiagnosticTemplate.allCases.count)
    }

    func testEnglishAndTranslatedRendering() {
        let value = DICOMDiagnostic(.invalidValue, [.text("2"), .text("StudyDate"), .text("DA"),
                                                    .diagnostic(DICOMDiagnostic(.notDate))])
        XCTAssertEqual(value.description, "Value 2 of StudyDate is invalid for DA: not a YYYYMMDD date")
        let french: [DICOMDiagnosticTemplate: String] = [
            .invalidValue: "%2$@ : la valeur %1$@ n’est pas valide pour %3$@ (%4$@)",
            .notDate: "pas une date AAAAMMJJ",
        ]
        XCTAssertEqual(value.formatted { french[$0] ?? $0.rawValue },
                       "StudyDate : la valeur 2 n’est pas valide pour DA (pas une date AAAAMMJJ)")
        XCTAssertEqual(DICOMDiagnostic.substitute("%@ et %@, 100 %%", ["a", "b"]), "a et b, 100 %")
        XCTAssertEqual(DICOMDiagnostic.parsing("Dataset is corrupted"), DICOMDiagnostic(.datasetCorrupted))
        XCTAssertEqual(DICOMDiagnostic.parsing("Something else").template, .verbatim)
        XCTAssertEqual(DICOMDiagnostic.parsing("Something else").description, "Something else")
    }

    func testReadingEncodingAndIODCarryTheirDiagnostic() throws {
        // A data set cut in a value: the reader says where, with the tag.
        let meta = DICOMPart10Header.encodeMetaInformation(sopClassUID: "1.2.840.10008.5.1.4.1.1.7", sopInstanceUID: "1.2.3",
                                                           transferSyntaxUID: TransferSyntax.explicitVRLittleEndian, sourceAETitle: nil)
        var file = meta
        file += Data([0x10, 0x00, 0x10, 0x00, 0x50, 0x4E, 0x40, 0x00]) + Data("DOE".utf8)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostic-\(UUID().uuidString).dcm")
        try file.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let read = try DicomFile(tolerantlyReadingPath: url.path)
        let failure = try XCTUnwrap(read.readFailure)
        XCTAssertEqual(failure.diagnostic.template, .lengthOverflows)
        XCTAssertEqual(failure.message, failure.diagnostic.description)
        XCTAssertTrue(failure.message.hasPrefix("Fatal, cannot read length properly, decoded (0010,0010) length"), failure.message)

        XCTAssertEqual(DICOMValueValidation.diagnostic(with: "2026.11.28", vr: .DA)?.template, .acrNemaDate)
        XCTAssertEqual(DICOMValueValidation.problem(with: "20261", vr: .DA), "not a YYYYMMDD date")
        XCTAssertEqual(DICOMValueValidation.diagnostic(with: String(repeating: "1", count: 20), vr: .DS),
                       DICOMDiagnostic(.longerThanBytes, "16"))

        // The VRs a tag permits, as an expert reads them.
        let name = try XCTUnwrap(DataElement(withTagName: "PatientName", dataset: DataSet()))
        name.vr = .US
        let mismatch = try XCTUnwrap(DicomSpec.shared.validate(dataElement: name).first { $0.diagnostic.template == .vrMismatch })
        XCTAssertEqual(mismatch.message, "Value Representation mismatch, (0010,0010) permits PN")

        let report = DICOMIODValidator().validate(DataSet())
        XCTAssertEqual(report.findings.first?.diagnostic, DICOMDiagnostic(.noSOPClass))
        XCTAssertEqual(report.findings.first?.message, "SOP Class UID is missing, so the IOD is unknown")
    }
}
