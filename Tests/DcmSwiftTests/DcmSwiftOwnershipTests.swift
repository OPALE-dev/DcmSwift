import XCTest
@testable import DcmSwift

final class DcmSwiftOwnershipTests: XCTestCase {
    func testConstructedDatasetAndPixelElementAreReleased() throws {
        weak var dataset: DataSet?
        weak var pixels: DataElement?
        do {
            let object = DataSet()
            object.set(value: "CT", forTagName: "Modality")
            object.set(value: Data(repeating: 7, count: 512 * 1024), forTagName: "PixelData")
            dataset = object
            pixels = object.element(forTagName: "PixelData")
            XCTAssertEqual(pixels?.data.count, 512 * 1024)
        }
        XCTAssertNil(dataset)
        XCTAssertNil(pixels)
    }

    func testNestedSequenceAndItemDoNotRetainTheirParents() throws {
        weak var dataset: DataSet?
        weak var sequence: DataSequence?
        weak var item: DataItem?
        weak var child: DataElement?
        do {
            let object = DataSet()
            let seq = DataSequence(withTag: try XCTUnwrap(DicomSpec.shared.dataTag(forName: "ReferencedStudySequence")), dataset: object)
            seq.vr = .SQ
            let entry = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), dataset: object, parent: seq)
            let leaf = try XCTUnwrap(DataElement(withTagName: "ReferencedSOPInstanceUID", dataset: object, parent: entry))
            XCTAssertTrue(leaf.setValue("1.2.3.4"))
            entry.elements = [leaf]; seq.items = [entry]; object.add(element: seq)
            dataset = object; sequence = seq; item = entry; child = leaf
            XCTAssertTrue(child?.parent === entry)
            XCTAssertTrue(item?.parent === seq)
        }
        XCTAssertNil(dataset); XCTAssertNil(sequence); XCTAssertNil(item); XCTAssertNil(child)
    }

    func testRetainedLeafKeepsEncodedTextAndReleasesOwnerAndSiblings() throws {
        weak var dataset: DataSet?
        weak var pixels: DataElement?
        var retained: DataElement?
        do {
            let object = DataSet()
            // Set the charset after element construction to exercise the live context and its snapshot.
            object.set(value: "Patient", forTagName: "PatientName")
            object.set(value: "ISO_IR 100", forTagName: "SpecificCharacterSet")
            retained = object.element(forTagName: "PatientName")
            XCTAssertTrue(try XCTUnwrap(retained).setTextValues(["DUPRÉ^Élodie"]))
            object.set(value: Data(repeating: 0, count: 512 * 1024), forTagName: "PixelData")
            dataset = object; pixels = object.element(forTagName: "PixelData")
        }
        XCTAssertNil(dataset); XCTAssertNil(pixels)
        XCTAssertNil(retained?.dataset)
        XCTAssertEqual(retained?.textValues, ["DUPRÉ^Élodie"])
        XCTAssertTrue(try XCTUnwrap(retained).setTextValues(["ANDRÉ^Léa"]))
        XCTAssertEqual(retained?.textValues, ["ANDRÉ^Léa"])
    }

    func testDecodedDatasetsAndPixelsAreReleasedAcrossRepeatedParses() throws {
        let object = DataSet()
        object.set(value: "CT", forTagName: "Modality")
        object.set(value: Data(repeating: 0, count: 512 * 1024), forTagName: "PixelData")
        let encoded = object.toData(vrMethod: .Explicit, byteOrder: .LittleEndian)
        for _ in 0..<25 {
            weak var dataset: DataSet?
            weak var pixels: DataElement?
            do {
                let decoded = try DICOMDataSetCoding.decode(encoded, transferSyntax: "1.2.840.10008.1.2.1")
                dataset = decoded; pixels = decoded.element(forTagName: "PixelData")
                XCTAssertEqual(pixels?.data.count, 512 * 1024)
            }
            XCTAssertNil(dataset); XCTAssertNil(pixels)
        }
    }
    func testRetainedSequenceChildKeepsItsTextWithoutOwningTheTree() throws {
        var retained: DataElement?
        weak var owner: DataSet?
        weak var parent: DataItem?
        do {
            let object = DataSet()
            object.set(value: "ISO_IR 100", forTagName: "SpecificCharacterSet")
            let seq = DataSequence(withTag: try XCTUnwrap(DicomSpec.shared.dataTag(forName: "ReferencedStudySequence")), dataset: object)
            seq.vr = .SQ
            let entry = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), dataset: object, parent: seq)
            let leaf = try XCTUnwrap(DataElement(withTagName: "PatientName", dataset: object, parent: entry))
            XCTAssertTrue(leaf.setTextValues(["DUPRÉ^Élodie"]))
            entry.elements = [leaf]; seq.items = [entry]; object.add(element: seq)
            let bytes = object.toData(vrMethod: .Explicit, byteOrder: .LittleEndian)
            let decoded = try DICOMDataSetCoding.decode(bytes, transferSyntax: "1.2.840.10008.1.2.1")
            let decodedItem = try XCTUnwrap(decoded.sequence(forTagName: "ReferencedStudySequence")?.items.first)
            retained = decodedItem.element(withName: "PatientName")
            owner = decoded; parent = decodedItem
        }
        XCTAssertNil(owner); XCTAssertNil(parent)
        XCTAssertNil(retained?.dataset); XCTAssertNil(retained?.parent)
        XCTAssertEqual(retained?.textValues, ["DUPRÉ^Élodie"])
    }

    func testRetainedDeferredValueCanStillLoadAfterItsOwnerIsReleased() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-ownership-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data(repeating: 0xa5, count: 256 * 1024)
        var retained: DataElement?
        weak var owner: DataSet?
        do {
            let object = DataSet()
            object.set(value: bytes, forTagName: "SelectorOBValue")
            try object.toData().write(to: url)
            let stream = DicomInputStream(url: url)
            stream.bulkDataLoadingPolicy = .lazy(minimumLength: 1024)
            let decoded = try XCTUnwrap(try stream.readDataset(enforceVR: false))
            retained = decoded.element(forTagName: "SelectorOBValue")
            owner = decoded
        }
        XCTAssertNil(owner); XCTAssertNil(retained?.dataset)
        XCTAssertEqual(retained?.isDataLoaded, false)
        XCTAssertEqual(try retained?.loadData(), bytes)
    }

    func testStructuredReportNodesReleaseTheirTree() {
        weak var root: SRNode?
        weak var child: SRNode?
        do {
            let parent = SRNode(parent: nil)
            let leaf = SRNode(parent: parent)
            parent.nodes = [leaf]
            root = parent; child = leaf
            XCTAssertTrue(leaf.parent === parent)
            XCTAssertEqual(leaf.level, 2)
        }
        XCTAssertNil(root)
        XCTAssertNil(child)
    }

    func testRetainedStructuredReportChildDoesNotRetainAncestors() {
        var retained: SRNode?
        weak var root: SRNode?
        do {
            let parent = SRNode(parent: nil)
            let leaf = SRNode(parent: parent)
            parent.nodes = [leaf]
            retained = leaf; root = parent
        }
        XCTAssertNil(root)
        XCTAssertNil(retained?.parent)
        XCTAssertEqual(retained?.level, 2)
    }

}
