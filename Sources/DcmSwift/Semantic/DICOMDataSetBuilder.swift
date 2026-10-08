import Foundation

/// Builds the attributes of a new instance, Sequences and Items included.
final class DICOMDataSetBuilder {
    let dataSet = DataSet()

    /// Sets an attribute of the data set, or of an Item.
    func set(_ name: String, _ value: Any, vr: VR.VR? = nil, in item: DataItem? = nil) {
        guard let element = DataElement(withTagName: name, dataset: dataSet, parent: item) else { return }
        if let vr { element.vr = vr }
        if let data = value as? Data {
            element.data = data
            element.length = data.count
        } else if let values = value as? [String] {
            _ = element.setTextValues(values)
        } else if let number = value as? UInt16 {
            element.data = Data([UInt8(number & 0xFF), UInt8(number >> 8)])
            element.length = 2
        } else if let number = value as? UInt32 {
            element.data = Data((0..<4).map { UInt8(truncatingIfNeeded: number >> UInt32($0 * 8)) })
            element.length = 4
        } else if let tags = value as? [DataTag] {
            _ = element.setValue(tags)
        } else {
            _ = element.setValue(value)
        }
        if let item { item.elements.append(element) } else { dataSet.add(element: element) }
    }

    /// Adds a Sequence with one Item per closure.
    @discardableResult
    func sequence(_ name: String, in parent: DataItem? = nil, items: [(DataItem) -> Void]) -> DataSequence? {
        guard let tag = DicomSpec.shared.dataTag(forName: name) else { return nil }
        let sequence = DataSequence(withTag: tag, parent: parent)
        sequence.vr = .SQ
        sequence.length = -1
        sequence.dataset = dataSet
        for fill in items {
            let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
            item.length = -1
            sequence.items.append(item)
            fill(item)
            item.elements.sort { $0.tagCode() < $1.tagCode() }
        }
        if let parent { parent.elements.append(sequence) } else { dataSet.add(element: sequence) }
        return sequence
    }

    /// A Code Sequence Macro Item.
    func code(_ name: String, _ code: DICOMCode, in parent: DataItem? = nil) {
        sequence(name, in: parent, items: [{ item in
            self.set("CodeValue", code.value, in: item)
            self.set("CodingSchemeDesignator", code.scheme, in: item)
            self.set("CodeMeaning", code.meaning, in: item)
        }])
    }

    /// Copies attributes of a source data set when it has them.
    func copy(_ names: [String], from source: DataSet, empty: Bool = true) {
        for name in names {
            if let element = source.element(forTagName: name), let value = element.textValues {
                set(name, value.count == 1 ? value[0] as Any : value as Any)
            } else if empty {
                set(name, "")
            }
        }
    }

    func finish() -> DataSet {
        dataSet.sortElements()
        return dataSet
    }

    static func newUID() -> String { DICOMEncapsulatedDocument.newUID() }

    static func dateAndTime(_ date: Date = Date()) -> (date: String, time: String) {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: TimeZone.current, from: date)
        return (String(format: "%04d%02d%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1),
                String(format: "%02d%02d%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0))
    }
}

extension DICOMSegmentation {
    /// The description of a segment to make.
    public struct SegmentDescription: Sendable {
        public var label: String
        public var category: DICOMCode
        public var type: DICOMCode
        /// AUTOMATIC, SEMIAUTOMATIC, or MANUAL.
        public var algorithmType: String
        /// Required unless the algorithm type is MANUAL.
        public var algorithmName: String?

        public init(label: String, category: DICOMCode, type: DICOMCode, algorithmType: String = "MANUAL",
                    algorithmName: String? = nil) {
            self.label = label
            self.category = category
            self.type = type
            self.algorithmType = algorithmType
            self.algorithmName = algorithmName
        }
    }

    public struct MakingError: Error, CustomStringConvertible {
        public let description: String
    }

    /// A BINARY Segmentation of single-frame source images of one series
    /// and geometry. `masks[segment][image]` is the mask of a segment on a
    /// source image, row by row, or nil when the segment is absent there;
    /// segments are numbered from 1 in the order given. Frames are ordered
    /// by segment, then by image.
    public static func binary(
        sources: [DataSet], segments: [SegmentDescription], masks: [[[Bool]?]],
        seriesNumber: Int = 1, instanceNumber: Int = 1, contentLabel: String = "SEGMENTATION"
    ) throws -> DataSet {
        guard let first = sources.first else { throw MakingError(description: "no source image") }
        let rows = first.element(forTagName: "Rows")?.decodedNumbers.first.map { Int($0) } ?? 0
        let columns = first.element(forTagName: "Columns")?.decodedNumbers.first.map { Int($0) } ?? 0
        guard rows > 0, columns > 0, masks.count == segments.count,
              masks.allSatisfy({ $0.count == sources.count && $0.allSatisfy { $0 == nil || $0!.count == rows * columns } })
        else { throw MakingError(description: "one mask of \(rows) x \(columns) per segment and source image is needed") }
        let builder = DICOMDataSetBuilder()
        let (day, time) = DICOMDataSetBuilder.dateAndTime()
        let sopInstance = DICOMDataSetBuilder.newUID()
        builder.set("SOPClassUID", "1.2.840.10008.5.1.4.1.1.66.4")
        builder.set("SOPInstanceUID", sopInstance)
        // Patient, General Study, Frame of Reference.
        builder.copy(["PatientName", "PatientID", "PatientBirthDate", "PatientSex", "StudyInstanceUID", "StudyDate",
                      "StudyTime", "ReferringPhysicianName", "StudyID", "AccessionNumber"], from: first)
        builder.copy(["SpecificCharacterSet", "FrameOfReferenceUID"], from: first, empty: false)
        builder.set("PositionReferenceIndicator", "")
        // General Series and Segmentation Series.
        builder.set("Modality", "SEG")
        builder.set("SeriesInstanceUID", DICOMDataSetBuilder.newUID())
        builder.set("SeriesNumber", String(seriesNumber))
        // General and Enhanced General Equipment.
        builder.set("Manufacturer", "DcmSwift")
        builder.set("ManufacturerModelName", "DcmSwift")
        builder.set("DeviceSerialNumber", "0")
        builder.set("SoftwareVersions", DICOMImplementation.versionName)
        // General Image and Segmentation Image.
        builder.set("InstanceNumber", String(instanceNumber))
        builder.set("ContentDate", day)
        builder.set("ContentTime", time)
        builder.set("ImageType", ["DERIVED", "PRIMARY"])
        builder.set("ContentLabel", contentLabel)
        builder.set("ContentDescription", "")
        builder.set("ContentCreatorName", "")
        builder.set("SegmentationType", "BINARY")
        builder.set("LossyImageCompression", "00")
        builder.sequence("SegmentSequence", items: segments.enumerated().map { index, segment in
            { item in
                builder.set("SegmentNumber", UInt16(index + 1), vr: .US, in: item)
                builder.set("SegmentLabel", segment.label, in: item)
                builder.set("SegmentAlgorithmType", segment.algorithmType, in: item)
                if let name = segment.algorithmName { builder.set("SegmentAlgorithmName", name, in: item) }
                builder.code("SegmentedPropertyCategoryCodeSequence", segment.category, in: item)
                builder.code("SegmentedPropertyTypeCodeSequence", segment.type, in: item)
            }
        })
        // Image Pixel: one bit per pixel.
        builder.set("SamplesPerPixel", UInt16(1), vr: .US)
        builder.set("PhotometricInterpretation", "MONOCHROME2")
        builder.set("Rows", UInt16(rows), vr: .US)
        builder.set("Columns", UInt16(columns), vr: .US)
        builder.set("BitsAllocated", UInt16(1), vr: .US)
        builder.set("BitsStored", UInt16(1), vr: .US)
        builder.set("HighBit", UInt16(0), vr: .US)
        builder.set("PixelRepresentation", UInt16(0), vr: .US)

        // Frames: one per segment present on a source image.
        var frames: [(segment: Int, image: Int)] = []
        for (segment, perImage) in masks.enumerated() {
            for (image, mask) in perImage.enumerated() where mask != nil { frames.append((segment, image)) }
        }
        guard !frames.isEmpty else { throw MakingError(description: "every mask is absent") }
        builder.set("NumberOfFrames", String(frames.count))
        // Multi-frame Dimension: segment, then position.
        let organization = DICOMDataSetBuilder.newUID()
        builder.sequence("DimensionOrganizationSequence", items: [{ builder.set("DimensionOrganizationUID", organization, in: $0) }])
        builder.sequence("DimensionIndexSequence", items: [("0062000B", "0062000A"), ("00200032", "00209113")].map { pointer, group in
            { item in
                builder.set("DimensionOrganizationUID", organization, in: item)
                builder.set("DimensionIndexPointer", [DataTag(withGroup: String(pointer.prefix(4)), element: String(pointer.suffix(4)))],
                            vr: .AT, in: item)
                builder.set("FunctionalGroupPointer", [DataTag(withGroup: String(group.prefix(4)), element: String(group.suffix(4)))],
                            vr: .AT, in: item)
            }
        })
        // Shared Functional Groups: geometry of the sources.
        builder.sequence("SharedFunctionalGroupsSequence", items: [{ shared in
            builder.sequence("PixelMeasuresSequence", in: shared, items: [{ item in
                builder.set("PixelSpacing", first.element(forTagName: "PixelSpacing")?.textValues ?? ["1", "1"], in: item)
                builder.set("SliceThickness", first.element(forTagName: "SliceThickness")?.textValues?.first ?? "1", in: item)
            }])
            builder.sequence("PlaneOrientationSequence", in: shared, items: [{ item in
                builder.set("ImageOrientationPatient", first.element(forTagName: "ImageOrientationPatient")?.textValues
                    ?? ["1", "0", "0", "0", "1", "0"], in: item)
            }])
        }])
        // Positions, for the dimension index of each frame.
        let positions = sources.map { $0.element(forTagName: "ImagePositionPatient")?.textValues ?? ["0", "0", "0"] }
        let distinct = Array(Set(positions.map { $0.joined(separator: "\\") })).sorted {
            let a = $0.split(separator: "\\").last.flatMap { Double($0) } ?? 0
            let b = $1.split(separator: "\\").last.flatMap { Double($0) } ?? 0
            return a < b
        }
        builder.sequence("PerFrameFunctionalGroupsSequence", items: frames.map { frame in
            { group in
                let source = sources[frame.image]
                builder.sequence("DerivationImageSequence", in: group, items: [{ derivation in
                    builder.code("DerivationCodeSequence", DICOMCode("113076", scheme: "DCM", meaning: "Segmentation"), in: derivation)
                    builder.sequence("SourceImageSequence", in: derivation, items: [{ reference in
                        builder.set("ReferencedSOPClassUID", source.string(forTag: "SOPClassUID") ?? "", in: reference)
                        builder.set("ReferencedSOPInstanceUID", source.string(forTag: "SOPInstanceUID") ?? "", in: reference)
                        builder.code("PurposeOfReferenceCodeSequence", DICOMCode(
                            "121322", scheme: "DCM", meaning: "Source image for image processing operation"), in: reference)
                        // The mask has the pixels of the source image.
                        builder.set("SpatialLocationsPreserved", "YES", in: reference)
                    }])
                }])
                builder.sequence("FrameContentSequence", in: group, items: [{ content in
                    let position = (distinct.firstIndex(of: positions[frame.image].joined(separator: "\\")) ?? 0) + 1
                    builder.set("DimensionIndexValues", Data((0..<2).flatMap { index -> [UInt8] in
                        let value = UInt32(index == 0 ? frame.segment + 1 : position)
                        return (0..<4).map { UInt8(truncatingIfNeeded: value >> UInt32($0 * 8)) }
                    }), vr: .UL, in: content)
                }])
                builder.sequence("PlanePositionSequence", in: group, items: [{ item in
                    builder.set("ImagePositionPatient", positions[frame.image], in: item)
                }])
                builder.sequence("SegmentIdentificationSequence", in: group, items: [{ item in
                    builder.set("ReferencedSegmentNumber", UInt16(frame.segment + 1), vr: .US, in: item)
                }])
            }
        })
        // Common Instance Reference: the source series.
        builder.sequence("ReferencedSeriesSequence", items: [{ series in
            builder.set("SeriesInstanceUID", first.string(forTag: "SeriesInstanceUID") ?? "", in: series)
            builder.sequence("ReferencedInstanceSequence", in: series, items: sources.map { source in
                { reference in
                    builder.set("ReferencedSOPClassUID", source.string(forTag: "SOPClassUID") ?? "", in: reference)
                    builder.set("ReferencedSOPInstanceUID", source.string(forTag: "SOPInstanceUID") ?? "", in: reference)
                }
            })
        }])
        // Pixel Data: bits packed least significant first across frames.
        let size = rows * columns
        var bytes = [UInt8](repeating: 0, count: (frames.count * size + 7) / 8)
        for (index, frame) in frames.enumerated() {
            for (pixel, set) in masks[frame.segment][frame.image]!.enumerated() where set {
                let bit = index * size + pixel
                bytes[bit >> 3] |= 1 << UInt8(bit & 7)
            }
        }
        if bytes.count % 2 == 1 { bytes.append(0) }
        builder.set("PixelData", Data(bytes), vr: .OB)
        return builder.finish()
    }
}
