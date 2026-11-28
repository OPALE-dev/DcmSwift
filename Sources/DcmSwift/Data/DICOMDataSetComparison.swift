//
//  DICOMDataSetComparison.swift
//  DcmSwift
//
//  The differences between two Data Sets, attribute by attribute, Sequence
//  Items included (PS3.5 7.1, 7.5).
//

import Foundation

/// A difference between two Data Sets: an attribute or an Item present in
/// one only, or an attribute whose VR or Value differs.
public struct DICOMDataSetDifference: Sendable, Equatable {
    /// One step of the way to an attribute: a tag, and, for a Sequence, the
    /// index of the Item the next step is in.
    public struct Step: Sendable, Hashable, CustomStringConvertible {
        /// Group and element, as eight upper-case hexadecimal digits.
        public let tag: String
        /// The zero-based index of an Item of this Sequence.
        public let item: Int?

        public init(tag: String, item: Int? = nil) {
            self.tag = tag
            self.item = item
        }

        /// (gggg,eeee), followed by [n] for an Item.
        public var description: String {
            let tag = self.tag.count == 8 ? "(\(self.tag.prefix(4)),\(self.tag.suffix(4)))" : self.tag
            return item.map { "\(tag)[\($0)]" } ?? tag
        }
    }

    /// What a side holds at the location.
    public enum Value: Sendable, Equatable {
        /// Character string Values, decoded with the Specific Character Set.
        case text([String])
        /// Other Values, in Little Endian whatever the Transfer Syntax.
        case bytes(Data)
        /// A Sequence and its number of Items.
        case sequence(items: Int)
        /// A Sequence Item and its number of attributes.
        case item(attributes: Int)
    }

    /// One side of the difference.
    public struct Side: Sendable, Equatable {
        /// The VR, as its two letters; empty for an Item.
        public let vr: String
        /// The length of the Value Field as read; -1 for an undefined length.
        public let length: Int
        public let value: Value
    }

    public enum Kind: Sendable, Equatable {
        /// In the second Data Set only.
        case added
        /// In the first Data Set only.
        case removed
        /// In both, with another VR, another Value, or both.
        case changed(vr: Bool, value: Bool)
    }

    /// The way from a top-level attribute; an Item added or removed ends
    /// with its Sequence and the Item's index.
    public let path: [Step]
    public let kind: Kind
    /// The first Data Set's side; nil when added.
    public let left: Side?
    /// The second Data Set's side; nil when removed.
    public let right: Side?
}


/// Compares Data Sets (PS3.5 7.1, 7.5).
///
/// Attributes are paired by tag at each level, the File Meta Information
/// included unless left out; an attribute repeated at one level, which a
/// conformant Data Set does not have, is paired by its occurrence. The
/// Items of two Sequences are compared by position. Character strings are
/// compared as decoded with the Specific Character Set, other Values as
/// Little Endian bytes, so that a Data Set compares equal to itself in
/// another uncompressed Transfer Syntax. Encapsulated Pixel Data is
/// compared as its bytes.
public enum DICOMDataSetComparison {
    /// The differences from `left` to `right`, in the order of the tags.
    ///
    /// - Parameters:
    ///   - left: The first Data Set.
    ///   - right: The second Data Set.
    ///   - includesMetaInformation: Whether group 0002 is compared.
    public static func differences(from left: DataSet, to right: DataSet,
                                   includesMetaInformation: Bool = true) -> [DICOMDataSetDifference] {
        let meta = includesMetaInformation
            ? compare(left.metaInformationHeaderElements, right.metaInformationHeaderElements, path: []) : []
        return meta + compare(left.datasetElements, right.datasetElements, path: [])
    }

    private static func compare(_ left: [DataElement], _ right: [DataElement],
                                path: [DICOMDataSetDifference.Step]) -> [DICOMDataSetDifference] {
        var differences: [DICOMDataSetDifference] = []
        let leftGroups = grouped(left), rightGroups = grouped(right)
        let tags = Set(leftGroups.keys).union(rightGroups.keys).sorted()
        for tag in tags {
            let lefts = leftGroups[tag] ?? [], rights = rightGroups[tag] ?? []
            for index in 0..<max(lefts.count, rights.count) {
                let step = DICOMDataSetDifference.Step(tag: tag)
                switch (index < lefts.count ? lefts[index] : nil, index < rights.count ? rights[index] : nil) {
                case (let a?, nil):
                    differences.append(.init(path: path + [step], kind: .removed, left: side(a), right: nil))
                case (nil, let b?):
                    differences.append(.init(path: path + [step], kind: .added, left: nil, right: side(b)))
                case (let a?, let b?):
                    differences += compare(a, b, path: path, step: step)
                case (nil, nil):
                    break
                }
            }
        }
        return differences
    }

    private static func compare(_ a: DataElement, _ b: DataElement, path: [DICOMDataSetDifference.Step],
                                step: DICOMDataSetDifference.Step) -> [DICOMDataSetDifference] {
        let sameVR = a.vr == b.vr
        // Encapsulated Pixel Data is compared as its fragments, not as Items.
        let encapsulated = a is PixelSequence || b is PixelSequence
        guard !encapsulated, let first = a as? DataSequence, let second = b as? DataSequence else {
            let sameValue = (a is DataSequence) == (b is DataSequence) && value(a) == value(b)
            return sameVR && sameValue ? []
                : [.init(path: path + [step], kind: .changed(vr: !sameVR, value: !sameValue), left: side(a), right: side(b))]
        }
        var differences: [DICOMDataSetDifference] = []
        if !sameVR {
            differences.append(.init(path: path + [step], kind: .changed(vr: true, value: false), left: side(a), right: side(b)))
        }
        for index in 0..<max(first.items.count, second.items.count) {
            let itemPath = path + [DICOMDataSetDifference.Step(tag: step.tag, item: index)]
            switch (index < first.items.count ? first.items[index] : nil, index < second.items.count ? second.items[index] : nil) {
            case (let x?, nil):
                differences.append(.init(path: itemPath, kind: .removed, left: side(x), right: nil))
            case (nil, let y?):
                differences.append(.init(path: itemPath, kind: .added, left: nil, right: side(y)))
            case (let x?, let y?):
                differences += compare(x.elements, y.elements, path: itemPath)
            case (nil, nil):
                break
            }
        }
        return differences
    }

    /// The elements of a level by tag, in the order read.
    private static func grouped(_ elements: [DataElement]) -> [String: [DataElement]] {
        Dictionary(grouping: elements) { $0.tagCode().uppercased() }
    }

    static func value(_ element: DataElement) -> DICOMDataSetDifference.Value {
        if let pixels = element as? PixelSequence {
            return .bytes(pixels.items.reduce(into: Data()) { $0 += $1.data ?? Data() })
        }
        if let item = element as? DataItem { return .item(attributes: item.elements.count) }
        if let sequence = element as? DataSequence { return .sequence(items: sequence.items.count) }
        if let text = element.textValues { return .text(text) }
        return .bytes(element.length > 0 ? element.encodedValueData(byteOrder: .LittleEndian) : Data())
    }

    static func side(_ element: DataElement) -> DICOMDataSetDifference.Side {
        .init(vr: element is DataItem ? "" : "\(element.vr)", length: element.length, value: value(element))
    }
}
