import Foundation

private struct DICOMConvertedViewStore: DICOMInstanceStore {
    let items: [String: DICOMRetrieveItem]
    func write(_ instance: DICOMReceivedInstance) async throws -> String { throw DICOMEnhancedMultiFrameConversion.error("converted views are read-only") }
    func remove(_ location: String) async throws { throw DICOMEnhancedMultiFrameConversion.error("converted views are read-only") }
    func exists(_ location: String) async -> Bool { items[location] != nil }
    func item(at location: String) async throws -> DICOMRetrieveItem {
        guard let item = items[location] else { throw DICOMEnhancedMultiFrameConversion.error("missing converted instance") }
        return item
    }
}

extension DICOMArchive {
    /// The complete source catalogue is converted before matching identifiers.
    /// This is a transient read-only index; originals are never overwritten.
    func queryRetrieveView(_ identifier: DataSet) async throws -> DICOMArchive {
        guard let name = identifier.string(forTag: "QueryRetrieveView"),
              let view = DICOMEnhancedMultiFrameConversion.View(rawValue: name) else { return self }
        var items: [DICOMRetrieveItem] = []
        for document in try await index.documents(in: .instances, matching: .init(conditions: [])) {
            items.append(try await item(Self.record(document)))
        }
        let converted = try DICOMEnhancedMultiFrameConversion.convert(items, to: view)
        let viewStore = DICOMConvertedViewStore(items: Dictionary(uniqueKeysWithValues: converted.map { ($0.sopInstanceUID, $0) }))
        let result = DICOMArchive(store: viewStore)
        for item in converted {
            let dataSet = try DICOMDataSetCoding.decode(item.payload.data(), transferSyntax: item.transferSyntaxUID)
            let header = DICOMPart10Header(sopClassUID: item.sopClassUID, sopInstanceUID: item.sopInstanceUID,
                transferSyntaxUID: item.transferSyntaxUID, dataSetOffset: 0, dataSetLength: 0)
            let record = Self.record(location: item.sopInstanceUID, header: header, dataSet: dataSet)
            try await result.index.save(Self.document(record), in: .instances)
        }
        return result
    }
}
