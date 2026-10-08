import XCTest
@testable import DcmSwift

/// DICOMwebClient against an independent origin server, such as Orthanc with
/// its DICOMweb plugin. Runs when both variables are set:
///
/// - `DCMSWIFT_DICOMWEB_ORACLE`: the service root, such as
///   http://127.0.0.1:8042/dicom-web, over an empty archive;
/// - `DCMSWIFT_DICOMWEB_FILES`: a directory of Part 10 files to store.
final class DcmSwiftWebInteropTests: XCTestCase {
    func testClientAgainstAnIndependentOriginServer() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let base = environment["DCMSWIFT_DICOMWEB_ORACLE"], let folder = environment["DCMSWIFT_DICOMWEB_FILES"] else {
            throw XCTSkip("Set DCMSWIFT_DICOMWEB_ORACLE and DCMSWIFT_DICOMWEB_FILES to run")
        }
        let client = DICOMwebClient(baseURI: base)
        let urls = (FileManager.default.enumerator(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []).filter { !$0.hasDirectoryPath }.sorted { $0.path < $1.path }
        var checked = 0, skipped = 0
        var seen = Set<String>()
        for url in urls {
            // Instances Web Services can carry, with valid identification.
            guard let header = try? DICOMPart10Header.read(url),
                  header.transferSyntaxUID != TransferSyntax.implicitVRLittleEndian,
                  header.transferSyntaxUID != TransferSyntax.explicitVRBigEndian,
                  let file = DicomFile(forPath: url.path), let original = file.dataset,
                  let study = original.string(forTag: "StudyInstanceUID"), DICOMUniqueIdentifier.isValid(study),
                  let series = original.string(forTag: "SeriesInstanceUID"), DICOMUniqueIdentifier.isValid(series),
                  let instance = original.string(forTag: "SOPInstanceUID"), DICOMUniqueIdentifier.isValid(instance),
                  instance == header.sopInstanceUID, seen.insert(instance).inserted else {
                // Including files that reuse the UID of another file.
                skipped += 1
                continue
            }
            let name = url.lastPathComponent
            let stored: DICOMwebStoreResponse
            do { stored = try await client.store(files: [url]) } catch let error as DICOMwebClientError where error.status == 400 {
                // The origin server refuses a file it cannot parse.
                print("\(name): refused by the origin server (\(error.status))")
                skipped += 1
                continue
            }
            guard stored.stored.contains(where: { $0.sopInstanceUID == instance }) else {
                XCTFail("\(name): not stored: \(stored)")
                continue
            }
            checked += 1

            var query = DICOMwebSearchQuery()
            query.match("SOPInstanceUID", instance)
            let found = try await client.search(.instance, study: study, series: series, query: query)
            XCTAssertEqual(found.matches.count, 1, "\(name): search")

            var retrieved: [DICOMwebRetrievedInstance] = []
            for try await part in client.instances(study: study, series: series, instance: instance, transferSyntax: "*") {
                retrieved.append(part)
            }
            XCTAssertEqual(retrieved.count, 1, "\(name): retrieve")
            if let copy = try? retrieved.first?.dataSet() {
                let expected = try Self.comparable(original), actual = try Self.comparable(copy)
                for key in Set(expected.keys).union(actual.keys).sorted() where expected[key] != actual[key] {
                    XCTFail("\(name): \(key) \(expected[key] ?? "absent") != \(actual[key] ?? "absent")")
                }
            }

            let metadata = try await client.metadata(study: study, series: series, instance: instance)
            XCTAssertEqual(metadata.first?.string(forTag: "SOPInstanceUID"), instance, "\(name): metadata")

            // Frames and a rendered image of uncompressed images.
            if header.transferSyntaxUID == TransferSyntax.explicitVRLittleEndian,
               let description = try? DICOMPixelDescription(dataset: original), description.bitsAllocated >= 8,
               let native = try? DICOMNativePixelData(dataset: original, description: description) {
                let frames = try await client.frames([1], study: study, series: series, instance: instance)
                XCTAssertEqual(frames.first, try native.frameData(0), "\(name): frame 1")
                let resource = description.numberOfFrames > 1
                    ? DICOMwebResource.frames([1], study: study, series: series, instance: instance, rendered: true)
                    : DICOMwebResource.target(study: study, series: series, instance: instance, kind: .rendered)
                do {
                    let images = try await client.rendered(resource, mediaType: .jpeg)
                    XCTAssertEqual(images.first?.starts(with: [0xFF, 0xD8]), true, "\(name): rendered")
                } catch let error as DICOMwebClientError where (400..<600).contains(error.status) {
                    // Orthanc does not render 32-bit images, for example.
                    print("\(name): rendering refused by the origin server (\(error.status))")
                }
            }
        }
        print("DICOMweb interoperability: \(checked) instances checked, \(skipped) files skipped")
        XCTAssertGreaterThan(checked, 0)
    }

    /// Top-level attributes other than Pixel Data, Group Lengths, and File
    /// Meta Information, as DICOM JSON text. Empty attributes are left out:
    /// Orthanc drops zero-length elements from the instances it returns.
    static func comparable(_ dataSet: DataSet) throws -> [String: String] {
        let object = try DICOMJSON.object(dataSet)
        var result: [String: String] = [:]
        for (key, value) in object where !key.hasPrefix("0002") && !key.hasSuffix("0000") && !key.hasPrefix("7FE0") {
            if let attribute = value as? [String: Any], attribute.count == 1 { continue }
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
            result[key] = String(decoding: data, as: UTF8.self)
        }
        return result
    }
}
