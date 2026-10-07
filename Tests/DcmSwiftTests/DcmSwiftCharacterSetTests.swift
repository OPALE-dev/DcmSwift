import XCTest
@testable import DcmSwift

/// Specific Character Set qualification against normative and independent
/// vectors:
/// - PS3.5 2026d Annexes H, I, J, and K and Section 6.1.2.3 examples, copied
///   in the standard's column/row or hexadecimal notation;
/// - Patient's Name values of the DCMTK character-set test files distributed
///   with pydicom 3.0.2, with pydicom's decoding as the expected text;
/// - CPython codec encodings for single-byte repertoires without a DICOM
///   example.
final class DcmSwiftCharacterSetTests: XCTestCase {

    // MARK: PS3.5 Annex H (Japanese)

    func testAnnexH3JapanesePersonNameWithDefaultValue1() throws {
        let set = DICOMCharacterSet(specificCharacterSet: "\\ISO 2022 IR 87")
        let text = "Yamada^Tarou=山田^太郎=やまだ^たろう"
        let bytes = columnRow("""
            05/09 06/01 06/13 06/01 06/04 06/01 5/14 05/04 06/01 07/02 06/15 07/05 03/13 01/11 02/04 04/02 \
            03/11 03/03 04/05 04/04 01/11 02/08 04/02 05/14 01/11 02/04 04/02 04/02 04/00 04/15 03/10 01/11 \
            02/08 04/02 03/13 01/11 02/04 04/02 02/04 06/04 02/04 05/14 02/04 04/00 01/11 02/08 04/02 05/14 \
            01/11 02/04 04/02 02/04 03/15 02/04 06/13 02/04 02/06 01/11 02/08 04/02
            """)
        XCTAssertTrue(set.usesCodeExtensions)
        XCTAssertEqual(set.decode(bytes, vr: .PN), text)
        XCTAssertEqual(set.encode(text, vr: .PN), bytes)
    }

    func testAnnexH3JapanesePersonNameWithKatakanaValue1() throws {
        let set = DICOMCharacterSet(specificCharacterSet: "ISO 2022 IR 13\\ISO 2022 IR 87")
        let text = "ﾔﾏﾀﾞ^ﾀﾛｳ=山田^太郎=やまだ^たろう"
        let bytes = columnRow("""
            13/04 12/15 12/00 13/14 05/14 12/00 13/11 11/03 03/13 01/11 02/04 04/02 03/11 03/03 04/05 04/04 \
            01/11 02/08 04/10 05/14 01/11 02/04 04/02 04/02 04/00 04/15 03/10 01/11 02/08 04/10 03/13 01/11 \
            02/04 04/02 02/04 06/04 02/04 05/14 02/04 04/00 01/11 02/08 04/10 05/14 01/11 02/04 04/02 02/04 \
            03/15 02/04 06/13 02/04 02/06 01/11 02/08 04/10
            """)
        XCTAssertEqual(set.decode(bytes, vr: .PN), text)
        XCTAssertEqual(set.encode(text, vr: .PN), bytes)
    }

    // MARK: PS3.5 Annex I (Korean)

    func testAnnexI2KoreanPersonName() throws {
        let set = DICOMCharacterSet(specificCharacterSet: "\\ISO 2022 IR 149")
        let text = "Hong^Gildong=洪^吉洞=홍^길동"
        let bytes = columnRow("""
            04/08 06/15 06/14 06/07 05/14 04/07 06/09 06/12 06/04 06/15 06/14 06/07 03/13 01/11 02/04 02/09 \
            04/03 15/11 15/03 05/14 01/11 02/04 02/09 04/03 13/01 12/14 13/04 13/07 03/13 01/11 02/04 02/09 \
            04/03 12/08 10/11 05/14 01/11 02/04 02/09 04/03 11/01 14/06 11/05 11/15
            """)
        XCTAssertEqual(set.decode(bytes, vr: .PN), text)
        XCTAssertEqual(set.encode(text, vr: .PN), bytes)
    }

    func testAnnexI3KoreanLongTextWithEscapeAtLineStart() throws {
        // Annex I.3 designates KS X 1001 at the head of each line; Hangul
        // 한 and 글 are C7D1H and B1DBH in KS X 1001 (GR).
        let set = DICOMCharacterSet(specificCharacterSet: "\\ISO 2022 IR 149")
        let escape: [UInt8] = [0x1B, 0x24, 0x29, 0x43]
        let hangul: [UInt8] = [0xC7, 0xD1, 0xB1, 0xDB]
        var bytes = escape + Array("The first line includes ".utf8) + hangul + Array(".\r\n".utf8)
        bytes += escape + Array("The second line includes ".utf8) + hangul + Array(", too.\r\n".utf8)
        bytes += Array("The third line".utf8)
        let text = "The first line includes 한글.\r\nThe second line includes 한글, too.\r\nThe third line"

        XCTAssertEqual(set.decode(Data(bytes), vr: .LT), text)
        // DcmSwift designates G1 just before the first Hangul of each line,
        // which PS3.5 6.1.2.5.3 equally permits.
        let encoded = try XCTUnwrap(set.encode(text, vr: .LT))
        XCTAssertEqual(set.decode(encoded, vr: .LT), text)
        XCTAssertEqual(encoded.count, bytes.count)
    }

    // MARK: PS3.5 Annex J (UTF-8, GB18030)

    func testAnnexJ1ChinesePersonNameInUTF8() throws {
        let bytes = hex("""
            0x57 0x61 0x6e 0x67 0x5e 0x58 0x69 0x61 0x6f 0x44 0x6f 0x6e 0x67 0x3d 0xe7 0x8e 0x8b 0x5e 0xe5 \
            0xb0 0x8f 0xe6 0x9d 0xb1 0x3d
            """)
        XCTAssertEqual(DICOMCharacterSet.utf8.decode(bytes, vr: .PN), "Wang^XiaoDong=王^小東=")
        XCTAssertEqual(DICOMCharacterSet.utf8.encode("Wang^XiaoDong=王^小東=", vr: .PN), bytes)
    }

    func testAnnexJ2ChineseLongTextInUTF8() throws {
        let bytes = hex("""
            0x54 0x68 0x65 0x20 0x66 0x69 0x72 0x73 0x74 0x20 0x6c 0x69 0x6e 0x65 0x20 0x69 0x6e 0x63 0x6c \
            0x75 0x64 0x65 0x73 0xe4 0xb8 0xad 0xe6 0x96 0x87 0x2e 0x0d 0x0a 0x54 0x68 0x65 0x20 0x73 0x65 \
            0x63 0x6f 0x6e 0x64 0x20 0x6c 0x69 0x6e 0x65 0x20 0x69 0x6e 0x63 0x6c 0x75 0x64 0x65 0x73 0xe4 \
            0xb8 0xad 0xe6 0x96 0x87 0x2c 0x20 0x74 0x6f 0x6f 0x2e 0x0d 0x0a 0x54 0x68 0x65 0x20 0x74 0x68 \
            0x69 0x72 0x64 0x20 0x6c 0x69 0x6e 0x65 0x2e 0x0d 0x0a
            """)
        let text = "The first line includes中文.\r\nThe second line includes中文, too.\r\nThe third line.\r\n"
        XCTAssertEqual(DICOMCharacterSet.utf8.decode(bytes, vr: .LT), text)
        XCTAssertEqual(DICOMCharacterSet.utf8.encode(text, vr: .LT), bytes)
    }

    func testAnnexJ3ChinesePersonNameInGB18030() throws {
        let set = DICOMCharacterSet(specificCharacterSet: "GB18030")
        let bytes = hex("""
            0x57 0x61 0x6e 0x67 0x5e 0x58 0x69 0x61 0x6f 0x44 0x6f 0x6e 0x67 0x3d 0xcd 0xf5 0x5e 0xd0 0xa1 \
            0xb6 0xab 0x3d
            """)
        XCTAssertEqual(set.decode(bytes, vr: .PN), "Wang^XiaoDong=王^小东=")
        XCTAssertEqual(set.encode("Wang^XiaoDong=王^小东=", vr: .PN), bytes)
    }

    func testAnnexJ4ChineseLongTextInGB18030() throws {
        let set = DICOMCharacterSet(specificCharacterSet: "GB18030")
        let bytes = hex("""
            0x54 0x68 0x65 0x20 0x66 0x69 0x72 0x73 0x74 0x20 0x6c 0x69 0x6e 0x65 0x20 0x69 0x6e 0x63 0x6c \
            0x75 0x64 0x65 0x73 0xd6 0xd0 0xce 0xc4 0x2e 0x0d 0x0a 0x54 0x68 0x65 0x20 0x73 0x65 0x63 0x6f \
            0x6e 0x64 0x20 0x6c 0x69 0x6e 0x65 0x20 0x69 0x6e 0x63 0x6c 0x75 0x64 0x65 0x73 0xd6 0xd0 0xce \
            0xc4 0x2c 0x20 0x74 0x6f 0x6f 0x2e 0x0d 0x0a 0x54 0x68 0x65 0x20 0x74 0x68 0x69 0x72 0x64 0x20 \
            0x6c 0x69 0x6e 0x65 0x2e 0x0d 0x0a
            """)
        let text = "The first line includes中文.\r\nThe second line includes中文, too.\r\nThe third line.\r\n"
        XCTAssertEqual(set.decode(bytes, vr: .LT), text)
        XCTAssertEqual(set.encode(text, vr: .LT), bytes)
    }

    // MARK: PS3.5 Annex K (Chinese with Code Extensions)

    func testAnnexK2ChinesePersonNameWithGB2312() throws {
        let set = DICOMCharacterSet(specificCharacterSet: "\\ISO 2022 IR 58")
        let bytes = hex("""
            0x5A 0x68 0x61 0x6E 0x67 0x5E 0x58 0x69 0x61 0x6F 0x44 0x6F 0x6E 0x67 0x3D 0x1B 0x24 0x29 0x41 \
            0xD5 0xC5 0x5E 0x1B 0x24 0x29 0x41 0xD0 0xA1 0xB6 0xAB 0x3D 0x20
            """)
        // The final 20H is the Value Field padding.
        XCTAssertEqual(set.decode(bytes, vr: .PN), "Zhang^XiaoDong=张^小东= ")
        XCTAssertEqual(set.encode("Zhang^XiaoDong=张^小东=", vr: .PN), bytes.dropLast())
    }

    func testAnnexK3ChineseLongTextWithGB2312() throws {
        let set = DICOMCharacterSet(specificCharacterSet: "\\ISO 2022 IR 58")
        let bytes = hex("""
            0x31 0x2e 0x1B 0x24 0x29 0x41 0xB5 0xDA 0xD2 0xBB 0xD0 0xD0 0xCE 0xC4 0xD7 0xD6 0xA1 0xA3 0x0D 0x0A \
            0x32 0x2e 0x1B 0x24 0x29 0x41 0xB5 0xDA 0xB6 0xFE 0xD0 0xD0 0xCE 0xC4 0xD7 0xD6 0xA1 0xA3 0x0D 0x0A \
            0x33 0x2e 0x1B 0x24 0x29 0x41 0xB5 0xDA 0xC8 0xFD 0xD0 0xD0 0xCE 0xC4 0xD7 0xD6 0xA1 0xA3 0x0D 0x0A
            """)
        let text = "1.第一行文字。\r\n2.第二行文字。\r\n3.第三行文字。\r\n"
        XCTAssertEqual(set.decode(bytes, vr: .LT), text)
        XCTAssertEqual(set.encode(text, vr: .LT), bytes)
    }

    // MARK: DCMTK test files (pydicom 3.0.2 decoding)

    func testDCMTKCharacterSetFilesMatchPydicom() throws {
        let vectors: [(file: String, specificCharacterSet: String, bytes: String, text: String)] = [
            ("chrArab", "ISO_IR 127", "e2c8c7e6ea5ee4e6d2c7d1", "قباني^لنزار"),
            ("chrFren", "ISO_IR 100", "4275635e4ae972f46d65", "Buc^Jérôme"),
            ("chrGerm", "ISO_IR 100", "c46e6561735e52fc6469676572", "Äneas^Rüdiger"),
            ("chrGreek", "ISO_IR 126", "c4e9efedf5f3e9eff2", "Διονυσιος"),
            ("chrH31", "\\ISO 2022 IR 87",
             "59616d6164615e5461726f753d1b24423b3345441b28425e1b244242404f3a1b28423d1b24422464245e24401b28425e1b2442243f246d24261b2842",
             "Yamada^Tarou=山田^太郎=やまだ^たろう"),
            ("chrH32", "ISO 2022 IR 13\\ISO 2022 IR 87",
             "d4cfc0de5ec0dbb33d1b24423b3345441b284a5e1b244242404f3a1b284a3d1b24422464245e24401b284a5e1b2442243f246d24261b284a",
             "ﾔﾏﾀﾞ^ﾀﾛｳ=山田^太郎=やまだ^たろう"),
            ("chrHbrw", "ISO_IR 138", "f9f8e5ef5ee3e1e5f8e4", "שרון^דבורה"),
            ("chrI2", "\\ISO 2022 IR 149",
             "486f6e675e47696c646f6e673d1b242943fbf35e1b242943d1ced4d73d1b242943c8ab5e1b242943b1e6b5bf",
             "Hong^Gildong=洪^吉洞=홍^길동"),
            ("chrJapMulti", "\\ISO 2022 IR 87", "1b24422464245e24401b28425e1b2442243f246d24261b2842", "やまだ^たろう"),
            ("chrJapMultiExplicitIR6", "ISO 2022 IR 6\\ISO 2022 IR 87",
             "1b24422464245e24401b28425e1b2442243f246d24261b2842", "やまだ^たろう"),
            ("chrKoreanMulti", "\\ISO 2022 IR 149", "1b242943b1e8c8f1c1df1b2842", "김희중"),
            ("chrRuss", "ISO_IR 144", "bbeeda6365dcd17970d3", "Люкceмбypг"),
            ("chrX1", "ISO_IR 192", "57616e675e5869616f446f6e673de78e8b5ee5b08fe69db13d", "Wang^XiaoDong=王^小東="),
            ("chrX2", "GB18030", "57616e675e5869616f446f6e673dcdf55ed0a1b6ab3d", "Wang^XiaoDong=王^小东="),
        ]
        for vector in vectors {
            let set = DICOMCharacterSet(specificCharacterSet: vector.specificCharacterSet)
            let bytes = Data(hexString: vector.bytes)
            XCTAssertEqual(set.decode(bytes, vr: .PN), vector.text, vector.file)
            let encoded = try XCTUnwrap(set.encode(vector.text, vr: .PN), vector.file)
            XCTAssertEqual(set.decode(encoded, vr: .PN), vector.text, vector.file)
        }
    }

    // MARK: Single-byte repertoires (CPython codecs)

    func testEverySingleByteRepertoireRoundTrips() throws {
        let vectors: [(term: String, text: String, bytes: String)] = [
            ("ISO_IR 100", "Günther", "47fc6e74686572"),  // PS3.5 6.1.2.3 example
            ("ISO_IR 101", "Łódź^Żaneta", "a3f364bc5eaf616e657461"),
            ("ISO_IR 109", "Ħaġar^Ġużeppi", "a161f561725ed575bf65707069"),
            ("ISO_IR 110", "Ģirts^Ķēniņš", "ab697274735ed3ba6e69f1b9"),
            ("ISO_IR 144", "Люкceмбypг", "bbeeda6365dcd17970d3"),
            ("ISO_IR 127", "قباني^لنزار", "e2c8c7e6ea5ee4e6d2c7d1"),
            ("ISO_IR 126", "Διονυσιος", "c4e9efedf5f3e9eff2"),
            ("ISO_IR 138", "שרון^דבורה", "f9f8e5ef5ee3e1e5f8e4"),
            ("ISO_IR 148", "Çağrı^Şükrü", "c761f072fd5edefc6b72fc"),
            ("ISO_IR 203", "Œuvre^Zoë€", "bc757672655e5a6feba4"),
            ("ISO_IR 166", "สมชาย^ใจดี", "cac1aad2c25ee3a8b4d5"),
            ("ISO_IR 13", "ﾔﾏﾀﾞ^ﾀﾛｳ", "d4cfc0de5ec0dbb3"),
        ]
        for vector in vectors {
            let set = DICOMCharacterSet(specificCharacterSet: vector.term)
            XCTAssertTrue(set.isSupported, vector.term)
            XCTAssertFalse(set.usesCodeExtensions, vector.term)
            XCTAssertEqual(set.encode(vector.text, vr: .PN), Data(hexString: vector.bytes), vector.term)
            XCTAssertEqual(set.decode(Data(hexString: vector.bytes), vr: .PN), vector.text, vector.term)
        }
    }

    func testSingleByteCodeExtensionsSwitchG1AndRestoreValue1() throws {
        let set = DICOMCharacterSet(specificCharacterSet: "ISO 2022 IR 100\\ISO 2022 IR 126")
        let text = "Dupont^Hélène=Διονυσιος"
        let encoded = try XCTUnwrap(set.encode(text, vr: .PN))
        // Latin-1 is active initially; Greek is designated with ESC 02/13
        // 04/06 and Latin-1 is restored with ESC 02/13 04/01 at the end.
        XCTAssertEqual(encoded, Data("Dupont^H".utf8) + Data([0xE9]) + Data("l".utf8) + Data([0xE8])
            + Data("ne=".utf8) + Data([0x1B, 0x2D, 0x46, 0xC4, 0xE9, 0xEF, 0xED, 0xF5, 0xF3, 0xE9, 0xEF, 0xF2])
            + Data([0x1B, 0x2D, 0x41]))
        XCTAssertEqual(set.decode(encoded, vr: .PN), text)
    }

    // MARK: Delimiters (PS3.5 6.1.2.3)

    func testOnlySingleByte0512SeparatesValues() throws {
        // GBK 乗 is 815CH: its trail byte is not a value delimiter.
        let gbk = DICOMCharacterSet(specificCharacterSet: "GBK")
        XCTAssertEqual(gbk.decode(Data([0x41, 0x5C, 0x81, 0x5C]), vr: .LO), "A\\乗")
        XCTAssertEqual(gbk.encode("A\\乗", vr: .LO), Data([0x41, 0x5C, 0x81, 0x5C]))

        // JIS X 0208 移 is 305CH: inside ESC $ B it is one kanji.
        let japanese = DICOMCharacterSet(specificCharacterSet: "\\ISO 2022 IR 87")
        let kanji = Data([0x1B, 0x24, 0x42, 0x30, 0x5C, 0x1B, 0x28, 0x42])
        XCTAssertEqual(japanese.decode(kanji + Data([0x5C, 0x41]), vr: .LO), "移\\A")
        XCTAssertEqual(japanese.encode("移\\A", vr: .LO), kanji + Data([0x5C, 0x41]))
    }

    func testRomajiYenSignAndOverlineFollowISOIR14() throws {
        let set = DICOMCharacterSet(specificCharacterSet: "ISO_IR 13")
        // In multi-valued VRs 05/12 is the delimiter, whatever its glyph.
        XCTAssertEqual(set.decode(Data([0x41, 0x5C, 0x42]), vr: .LO), "A\\B")
        XCTAssertNil(set.encode("A¥B", vr: .LO))
        // In text VRs it is YEN SIGN; 07/14 is OVERLINE.
        XCTAssertEqual(set.decode(Data([0x41, 0x5C, 0x7E]), vr: .LT), "A¥‾")
        XCTAssertEqual(set.encode("A¥‾", vr: .LT), Data([0x41, 0x5C, 0x7E]))
        XCTAssertNil(set.encode("~", vr: .LT))
    }

    func testValue1IsRestoredAfterControlCharactersAndDelimiters() throws {
        let set = DICOMCharacterSet(specificCharacterSet: "\\ISO 2022 IR 87")
        // A decoder that kept JIS X 0208 active across CR LF would read the
        // second line as kanji pairs.
        let bytes = Data([0x1B, 0x24, 0x42, 0x30, 0x5C, 0x0D, 0x0A, 0x41, 0x42])
        XCTAssertEqual(set.decode(bytes, vr: .LT), "移\r\nAB")
        XCTAssertEqual(set.encode("移\r\nAB", vr: .LT),
                       Data([0x1B, 0x24, 0x42, 0x30, 0x5C, 0x1B, 0x28, 0x42, 0x0D, 0x0A, 0x41, 0x42]))
    }

    // MARK: GB18030-2022

    func testGB18030FourByteAndSupplementaryCodes() throws {
        let set = DICOMCharacterSet(specificCharacterSet: "GB18030")
        let vectors: [(String, String)] = [
            ("\u{0080}", "81308130"), ("€", "a2e3"), ("\u{FFFD}", "8431a437"),
            ("\u{10000}", "90308130"), ("\u{10FFFF}", "e3329a35"), ("\u{3000}", "a1a1"),
            ("\u{E5E5}", "a3a0"),
            // GB18030-2022 moved U+FE10 from 84318236H to A6D9H.
            ("\u{FE10}", "a6d9"),
        ]
        for (text, bytes) in vectors {
            XCTAssertEqual(set.encode(text), Data(hexString: bytes), bytes)
            XCTAssertEqual(set.decode(Data(hexString: bytes)), text, bytes)
        }
        XCTAssertEqual(set.decode(Data(hexString: "84318236")), "\u{FE10}")

        let gbk = DICOMCharacterSet(specificCharacterSet: "GBK")
        XCTAssertNil(gbk.encode("\u{0080}"))
        XCTAssertNil(gbk.decode(Data(hexString: "81308130")))
        XCTAssertEqual(gbk.decode(Data(hexString: "a2e3")), "€")
    }

    // MARK: Malformed input and declarations

    func testMalformedBytesAreNotDecoded() {
        let japanese = DICOMCharacterSet(specificCharacterSet: "\\ISO 2022 IR 87")
        XCTAssertNil(japanese.decode(Data([0x1B, 0x24, 0x40, 0x41])), "unknown escape sequence")
        XCTAssertNil(japanese.decode(Data([0x1B, 0x24, 0x42, 0x30])), "truncated two-byte character")
        XCTAssertNil(japanese.decode(Data([0x41, 0x85])), "C1 Control Character")
        XCTAssertNil(japanese.decode(Data([0xE9])), "GR byte without a G1 set")
        XCTAssertNil(DICOMCharacterSet.latin1.decode(Data([0x1B, 0x2D, 0x46, 0xC4])), "escape without Code Extensions")
        XCTAssertNil(DICOMCharacterSet.defaultRepertoire.decode(Data([0xE9])))
        XCTAssertNil(DICOMCharacterSet(specificCharacterSet: "ISO_IR 166").decode(Data([0xA0])), "unassigned TIS 620 byte")
        XCTAssertNil(DICOMCharacterSet(specificCharacterSet: "GB18030").decode(Data([0x80])))
        XCTAssertNil(DICOMCharacterSet(specificCharacterSet: "GB18030").decode(Data([0x81, 0x30])))
        XCTAssertNil(DICOMCharacterSet.utf8.decode(Data([0xC0, 0xAF])), "overlong UTF-8")
        XCTAssertNil(DICOMCharacterSet.latin1.encode("Δ"))
        // JIS X 0208 includes Greek and Cyrillic, but not Thai.
        XCTAssertNil(japanese.encode("ส"))
    }

    func testSpecificCharacterSetDeclarations() {
        for supported in ["", "ISO_IR 6", "ISO 2022 IR 6", "ISO_IR 13", "ISO_IR 192", "GB18030", "GBK",
                          "\\ISO 2022 IR 87\\ISO 2022 IR 159", "ISO 2022 IR 6\\ISO 2022 IR 149",
                          "ISO 2022 IR 100\\ISO 2022 IR 101\\ISO 2022 IR 144", "\\ISO 2022 IR 58"] {
            XCTAssertTrue(DICOMCharacterSet(specificCharacterSet: supported).isSupported, supported)
        }
        for unsupported in ["ISO_IR 999", "ISO 2022 IR 87", "ISO_IR 87", "UTF-8",
                            "ISO_IR 192\\ISO 2022 IR 87", "\\GB18030", "\\ISO_IR 100",
                            "ISO 2022 IR 87\\ISO 2022 IR 100"] {
            XCTAssertFalse(DICOMCharacterSet(specificCharacterSet: unsupported).isSupported, unsupported)
        }
        XCTAssertEqual(DICOMCharacterSet(specificCharacterSet: "ISO_IR 6"), .defaultRepertoire)
        XCTAssertEqual(DICOMCharacterSet(specificCharacterSet: " ISO_IR 100 "), .latin1)
        XCTAssertEqual(DICOMCharacterSet(specificCharacterSet: "\\ISO 2022 IR 87").identifiers, ["", "ISO 2022 IR 87"])
    }

    // MARK: Data Set integration

    func testCodeExtensionsRoundTripThroughPart10Encoding() throws {
        let source = DataSet()
        XCTAssertNotNil(source.set(value: "\\ISO 2022 IR 87", forTagName: "SpecificCharacterSet"))
        XCTAssertNotNil(source.set(value: "Yamada^Tarou=山田^太郎", forTagName: "PatientName"))
        XCTAssertNotNil(source.set(value: "移\\表", forTagName: "OtherPatientIDs"))

        let encoded = source.toData(vrMethod: .Explicit, byteOrder: .LittleEndian)
        let decoded = try XCTUnwrap(try DicomInputStream(data: encoded).readDataset(enforceVR: false))
        XCTAssertTrue(decoded.characterSet.usesCodeExtensions)
        XCTAssertEqual(decoded.string(forTag: "PatientName"), "Yamada^Tarou=山田^太郎")
        XCTAssertEqual(decoded.string(forTag: "OtherPatientIDs"), "移\\表")
    }

    // MARK: Helpers

    /// Bytes written in the PS3.5 column/row notation, e.g. "05/09 01/11".
    private func columnRow(_ text: String) -> Data {
        Data(text.split(separator: " ").map { pair in
            let parts = pair.split(separator: "/")
            return UInt8(Int(parts[0])! * 16 + Int(parts[1])!)
        })
    }

    /// Bytes written as "0x57 0x61 ...".
    private func hex(_ text: String) -> Data {
        Data(text.split(separator: " ").map { UInt8($0.dropFirst(2), radix: 16)! })
    }
}

private extension Data {
    init(hexString: String) {
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            bytes.append(UInt8(hexString[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}
