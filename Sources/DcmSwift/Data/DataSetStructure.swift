//
//  DataSetStructure.swift
//  DcmSwift
//
//  Changes to the structure of a data set: Data Elements added in tag
//  order and removed, at the top level or in a Sequence Item, and Items
//  added, removed and moved in a Sequence (PS3.5 7.1, 7.5). Each change
//  returns what is needed to undo it.
//

import Foundation

/// Why a change to the structure of a data set was refused.
public enum DataSetStructureError: Error, Equatable, CustomStringConvertible {
    /// Group 0002 is the File Meta Information, written with the file (PS3.10 7.1).
    case fileMetaInformation
    /// Group Length elements (gggg,0000) are computed, not edited (PS3.5 7.2).
    case groupLength
    /// Items and delimiters (FFFE,xxxx) are the structure of Sequences, not elements (PS3.5 7.5).
    case itemOrDelimiter
    /// The data set or Item already holds an element with this tag (PS3.5 7.1).
    case duplicate(tag: String)
    /// The element or Item is not where the change looked for it.
    case notFound
    /// An Item position outside the Sequence.
    case itemIndexOutOfRange(Int)
    /// The data set was not fully read: its structure is not changed.
    case corrupted

    public var description: String {
        switch self {
        case .fileMetaInformation: "Group 0002 belongs to the File Meta Information"
        case .groupLength: "Group Length elements are computed when the data set is written"
        case .itemOrDelimiter: "Items and delimiters are not Data Elements"
        case .duplicate(let tag): "An element (\(tag)) is already there"
        case .notFound: "The element is not in this data set"
        case .itemIndexOutOfRange(let index): "No Item at position \(index)"
        case .corrupted: "The data set was not fully read"
        }
    }
}


extension DataSet {
    /// Checks that a tag can be added by hand: not File Meta Information,
    /// not a Group Length, not an Item or delimiter.
    ///
    /// - Parameter tag: the tag of the element to add.
    public static func checkAddable(_ tag: DataTag) throws {
        let group = tag.group.lowercased()
        if group == DicomConstants.metaInformationGroup { throw DataSetStructureError.fileMetaInformation }
        if group == "fffe" { throw DataSetStructureError.itemOrDelimiter }
        if tag.element.lowercased() == "0000" { throw DataSetStructureError.groupLength }
    }

    /// The elements an Item holds, or the data set's own when `item` is nil.
    ///
    /// - Parameter item: the Item, or nil for the top level.
    public func elements(in item: DataItem?) -> [DataElement] {
        item?.elements ?? datasetElements
    }

    /// A new element with an empty Value, not yet in the data set: a
    /// `DataSequence` without Items for SQ.
    ///
    /// - Parameters:
    ///   - tag: its tag.
    ///   - vr: its VR; the dictionary's when nil, UN for a tag it does not know.
    ///   - item: the Item it is meant for, or nil for the top level.
    public func makeElement(tag: DataTag, vr: VR.VR? = nil, in item: DataItem? = nil) throws -> DataElement {
        try Self.checkAddable(tag)
        let resolved = vr ?? DicomSpec.shared.vrForTag(withCode: tag.code.lowercased()) ?? .UN
        let element: DataElement = resolved == .SQ
            ? DataSequence(withTag: tag, dataset: self, parent: item)
            : DataElement(withTag: tag, dataset: self, parent: item)
        element.vr = resolved
        element.vrMethod = vrMethod
        element.byteOrder = byteOrder
        element.data = Data()
        element.length = resolved == .SQ ? -1 : 0
        element.characterSet = item?.effectiveCharacterSet
        return element
    }

    /// Adds an element at its place in tag order, at the top level or in an Item.
    ///
    /// - Parameters:
    ///   - element: the element, made by `makeElement` or removed before.
    ///   - item: the Item that receives it, or nil for the top level.
    public func insert(_ element: DataElement, into item: DataItem? = nil) throws {
        guard !isCorrupted else { throw DataSetStructureError.corrupted }
        try Self.checkAddable(element.tag)
        let code = element.tag.code.lowercased()
        if elements(in: item).contains(where: { $0.tag.code.lowercased() == code }) {
            throw DataSetStructureError.duplicate(tag: "(\(element.group.uppercased()),\(element.element.uppercased()))")
        }
        element.dataset = self
        element.parent = item
        if let item {
            item.elements.insert(element, at: Self.position(of: code, in: item.elements))
        } else {
            datasetElements.insert(element, at: Self.position(of: code, in: datasetElements))
            allElements.insert(element, at: Self.position(of: code, in: allElements))
            if element.name == "SpecificCharacterSet" { updateCharacterSet() }
        }
    }

    /// Removes an element from where it is.
    ///
    /// - Parameter element: the element, at the top level or in an Item.
    /// - Returns: the Item that held it, nil for the top level: `insert(_:into:)` puts it back.
    @discardableResult
    public func removeElement(_ element: DataElement) throws -> DataItem? {
        guard !isCorrupted else { throw DataSetStructureError.corrupted }
        if element is DataItem { throw DataSetStructureError.itemOrDelimiter }
        if element.group.lowercased() == DicomConstants.metaInformationGroup { throw DataSetStructureError.fileMetaInformation }
        if let item = element.parent as? DataItem {
            guard let index = item.elements.firstIndex(where: { $0 === element }) else { throw DataSetStructureError.notFound }
            item.elements.remove(at: index)
            return item
        }
        guard let index = datasetElements.firstIndex(where: { $0 === element }) else { throw DataSetStructureError.notFound }
        datasetElements.remove(at: index)
        allElements.removeAll { $0 === element }
        if element.name == "SpecificCharacterSet" { updateCharacterSet() }
        return nil
    }

    /// Adds an Item to a Sequence of the data set.
    ///
    /// - Parameters:
    ///   - item: the Item, removed before; a new empty Item when nil.
    ///   - sequence: the Sequence that receives it.
    ///   - index: its position, from 0 to the count of Items.
    /// - Returns: the Item added.
    @discardableResult
    public func insertItem(_ item: DataItem? = nil, into sequence: DataSequence, at index: Int) throws -> DataItem {
        guard !isCorrupted else { throw DataSetStructureError.corrupted }
        guard (0...sequence.items.count).contains(index) else { throw DataSetStructureError.itemIndexOutOfRange(index) }
        let item = item ?? {
            let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
            item.characterSet = (sequence.parent as? DataItem)?.effectiveCharacterSet ?? characterSet
            item.vrMethod = .Implicit
            item.length = -1
            return item
        }()
        item.parent = sequence
        sequence.items.insert(item, at: index)
        return item
    }

    /// Removes an Item from its Sequence.
    ///
    /// - Parameter item: the Item.
    /// - Returns: its Sequence and position: `insertItem(_:into:at:)` puts it back.
    @discardableResult
    public func removeItem(_ item: DataItem) throws -> (sequence: DataSequence, index: Int) {
        guard !isCorrupted else { throw DataSetStructureError.corrupted }
        guard let sequence = item.parent as? DataSequence,
              let index = sequence.items.firstIndex(where: { $0 === item }) else { throw DataSetStructureError.notFound }
        sequence.items.remove(at: index)
        return (sequence, index)
    }

    /// Moves an Item within its Sequence: the order of Items is significant (PS3.5 7.5.1).
    ///
    /// - Parameters:
    ///   - sequence: the Sequence.
    ///   - source: the position of the Item.
    ///   - destination: its new position, among the Items once it is taken out.
    public func moveItem(in sequence: DataSequence, from source: Int, to destination: Int) throws {
        guard !isCorrupted else { throw DataSetStructureError.corrupted }
        guard sequence.items.indices.contains(source) else { throw DataSetStructureError.itemIndexOutOfRange(source) }
        guard sequence.items.indices.contains(destination) else { throw DataSetStructureError.itemIndexOutOfRange(destination) }
        let item = sequence.items.remove(at: source)
        sequence.items.insert(item, at: destination)
    }

    /// Where an element with this tag code goes, the elements in ascending tag order (PS3.5 7.1).
    private static func position(of code: String, in elements: [DataElement]) -> Int {
        elements.firstIndex { $0.tag.code.lowercased() > code } ?? elements.count
    }
}
