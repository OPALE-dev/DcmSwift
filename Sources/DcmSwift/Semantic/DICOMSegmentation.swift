import Foundation

/// The Functional Groups of a frame: its Per-Frame Item, then the Shared one.
struct DICOMFrameGroups {
    let shared: DataItem?
    let perFrame: [DataItem]

    init(_ dataSet: DataSet) {
        shared = (dataSet.element(forTagName: "SharedFunctionalGroupsSequence") as? DataSequence)?.items.first
        perFrame = (dataSet.element(forTagName: "PerFrameFunctionalGroupsSequence") as? DataSequence)?.items ?? []
    }

    /// The first Item of a Functional Group Sequence for a frame.
    func group(_ name: String, frame: Int) -> DataItem? {
        if frame < perFrame.count, let item = (perFrame[frame].element(withName: name) as? DataSequence)?.items.first {
            return item
        }
        return (shared?.element(withName: name) as? DataSequence)?.items.first
    }
}

/// A Segmentation (PS3.3 A.51, C.8.20): segments and, per frame, the
/// segment and the source images it covers.
public struct DICOMSegmentation: Sendable {
    public enum SegmentationType: String, Sendable {
        case binary = "BINARY", fractional = "FRACTIONAL", labelMap = "LABELMAP"
    }

    public struct Segment: Sendable {
        /// Segment Number (0062,0004), from 1.
        public let number: Int
        public let label: String
        public let description: String?
        /// Segmented Property Category Code Sequence (0062,0003).
        public let category: DICOMCode?
        /// Segmented Property Type Code Sequence (0062,000F).
        public let type: DICOMCode?
        /// Segment Algorithm Type (0062,0008): AUTOMATIC, SEMIAUTOMATIC, MANUAL.
        public let algorithmType: String
        public let algorithmName: String?
        /// Recommended Display CIELab Value (0062,000D), as stored.
        public let displayColor: [Int]?
    }

    public struct SourceImage: Sendable, Equatable {
        public let sopClassUID: String
        public let sopInstanceUID: String
        public let frames: [Int]
    }

    public struct Frame: Sendable {
        /// The segment of the frame; nil for a LABELMAP.
        public let segmentNumber: Int?
        public let sourceImages: [SourceImage]
        /// Image Position (Patient) of the Plane Position Sequence.
        public let position: [Double]
    }

    public let type: SegmentationType
    /// Maximum Fractional Value (0062,000E) of a FRACTIONAL segmentation.
    public let maximumFractionalValue: Int?
    /// Segmentation Fractional Type (0062,0010): PROBABILITY or OCCUPANCY.
    public let fractionalType: String?
    public let rows: Int
    public let columns: Int
    public let segments: [Segment]
    public let frames: [Frame]
    private let dataSet: DataSet

    public init?(dataSet: DataSet) {
        guard ["1.2.840.10008.5.1.4.1.1.66.4", "1.2.840.10008.5.1.4.1.1.66.7"].contains(dataSet.string(forTag: "SOPClassUID") ?? ""),
              let type = (dataSet.element(forTagName: "SegmentationType")?.decodedTexts?.first).flatMap(SegmentationType.init)
        else { return nil }
        self.dataSet = dataSet
        self.type = type
        maximumFractionalValue = dataSet.element(forTagName: "MaximumFractionalValue")?.decodedNumbers.first.map { Int($0) }
        fractionalType = dataSet.element(forTagName: "SegmentationFractionalType")?.decodedTexts?.first
        rows = dataSet.element(forTagName: "Rows")?.decodedNumbers.first.map { Int($0) } ?? 0
        columns = dataSet.element(forTagName: "Columns")?.decodedNumbers.first.map { Int($0) } ?? 0
        segments = ((dataSet.element(forTagName: "SegmentSequence") as? DataSequence)?.items ?? []).compactMap { item in
            func text(_ name: String) -> String? { item.element(withName: name)?.decodedTexts?.first }
            func code(_ name: String) -> DICOMCode? {
                (item.element(withName: name) as? DataSequence)?.items.first.flatMap(DICOMCode.init(item:))
            }
            guard let number = item.element(withName: "SegmentNumber")?.decodedNumbers.first else { return nil }
            let color = item.element(withName: "RecommendedDisplayCIELabValue")?.decodedNumbers.map { Int($0) }
            return Segment(number: Int(number), label: text("SegmentLabel") ?? "", description: text("SegmentDescription"),
                           category: code("SegmentedPropertyCategoryCodeSequence"),
                           type: code("SegmentedPropertyTypeCodeSequence"), algorithmType: text("SegmentAlgorithmType") ?? "",
                           algorithmName: text("SegmentAlgorithmName"), displayColor: color)
        }
        let count = dataSet.element(forTagName: "NumberOfFrames")?.decodedNumbers.first.map { Int($0) } ?? 1
        let groups = DICOMFrameGroups(dataSet)
        frames = (0..<count).map { index in
            let segment = groups.group("SegmentIdentificationSequence", frame: index)?
                .element(withName: "ReferencedSegmentNumber")?.decodedNumbers.first.map { Int($0) }
            var sources: [SourceImage] = []
            for derivation in (groups.perFrame.indices.contains(index)
                ? (groups.perFrame[index].element(withName: "DerivationImageSequence") as? DataSequence)?.items : nil)
                ?? ((groups.shared?.element(withName: "DerivationImageSequence") as? DataSequence)?.items ?? []) {
                for source in (derivation.element(withName: "SourceImageSequence") as? DataSequence)?.items ?? [] {
                    sources.append(SourceImage(
                        sopClassUID: source.element(withName: "ReferencedSOPClassUID")?.decodedTexts?.first ?? "",
                        sopInstanceUID: source.element(withName: "ReferencedSOPInstanceUID")?.decodedTexts?.first ?? "",
                        frames: source.element(withName: "ReferencedFrameNumber")?.decodedNumbers.map { Int($0) } ?? []))
                }
            }
            let position = groups.group("PlanePositionSequence", frame: index)?
                .element(withName: "ImagePositionPatient")?.decodedNumbers ?? []
            return Frame(segmentNumber: type == .labelMap ? nil : segment, sourceImages: sources, position: position)
        }
    }

    /// The mask of a frame, row by row: 0 or 1 for BINARY, 0 to Maximum
    /// Fractional Value for FRACTIONAL, segment numbers for LABELMAP.
    public func mask(frame: Int) throws -> [Int] {
        let size = rows * columns
        // Native Pixel Data, whatever class the parser gave the element.
        let native = [TransferSyntax.implicitVRLittleEndian, TransferSyntax.explicitVRLittleEndian,
                      TransferSyntax.explicitVRBigEndian, "1.2.840.10008.1.2.1.99"]
            .contains(dataSet.transferSyntax?.tsUID ?? TransferSyntax.explicitVRLittleEndian)
        if type == .binary, native, let pixels = dataSet.element(forTagName: "PixelData"),
           let data = (pixels as? DataSequence)?.items.first?.data ?? pixels.data {
            // Bits are packed, least significant first, across frames.
            let start = frame * size
            guard (start + size + 7) / 8 <= data.count else {
                throw DICOMPixelDataError.truncatedPixelData(expectedBytes: (start + size + 7) / 8, actualBytes: data.count)
            }
            return data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                (start..<(start + size)).map { Int(bytes[$0 >> 3] >> UInt8($0 & 7) & 1) }
            }
        }
        return try DICOMImageRenderer(dataset: dataSet).storedValues(frame: frame).map { Int($0) }
    }
}

/// A Parametric Map (PS3.3 A.75): real-world values per frame, from float,
/// double, or integer pixels and the Real World Value Mapping.
public struct DICOMParametricMap: Sendable {
    public struct Mapping: Sendable {
        /// LUT Label (0040,9210).
        public let label: String?
        /// Measurement Units Code Sequence (0040,08EA).
        public let units: DICOMCode?
        /// Real World Value Slope and Intercept (0040,9225), (0040,9224).
        public let slope: Double
        public let intercept: Double
    }

    public let rows: Int
    public let columns: Int
    public let frameCount: Int
    private let dataSet: DataSet
    private let groups: DICOMFrameGroups

    public init?(dataSet: DataSet) {
        guard dataSet.string(forTag: "SOPClassUID") == "1.2.840.10008.5.1.4.1.1.30" else { return nil }
        self.dataSet = dataSet
        groups = DICOMFrameGroups(dataSet)
        rows = dataSet.element(forTagName: "Rows")?.decodedNumbers.first.map { Int($0) } ?? 0
        columns = dataSet.element(forTagName: "Columns")?.decodedNumbers.first.map { Int($0) } ?? 0
        frameCount = dataSet.element(forTagName: "NumberOfFrames")?.decodedNumbers.first.map { Int($0) } ?? 1
    }

    /// The Real World Value Mapping of a frame.
    public func mapping(frame: Int) -> Mapping? {
        guard let item = groups.group("RealWorldValueMappingSequence", frame: frame) else { return nil }
        return Mapping(label: item.element(withName: "LUTLabel")?.decodedTexts?.first,
                       units: (item.element(withName: "MeasurementUnitsCodeSequence") as? DataSequence)?.items.first
                           .flatMap(DICOMCode.init(item:)),
                       slope: item.element(withName: "RealWorldValueSlope")?.decodedNumbers.first ?? 1,
                       intercept: item.element(withName: "RealWorldValueIntercept")?.decodedNumbers.first ?? 0)
    }

    /// The real-world values of a frame, row by row: Float Pixel Data and
    /// Double Float Pixel Data as stored, mapped by slope and intercept;
    /// integer Pixel Data the same way.
    public func values(frame: Int) throws -> [Double] {
        let size = rows * columns
        let mapping = self.mapping(frame: frame)
        let slope = mapping?.slope ?? 1, intercept = mapping?.intercept ?? 0
        for (name, width) in [("FloatPixelData", 4), ("DoubleFloatPixelData", 8)] {
            guard let element = dataSet.element(forTagName: name), let data = element.data else { continue }
            let start = frame * size * width
            guard start + size * width <= data.count else {
                throw DICOMPixelDataError.truncatedPixelData(expectedBytes: start + size * width, actualBytes: data.count)
            }
            let bigEndian = element.byteOrder == .BigEndian
            return data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [Double] in
                (0..<size).map { index in
                    var raw: UInt64 = 0
                    for byte in 0..<width {
                        let offset = start + index * width + (bigEndian ? width - 1 - byte : byte)
                        raw |= UInt64(bytes[offset]) << UInt64(byte * 8)
                    }
                    let value = width == 4 ? Double(Float(bitPattern: UInt32(raw))) : Double(bitPattern: raw)
                    return value * slope + intercept
                }
            }
        }
        return try DICOMImageRenderer(dataset: dataSet).storedValues(frame: frame).map { Double($0) * slope + intercept }
    }
}
