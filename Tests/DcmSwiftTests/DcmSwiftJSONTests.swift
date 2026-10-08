import XCTest
@testable import DcmSwift

/// The DICOM JSON Model (PS3.18 Annex F).
final class DcmSwiftJSONTests: XCTestCase {
    private func object(_ dataSet: DataSet, _ options: DICOMJSON.EncodingOptions = .init()) throws -> [String: Any] {
        let data = try DICOMJSON.encode(dataSet, options: options)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func attribute(_ object: [String: Any], _ key: String) throws -> [String: Any] {
        try XCTUnwrap(object[key] as? [String: Any], key)
    }

    private func element(_ dataSet: DataSet, tag: String, vr: VR.VR, data: Data) -> DataElement {
        let element = DataElement(
            withTag: DataTag(withGroup: String(tag.prefix(4)), element: String(tag.suffix(4))), dataset: dataSet)
        element.vr = vr
        element.data = data
        element.length = data.count
        dataSet.add(element: element)
        return element
    }

    private func sample() -> DataSet {
        let dataSet = DataSet()
        _ = dataSet.set(value: "ISO_IR 192", forTagName: "SpecificCharacterSet")
        _ = dataSet.set(value: "ORIGINAL\\\\AXIAL", forTagName: "ImageType")
        _ = dataSet.set(value: "Yamada^Tarou=山田^太郎=やまだ^たろう\\Doe^Jane", forTagName: "PatientName")
        _ = dataSet.set(value: "", forTagName: "PatientID")
        _ = dataSet.set(value: "1.5\\-2e3\\ 7 ", forTagName: "PixelSpacing")
        _ = dataSet.set(value: " 42", forTagName: "InstanceNumber")
        _ = dataSet.set(value: [UInt16(512), 256], forTagName: "Rows")
        _ = dataSet.set(value: [Float64(0.25), -1], forTagName: "RealWorldValueSlope")
        _ = dataSet.set(value: [DataTag(withGroup: "0010", element: "0010")], forTagName: "FrameIncrementPointer")
        dataSet.appendSequence("ReferencedSOPSequence", items: [
            [("ReferencedSOPClassUID", "1.2.840.10008.5.1.4.1.1.7"), ("ReferencedSOPInstanceUID", "1.2.3.4")], [],
        ])
        _ = element(dataSet, tag: "00090010", vr: .LO, data: Data("ACME 1.0".utf8))
        _ = element(dataSet, tag: "00091001", vr: .OB, data: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        _ = element(dataSet, tag: "00100000", vr: .UL, data: Data([4, 0, 0, 0]))
        return dataSet
    }

    // MARK: Encoding

    func testEncodingFollowsAnnexF() throws {
        let json = try object(sample())
        // Group Length left out (F.2.1).
        XCTAssertNil(json["00100000"])
        XCTAssertEqual(try attribute(json, "00080005")["Value"] as? [String], ["ISO_IR 192"])
        // Empty Values are null (F.2.5).
        XCTAssertEqual((try attribute(json, "00080008")["Value"] as? [Any])?.count, 3)
        XCTAssertTrue((try attribute(json, "00080008")["Value"] as? [Any])?[1] is NSNull)
        // An empty attribute has no Value.
        let id = try attribute(json, "00100020")
        XCTAssertEqual(id["vr"] as? String, "LO")
        XCTAssertNil(id["Value"])
        // Person names by component group (F.2.2).
        let names = try XCTUnwrap(try attribute(json, "00100010")["Value"] as? [[String: String]])
        XCTAssertEqual(names[0], ["Alphabetic": "Yamada^Tarou", "Ideographic": "山田^太郎", "Phonetic": "やまだ^たろう"])
        XCTAssertEqual(names[1], ["Alphabetic": "Doe^Jane"])
        // IS and DS as numbers, other numeric VRs as numbers.
        XCTAssertEqual(try attribute(json, "00280030")["Value"] as? [Double], [1.5, -2000, 7])
        XCTAssertEqual(try attribute(json, "00200013")["Value"] as? [Int], [42])
        XCTAssertEqual(try attribute(json, "00280010")["Value"] as? [Int], [512, 256])
        XCTAssertEqual(try attribute(json, "00409225")["Value"] as? [Double], [0.25, -1])
        // AT as uppercase hexadecimal.
        XCTAssertEqual(try attribute(json, "00280009")["Value"] as? [String], ["00100010"])
        // Sequences, with an empty item as an empty object.
        let items = try XCTUnwrap(try attribute(json, "00081199")["Value"] as? [[String: Any]])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual((items[0]["00081155"] as? [String: Any])?["Value"] as? [String], ["1.2.3.4"])
        XCTAssertTrue(items[1].isEmpty)
        // Private blocks keep their tags; binary data is InlineBinary.
        XCTAssertEqual(try attribute(json, "00090010")["Value"] as? [String], ["ACME 1.0"])
        XCTAssertEqual(try attribute(json, "00091001")["InlineBinary"] as? String, "3q2+7w==")
    }

    func testAttributesAreInLexicographicOrder() throws {
        // Plain byte order, which JSONSerialization.sortedKeys does not give
        // ("300A" would come before "0008").
        let dataSet = sample()
        _ = dataSet.set(value: "PLAN", forTagName: "RTPlanLabel")
        let text = String(decoding: try DICOMJSON.encode(dataSet), as: UTF8.self)
        let top = try object(dataSet).keys.sorted()
        XCTAssertEqual(top.last, "300A0002")
        let positions = top.compactMap { key in text.range(of: "\"\(key)\":")?.lowerBound }
        XCTAssertEqual(positions.count, top.count)
        XCTAssertEqual(positions, positions.sorted())
    }

    func testOptionsForNumbersBulkDataAndFileMeta() throws {
        let dataSet = sample()
        _ = dataSet.set(value: "1.2.840.10008.1.2.1", forTagName: "TransferSyntaxUID")
        let strings = try object(dataSet, .init(numbersAsStrings: true))
        XCTAssertEqual(try attribute(strings, "00280030")["Value"] as? [String], ["1.5", "-2e3", "7"])
        XCTAssertNil(strings["00020010"])
        let meta = try object(dataSet, .init(includesFileMetaInformation: true))
        XCTAssertEqual(try attribute(meta, "00020010")["Value"] as? [String], ["1.2.840.10008.1.2.1"])
        let bulk = try object(dataSet, .init(bulkDataURI: { $0.vr == .OB ? "https://example.org/bulk/\($0.tag.code)" : nil }))
        XCTAssertEqual(try attribute(bulk, "00091001")["BulkDataURI"] as? String, "https://example.org/bulk/00091001")
        XCTAssertNil(try attribute(bulk, "00091001")["InlineBinary"])
    }

    func testUnknownVRsAreResolvedFromTheDictionary() throws {
        let dataSet = DataSet()
        _ = element(dataSet, tag: "00100020", vr: .UN, data: Data("ID42".utf8))
        _ = element(dataSet, tag: "00190010", vr: .UN, data: Data("ACME ".utf8))
        _ = element(dataSet, tag: "00191001", vr: .UN, data: Data([1, 2]))
        // A sequence sent as UN, in Implicit VR Little Endian.
        var items = DcmSwiftFuzzTests.Writer(explicit: false)
        items.header(0xFFFE, 0xE000, "", 0xFFFF_FFFF)
        items.text(0x0008, 0x1150, "UI", "1.2.3")
        items.header(0xFFFE, 0xE00D, "", 0)
        _ = element(dataSet, tag: "00081199", vr: .UN, data: Data(items.bytes))
        let json = try object(dataSet)
        XCTAssertEqual(try attribute(json, "00100020")["vr"] as? String, "LO")
        XCTAssertEqual(try attribute(json, "00100020")["Value"] as? [String], ["ID42"])
        XCTAssertEqual(try attribute(json, "00190010")["vr"] as? String, "LO", "Private Creator")
        XCTAssertEqual(try attribute(json, "00191001")["vr"] as? String, "UN", "unknown private element")
        let sequence = try attribute(json, "00081199")
        XCTAssertEqual(sequence["vr"] as? String, "SQ")
        let item = try XCTUnwrap((sequence["Value"] as? [[String: Any]])?.first)
        XCTAssertEqual((item["00081150"] as? [String: Any])?["Value"] as? [String], ["1.2.3"])
        // Kept as received on request.
        let raw = try object(dataSet, .init(resolvesUnknownVRs: false))
        XCTAssertEqual(try attribute(raw, "00100020")["vr"] as? String, "UN")
    }

    // MARK: Decoding

    func testDecodingRoundTripsThroughBinary() throws {
        let source = sample()
        let first = try DICOMJSON.encode(source)
        let decoded = try XCTUnwrap(try DICOMJSON.decode(first).first)
        XCTAssertEqual(String(decoding: try DICOMJSON.encode(decoded), as: UTF8.self),
                       String(decoding: first, as: UTF8.self))
        // And through every network transfer syntax.
        for syntax in [TransferSyntax.explicitVRLittleEndian, TransferSyntax.implicitVRLittleEndian,
                       TransferSyntax.explicitVRBigEndian] {
            let binary = try DICOMDataSetCoding.encode(decoded, transferSyntax: syntax)
            let reread = try DICOMDataSetCoding.decode(binary, transferSyntax: syntax)
            var options = DICOMJSON.EncodingOptions()
            // Implicit VR loses the VR of private elements.
            options.resolvesUnknownVRs = true
            let again = try object(reread, options)
            let expected = try object(decoded)
            for key in expected.keys where !key.hasPrefix("0009") {
                XCTAssertEqual(NSDictionary(dictionary: try attribute(again, key)),
                               NSDictionary(dictionary: try attribute(expected, key)), "\(key) in \(syntax)")
            }
        }
    }

    func testDecodingArraysNumbersAndCharacterSets() throws {
        let json = """
        [{"00080005": {"vr": "CS", "Value": ["ISO_IR 100"]},
          "00100010": {"vr": "PN", "Value": [{"Alphabetic": "Müller^Jérôme"}, null]},
          "00200013": {"vr": "IS", "Value": [7]},
          "00280030": {"vr": "DS", "Value": [0.5, "1.25"]},
          "00280010": {"vr": "US", "Value": [64]},
          "00186011": {"vr": "SQ", "Value": [{}, {"00186012": {"vr": "US", "Value": [1]}}]},
          "7FE00010": {"vr": "OW", "InlineBinary": "AAEAAQ=="}},
         {"00100020": {"vr": "LO"}}]
        """
        let dataSets = try DICOMJSON.decode(Data(json.utf8))
        XCTAssertEqual(dataSets.count, 2)
        let first = dataSets[0]
        // Latin-1 bytes in the binary encoding.
        let name = try XCTUnwrap(first.element(forTagName: "PatientName"))
        XCTAssertTrue(name.data.contains(0xFC))
        XCTAssertEqual(first.textValues(forTag: "PatientName"), ["Müller^Jérôme", ""])
        XCTAssertEqual(first.string(forTag: "InstanceNumber"), "7")
        XCTAssertEqual(first.textValues(forTag: "PixelSpacing"), ["0.5", "1.25"])
        XCTAssertEqual(first.unsignedInteger16(forTag: "Rows"), 64)
        XCTAssertEqual(first.sequence(forTagName: "SequenceOfUltrasoundRegions")?.items.count, 2)
        XCTAssertEqual(first.element(forTagName: "PixelData")?.data, Data([0, 1, 0, 1]))
        XCTAssertEqual(dataSets[1].element(forTagName: "PatientID")?.length, 0)
        // Even lengths in the binary encoding.
        XCTAssertTrue(try DICOMDataSetCoding.encode(first, transferSyntax: TransferSyntax.explicitVRLittleEndian)
            .count.isMultiple(of: 2))
    }

    func testDecodingBulkDataAndEncapsulatedPixelData() throws {
        let fragments = Data([0xFE, 0xFF, 0x00, 0xE0, 0, 0, 0, 0, 0xFE, 0xFF, 0x00, 0xE0, 4, 0, 0, 0, 1, 2, 3, 4])
        let json = """
        {"7FE00010": {"vr": "OB", "InlineBinary": "\(fragments.base64EncodedString())"},
         "00420011": {"vr": "OB", "BulkDataURI": "https://example.org/pdf"}}
        """
        XCTAssertThrowsError(try DICOMJSON.decode(Data(json.utf8)))
        let decoded = try XCTUnwrap(try DICOMJSON.decode(Data(json.utf8), options: .init(loadBulkData: { uri in
            XCTAssertEqual(uri, "https://example.org/pdf")
            return Data("%PDF".utf8)
        })).first)
        XCTAssertEqual(decoded.element(forTagName: "EncapsulatedDocument")?.data, Data("%PDF".utf8))
        let pixels = try XCTUnwrap(decoded.element(forTagName: "PixelData") as? PixelSequence)
        XCTAssertEqual(pixels.items.map { $0.data ?? Data() }, [Data(), Data([1, 2, 3, 4])])
        // Written back as the same Items.
        let again = try object(decoded)
        XCTAssertEqual(try attribute(again, "7FE00010")["InlineBinary"] as? String, fragments.base64EncodedString())
    }

    func testInvalidInputIsRejected() {
        let invalid = [
            "not json", "42", "{\"0010001\": {\"vr\": \"LO\"}}", "{\"00100010\": {\"Value\": [\"A\"]}}",
            "{\"00100010\": {\"vr\": \"XX\"}}", "{\"00100010\": {\"vr\": \"LO\", \"Value\": \"A\"}}",
            "{\"00280010\": {\"vr\": \"US\", \"Value\": [\"A\"]}}",
            "{\"00091001\": {\"vr\": \"OB\", \"InlineBinary\": \"***\"}}",
            "{\"00100010\": {\"vr\": \"PN\", \"Value\": [\"A\"], \"InlineBinary\": \"AA==\"}}",
            "{\"00280009\": {\"vr\": \"AT\", \"Value\": [\"0010\"]}}",
            "{\"00100020\": {\"vr\": \"LO\", \"Value\": [\"A\\\\B\", \"C\"]}}",
        ]
        for text in invalid {
            XCTAssertThrowsError(try DICOMJSON.decode(Data(text.utf8)), text)
        }
    }
}
