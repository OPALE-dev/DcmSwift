import Foundation

/// Encapsulated Pixel Data (PS3.5 A.4): the Fragments of each frame located
/// through the Extended Offset Table, the Basic Offset Table, or the
/// Fragment layout, and decoded by the registered codec.
public struct DICOMEncapsulatedPixelData {
    public let description: DICOMPixelDescription
    public let transferSyntaxUID: String
    private let fragments: [DataItem]
    /// The Fragment indices of each frame.
    private let frameFragments: [Range<Int>]
    /// Byte length of each frame's single Fragment, from Extended Offset
    /// Table Lengths (7FE0,0002); the Fragment may carry trailing padding.
    private let frameLengths: [Int]?

    public init(dataset: DataSet) throws {
        let description = try DICOMPixelDescription(dataset: dataset)
        let scope = DICOMAttributeScope(dataset: dataset)
        guard let sequence = scope.element("PixelData") as? DataSequence else {
            throw DICOMPixelDataError.missingPixelData
        }
        guard let offsetTable = sequence.items.first else {
            throw DICOMPixelDataError.invalidAttribute("PixelData", "missing Basic Offset Table Item")
        }
        let fragments = Array(sequence.items.dropFirst())
        guard !fragments.isEmpty else {
            throw DICOMPixelDataError.invalidAttribute("PixelData", "no Fragment")
        }
        let uid = dataset.transferSyntax?.tsUID ?? ""

        // Offsets of each Fragment's Item Tag from the first Fragment.
        var itemOffsets: [Int] = []
        var position = 0
        for fragment in fragments {
            itemOffsets.append(position)
            position += 8 + fragment.length
        }
        let fragmentIndex = Dictionary(uniqueKeysWithValues: itemOffsets.enumerated().map { ($1, $0) })
        let frames = description.numberOfFrames

        var frameLengths: [Int]?
        let frameFragments: [Range<Int>]
        let basicOffsets = Self.unsigned(offsetTable, width: 4)

        if let extended = scope.element("ExtendedOffsetTable") {
            // PS3.3 C.7.6.3.1.8: one Fragment per frame, empty Basic Offset Table.
            guard basicOffsets.isEmpty else {
                throw DICOMPixelDataError.invalidAttribute(
                    "ExtendedOffsetTable", "the Basic Offset Table must be empty")
            }
            let offsets = Self.unsigned(extended, width: 8)
            let lengths = scope.element("ExtendedOffsetTableLengths").map { Self.unsigned($0, width: 8) } ?? []
            guard offsets.count == frames, lengths.count == frames else {
                throw DICOMPixelDataError.invalidAttribute(
                    "ExtendedOffsetTable", "\(offsets.count) offsets and \(lengths.count) lengths for \(frames) frames")
            }
            frameFragments = try offsets.enumerated().map { frame, offset in
                guard let index = fragmentIndex[offset], lengths[frame] <= fragments[index].length else {
                    throw DICOMPixelDataError.invalidAttribute(
                        "ExtendedOffsetTable", "frame \(frame) does not match a Fragment")
                }
                return index..<(index + 1)
            }
            frameLengths = lengths
        } else if !basicOffsets.isEmpty {
            guard basicOffsets.count == frames, basicOffsets.first == 0,
                  zip(basicOffsets, basicOffsets.dropFirst()).allSatisfy({ $0 < $1 }) else {
                throw DICOMPixelDataError.invalidAttribute(
                    "PixelData", "Basic Offset Table does not list \(frames) increasing offsets from 0")
            }
            let starts = try basicOffsets.map { offset -> Int in
                guard let index = fragmentIndex[offset] else {
                    throw DICOMPixelDataError.invalidAttribute(
                        "PixelData", "Basic Offset Table entry \(offset) is not a Fragment Item Tag")
                }
                return index
            }
            frameFragments = zip(starts, starts.dropFirst().map { $0 } + [fragments.count]).map { $0..<$1 }
        } else if frames == 1 {
            frameFragments = [0..<fragments.count]
        } else if fragments.count == frames {
            frameFragments = (0..<frames).map { $0..<($0 + 1) }
        } else if let starts = Self.codestreamStarts(in: fragments, transferSyntaxUID: uid), starts.count == frames {
            frameFragments = zip(starts, starts.dropFirst().map { $0 } + [fragments.count]).map { $0..<$1 }
        } else {
            throw DICOMPixelDataError.invalidAttribute(
                "PixelData", "cannot locate \(frames) frames in \(fragments.count) Fragments without an offset table")
        }

        self.description = description
        self.transferSyntaxUID = uid
        self.fragments = fragments
        self.frameFragments = frameFragments
        self.frameLengths = frameLengths
    }

    /// The encoded bytes of a frame: its Fragments concatenated.
    public func encodedFrame(_ frame: Int) throws -> Data {
        guard frameFragments.indices.contains(frame) else {
            throw DICOMPixelDataError.frameOutOfRange(frame, numberOfFrames: frameFragments.count)
        }
        var data = Data()
        for index in frameFragments[frame] {
            data.append(try fragments[index].loadData())
        }
        if let frameLengths {
            data = data.prefix(frameLengths[frame])
        }
        return data
    }

    /// Decodes a frame with the decoder registered for the Transfer Syntax.
    public func decodedFrame(_ frame: Int) throws -> DICOMDecodedFrame {
        guard let decoder = DICOMCodecRegistry.decoder(for: transferSyntaxUID) else {
            throw DICOMPixelDataError.encapsulatedPixelData(transferSyntax: transferSyntaxUID)
        }
        let encoded = try encodedFrame(frame)
        return try decoder.decode(encoded, description: description.decodedFrame())
    }

    /// Fragments that begin a codestream, used when an empty Basic Offset
    /// Table leaves several Fragments per frame (PS3.5 A.4).
    private static func codestreamStarts(in fragments: [DataItem], transferSyntaxUID: String) -> [Int]? {
        let markers: [[UInt8]]
        if transferSyntaxUID.hasPrefix("1.2.840.10008.1.2.4.") {
            // JPEG and JPEG-LS SOI, JPEG 2000 SOC + SIZ.
            markers = [[0xFF, 0xD8], [0xFF, 0x4F, 0xFF, 0x51]]
        } else {
            return nil
        }
        var starts: [Int] = []
        for (index, fragment) in fragments.enumerated() {
            guard let data = try? fragment.loadData() else { return nil }
            let head = [UInt8](data.prefix(4))
            if markers.contains(where: { head.starts(with: $0) }) { starts.append(index) }
        }
        return starts.first == 0 ? starts : nil
    }

    /// Little endian unsigned values of an Item or element Value Field.
    private static func unsigned(_ element: DataElement, width: Int) -> [Int] {
        guard let data = try? element.loadData() else { return [] }
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count - width + 1, by: width).map { start in
            (0..<width).reversed().reduce(0) { $0 << 8 | Int(bytes[start + $1]) }
        }
    }
}
