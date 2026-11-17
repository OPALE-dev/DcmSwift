import XCTest
@testable import DcmSwift

/// The Native DICOM Model (PS3.19 A.1).
final class DcmSwiftXMLTests: XCTestCase {
    private func sample() -> DataSet {
        let dataSet = DataSet()
        _ = dataSet.set(value: "ISO_IR 192", forTagName: "SpecificCharacterSet")
        _ = dataSet.set(value: "ORIGINAL\\\\AXIAL", forTagName: "ImageType")
        _ = dataSet.set(value: "Yamada^Tarou=山田^太郎\\Doe^^^Dr", forTagName: "PatientName")
        _ = dataSet.set(value: "", forTagName: "PatientID")
        _ = dataSet.set(value: "A <b> & \"c\"", forTagName: "StudyDescription")
        _ = dataSet.set(value: "0.50\\1", forTagName: "PixelSpacing")
        _ = dataSet.set(value: [UInt16(512), 256], forTagName: "Rows")
        _ = dataSet.set(value: [DataTag(withGroup: "0010", element: "0010")], forTagName: "FrameIncrementPointer")
        dataSet.appendSequence("ReferencedSOPSequence", items: [[("ReferencedSOPInstanceUID", "1.2.3.4")], []])
        for (tag, vr, data) in [("00290010", VR.VR.LO, Data("ACME 1.0".utf8)), ("00291001", .OB, Data([1, 2])),
                                ("00290011", .LO, Data("OTHER ".utf8)), ("00291101", .LO, Data("x ".utf8))] {
            let element = DataElement(
                withTag: DataTag(withGroup: String(tag.prefix(4)), element: String(tag.suffix(4))), dataset: dataSet)
            element.vr = vr
            element.data = data
            element.length = data.count
            dataSet.add(element: element)
        }
        return dataSet
    }

    func testEncodingFollowsTheNativeDICOMModel() throws {
        let xml = String(decoding: try DICOMXML.encode(sample()), as: UTF8.self)
        XCTAssertTrue(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(xml.contains("<NativeDicomModel xmlns=\"http://dicom.nema.org/PS3.19/models/NativeDICOM\" xml:space=\"preserve\">"))
        // Values numbered, empty Values kept, empty attributes empty.
        XCTAssertTrue(xml.contains("<DicomAttribute tag=\"00080008\" vr=\"CS\" keyword=\"ImageType\"><Value number=\"1\">ORIGINAL</Value><Value number=\"2\"/><Value number=\"3\">AXIAL</Value></DicomAttribute>"))
        XCTAssertTrue(xml.contains("<DicomAttribute tag=\"00100020\" vr=\"LO\" keyword=\"PatientID\"/>"))
        // Person names by component.
        XCTAssertTrue(xml.contains("<PersonName number=\"1\"><Alphabetic><FamilyName>Yamada</FamilyName><GivenName>Tarou</GivenName></Alphabetic><Ideographic><FamilyName>山田</FamilyName><GivenName>太郎</GivenName></Ideographic></PersonName>"))
        XCTAssertTrue(xml.contains("<PersonName number=\"2\"><Alphabetic><FamilyName>Doe</FamilyName><NamePrefix>Dr</NamePrefix></Alphabetic></PersonName>"))
        // Escaping, DS text as written, AT, binary.
        XCTAssertTrue(xml.contains("<Value number=\"1\">A &lt;b&gt; &amp; &quot;c&quot;</Value>"))
        XCTAssertTrue(xml.contains("<Value number=\"1\">0.50</Value>"))
        XCTAssertTrue(xml.contains("<Value number=\"1\">00100010</Value>"))
        // Items, the empty one included.
        XCTAssertTrue(xml.contains("<Item number=\"2\"></Item>"))
        // Private elements: creator attribute, gggg00ee tags, no creator elements.
        XCTAssertTrue(xml.contains("<DicomAttribute tag=\"00290001\" vr=\"OB\" privateCreator=\"ACME 1.0\"><InlineBinary>AQI=</InlineBinary></DicomAttribute>"))
        XCTAssertTrue(xml.contains("tag=\"00290001\" vr=\"LO\" privateCreator=\"OTHER\""))
        XCTAssertFalse(xml.contains("tag=\"00290010\""))
    }

    func testDecodingRoundTrips() throws {
        let first = try DICOMXML.encode(sample())
        let decoded = try DICOMXML.decode(first)
        XCTAssertEqual(String(decoding: try DICOMXML.encode(decoded), as: UTF8.self), String(decoding: first, as: UTF8.self))
        // Private blocks are reassigned in order of appearance.
        XCTAssertEqual(decoded.allElements.first { $0.tagCode() == "00290010" }?.value as? String, "ACME 1.0")
        XCTAssertEqual(decoded.allElements.first { $0.tagCode() == "00291001" }?.data, Data([1, 2]))
        XCTAssertEqual(decoded.textValues(forTag: "PatientName"), ["Yamada^Tarou=山田^太郎", "Doe^^^Dr"])
        XCTAssertEqual(decoded.textValues(forTag: "PixelSpacing"), ["0.50", "1"])
    }

    func testDecodingAcceptsUnorderedNumbersAndCDATA() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <NativeDicomModel xmlns="http://dicom.nema.org/PS3.19/models/NativeDICOM">
          <DicomAttribute tag="00280010" vr="US"><Value number="1">64</Value></DicomAttribute>
          <DicomAttribute tag="00080008" vr="CS"><Value number="3">B</Value><Value number="1">A</Value></DicomAttribute>
          <DicomAttribute tag="00081030" vr="LO"><Value number="1"><![CDATA[a<b]]></Value></DicomAttribute>
          <DicomAttribute tag="00090001" vr="LO" privateCreator="X"><Value number="1">p</Value></DicomAttribute>
        </NativeDicomModel>
        """
        let dataSet = try DICOMXML.decode(Data(xml.utf8))
        XCTAssertEqual(dataSet.unsignedInteger16(forTag: "Rows"), 64)
        XCTAssertEqual(dataSet.textValues(forTag: "ImageType"), ["A", "", "B"])
        XCTAssertEqual(dataSet.string(forTag: "StudyDescription"), "a<b")
        XCTAssertEqual(dataSet.allElements.first { $0.tagCode() == "00090010" }?.textValues, ["X"])
    }

    func testInvalidDocumentsAreRejected() {
        let invalid = [
            "<NativeDicomModel", "<Other/>",
            "<NativeDicomModel><DicomAttribute vr=\"LO\"/></NativeDicomModel>",
            "<NativeDicomModel><DicomAttribute tag=\"00100010\"/></NativeDicomModel>",
            "<NativeDicomModel><DicomAttribute tag=\"00100020\" vr=\"LO\"><Value number=\"0\">A</Value></DicomAttribute></NativeDicomModel>",
            "<NativeDicomModel><DicomAttribute tag=\"00100020\" vr=\"LO\"><Value number=\"1\">A</Value><Value number=\"1\">B</Value></DicomAttribute></NativeDicomModel>",
            "<NativeDicomModel><DicomAttribute tag=\"00280010\" vr=\"US\"><Value number=\"1\">x</Value></DicomAttribute></NativeDicomModel>",
            "<NativeDicomModel><DicomAttribute tag=\"00100001\" vr=\"LO\" privateCreator=\"X\"/></NativeDicomModel>",
            "<NativeDicomModel xmlns=\"urn:other\"/>",
        ]
        for text in invalid {
            XCTAssertThrowsError(try DICOMXML.decode(Data(text.utf8)), text)
        }
    }
}
