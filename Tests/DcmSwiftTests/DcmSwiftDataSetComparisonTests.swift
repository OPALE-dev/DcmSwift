import XCTest
@testable import DcmSwift

/// The differences between two Data Sets, Sequence Items included.
final class DcmSwiftDataSetComparisonTests: XCTestCase {
    private func image() throws -> DataSet {
        let dataSet = DcmSwiftIODValidationTests.secondaryCaptureImage()
        _ = dataSet.set(value: "DOE^JANE", forTagName: "PatientName")
        _ = dataSet.set(value: "CT01", forTagName: "StationName")
        let sequence = DataSequence(withTag: try XCTUnwrap(DicomSpec.shared.dataTag(forName: "ReferencedInstanceSequence")))
        sequence.vr = .SQ
        sequence.length = -1
        for uid in ["1.2.826.0.1.3680043.10.1.9", "1.2.826.0.1.3680043.10.1.10"] {
            let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
            item.length = -1
            let element = try XCTUnwrap(DataElement(withTagName: "ReferencedSOPInstanceUID", dataset: dataSet, parent: item))
            element.vr = .UI
            XCTAssertTrue(element.setValue(uid))
            item.elements.append(element)
            sequence.items.append(item)
        }
        dataSet.add(element: sequence)
        dataSet.sortElements()
        return dataSet
    }

    private func reread(_ dataSet: DataSet, _ syntax: String) throws -> DataSet {
        try DICOMDataSetCoding.decode(DICOMDataSetCoding.encode(dataSet, transferSyntax: syntax), transferSyntax: syntax)
    }

    func testADataSetEqualsItselfInEveryUncompressedSyntax() throws {
        let dataSet = try image()
        XCTAssertEqual(DICOMDataSetComparison.differences(from: dataSet, to: dataSet), [])
        for syntax in [TransferSyntax.explicitVRLittleEndian, TransferSyntax.explicitVRBigEndian] {
            let other = try reread(dataSet, syntax)
            XCTAssertEqual(DICOMDataSetComparison.differences(from: dataSet, to: other, includesMetaInformation: false), [], syntax)
        }
        // Implicit VR: Pixel Data is read as OW (PS3.5 A.1 c), its value unchanged.
        let implicit = DICOMDataSetComparison.differences(
            from: dataSet, to: try reread(dataSet, TransferSyntax.implicitVRLittleEndian), includesMetaInformation: false)
        XCTAssertEqual(implicit.map(\.kind), [.changed(vr: true, value: false)])
        XCTAssertEqual(implicit.first?.path, [.init(tag: "7FE00010")])
    }

    func testAddedRemovedAndChangedAttributes() throws {
        let left = try image()
        let right = try reread(left, TransferSyntax.explicitVRBigEndian)
        _ = right.set(value: "DOE^JOHN", forTagName: "PatientName")
        _ = right.remove(dataElement: try XCTUnwrap(right.element(forTagName: "StationName")))
        _ = right.set(value: "A12345", forTagName: "AccessionNumber")
        _ = right.set(value: UInt16(3), forTagName: "Columns")
        right.sortElements()

        let differences = DICOMDataSetComparison.differences(from: left, to: right, includesMetaInformation: false)
        let byTag = Dictionary(uniqueKeysWithValues: differences.map { ($0.path.map(\.description).joined(separator: " "), $0) })
        let name = try XCTUnwrap(byTag["(0010,0010)"])
        XCTAssertEqual(name.kind, .changed(vr: false, value: true))
        XCTAssertEqual(name.left?.value, .text(["DOE^JANE"]))
        XCTAssertEqual(name.right?.value, .text(["DOE^JOHN"]))
        XCTAssertEqual(byTag["(0008,1010)"]?.kind, .removed)
        XCTAssertNil(byTag["(0008,1010)"]?.right)
        let accession = try XCTUnwrap(byTag["(0008,0050)"])
        XCTAssertEqual(accession.kind, left.element(forTagName: "AccessionNumber") == nil ? .added : .changed(vr: false, value: true))
        // A US value, Big Endian on one side: compared as its value.
        let columns = try XCTUnwrap(byTag["(0028,0011)"])
        XCTAssertEqual(columns.kind, .changed(vr: false, value: true))
        XCTAssertEqual(columns.right?.value, .bytes(Data([3, 0])))
        XCTAssertEqual(differences.count, 4)
        // In the order of the tags.
        XCTAssertEqual(differences.map { $0.path[0].tag }, differences.map { $0.path[0].tag }.sorted())
    }

    func testVRAndItems() throws {
        let left = try image()
        let right = try reread(left, TransferSyntax.explicitVRLittleEndian)
        right.element(forTagName: "StationName")?.vr = .LO
        let sequence = try XCTUnwrap(right.element(forTagName: "ReferencedInstanceSequence") as? DataSequence)
        XCTAssertTrue(sequence.items[1].elements[0].setValue("1.2.826.0.1.3680043.10.1.11"))
        let extra = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
        sequence.items.append(extra)

        let differences = DICOMDataSetComparison.differences(from: left, to: right, includesMetaInformation: false)
        XCTAssertEqual(differences.map { $0.path.map(\.description).joined(separator: " ") },
                       ["(0008,1010)", "(0008,114A)[1] (0008,1155)", "(0008,114A)[2]"])
        XCTAssertEqual(differences[0].kind, .changed(vr: true, value: false))
        XCTAssertEqual(differences[0].left?.vr, "SH")
        XCTAssertEqual(differences[0].right?.vr, "LO")
        XCTAssertEqual(differences[1].kind, .changed(vr: false, value: true))
        XCTAssertEqual(differences[2].kind, .added)
        XCTAssertEqual(differences[2].right?.value, .item(attributes: 0))
        // The other way round, the Item is removed.
        let back = DICOMDataSetComparison.differences(from: right, to: left, includesMetaInformation: false)
        XCTAssertEqual(back.last?.kind, .removed)
    }

    func testFileMetaInformation() throws {
        let corpus = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Corpus/CT_ExplicitVRLittleEndian_SINGLE_MONOCHROME2_16.dcm")
        let first = try XCTUnwrap(DicomFile(forPath: corpus.path)?.dataset)
        let second = try XCTUnwrap(DicomFile(forPath: corpus.path)?.dataset)
        XCTAssertEqual(DICOMDataSetComparison.differences(from: first, to: second), [])
        _ = second.set(value: "OTHER", forTagName: "SourceApplicationEntityTitle")
        XCTAssertEqual(DICOMDataSetComparison.differences(from: first, to: second).first?.path.first?.tag.prefix(4), "0002")
        XCTAssertEqual(DICOMDataSetComparison.differences(from: first, to: second, includesMetaInformation: false), [])
    }

    /// Two CT images of the corpus: the attributes that differ are those
    /// pydicom 3.0.2 finds comparing the two files element by element.
    func testTwoImagesOfTheCorpusAsPydicomComparesThem() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Corpus")
        let explicit = try XCTUnwrap(DicomFile(forPath: folder.appendingPathComponent("CT_ExplicitVRLittleEndian_SINGLE_MONOCHROME2_16.dcm").path)?.dataset)
        let implicit = try XCTUnwrap(DicomFile(forPath: folder.appendingPathComponent("CT_ImplicitVRLittleEndian_SINGLE_MONOCHROME2_16.dcm").path)?.dataset)
        let differences = DICOMDataSetComparison.differences(from: explicit, to: implicit)
        XCTAssertEqual(differences.map { $0.path.map(\.description).joined() },
                       ["(0002,0000)", "(0002,0003)", "(0002,0010)", "(0008,0018)", "(0008,103E)", "(0020,000D)",
                        "(0020,000E)", "(0028,0101)", "(0028,0102)", "(0028,0103)", "(7FE0,0010)"])
        XCTAssertTrue(differences.allSatisfy { $0.kind == .changed(vr: false, value: true) })
    }
}
