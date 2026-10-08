//
//  DcmSeg.swift
//
//  Prints Segmentations and Parametric Maps, and makes binary Segmentations.
//

import ArgumentParser
import DcmSwift
import Foundation

@main
struct DcmSeg: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print Segmentations and Parametric Maps, or make a binary Segmentation.",
        subcommands: [Show.self, Make.self], defaultSubcommand: Show.self)

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print the segments and frames of a Segmentation, or a Parametric Map.")

        @Argument(help: "DICOM file")
        var path: String

        @Flag(help: "Print JSON, with every frame's mask or values")
        var json = false

        mutating func run() throws {
            guard let file = DicomFile(forPath: path), let dataSet = file.dataset else {
                throw ValidationError("cannot read \(path) as DICOM")
            }
            if let segmentation = DICOMSegmentation(dataSet: dataSet) {
                if json {
                    let object: [String: Any] = [
                        "type": segmentation.type.rawValue, "rows": segmentation.rows, "columns": segmentation.columns,
                        "segments": segmentation.segments.map { ["number": $0.number, "label": $0.label,
                                                                 "type": $0.type?.value ?? "", "algorithmType": $0.algorithmType] },
                        "frames": try segmentation.frames.indices.map { index -> [String: Any] in
                            let frame = segmentation.frames[index]
                            return ["segment": frame.segmentNumber ?? 0, "position": frame.position,
                                    "sources": frame.sourceImages.map(\.sopInstanceUID),
                                    "mask": try segmentation.mask(frame: index)]
                        },
                    ]
                    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: object))
                    return
                }
                print("\(segmentation.type.rawValue) Segmentation, \(segmentation.columns) x \(segmentation.rows), "
                      + "\(segmentation.frames.count) frames")
                for segment in segmentation.segments {
                    let count = segmentation.frames.filter { $0.segmentNumber == segment.number }.count
                    print("  \(segment.number). \(segment.label): \(segment.type?.meaning ?? ""), \(segment.algorithmType), \(count) frames")
                }
            } else if let map = DICOMParametricMap(dataSet: dataSet) {
                if json {
                    let object: [String: Any] = [
                        "rows": map.rows, "columns": map.columns,
                        "frames": try (0..<map.frameCount).map { ["values": try map.values(frame: $0),
                                                                    "units": map.mapping(frame: $0)?.units?.value ?? ""] },
                    ]
                    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: object))
                    return
                }
                let mapping = map.mapping(frame: 0)
                print("Parametric Map, \(map.columns) x \(map.rows), \(map.frameCount) frames, "
                      + "\(mapping?.label ?? "") in \(mapping?.units?.meaning ?? "-")")
            } else {
                throw ValidationError("\(path) is neither a Segmentation nor a Parametric Map")
            }
        }
    }

    struct Make: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Make a binary Segmentation of boxes on source images.")

        @Option(name: .customLong("source"), help: "A single-frame source image; repeatable, in order")
        var sources: [String] = []

        @Option(name: .customLong("box"), help: "A segment: label:x0,y0,x1,y1:first,last, a box of columns x0..<x1 and rows y0..<y1 on the source images first...last (from 0); repeatable")
        var boxes: [String] = []

        @Option(name: .shortAndLong, help: "Segmentation file to write")
        var output: String

        mutating func run() throws {
            let images = try sources.map { path -> DataSet in
                guard let file = DicomFile(forPath: path), let dataSet = file.dataset else {
                    throw ValidationError("cannot read \(path) as DICOM")
                }
                return dataSet
            }
            guard let first = images.first else { throw ValidationError("give --source images") }
            let rows = Int(first.element(forTagName: "Rows")?.uint16Values?.first ?? 0)
            let columns = Int(first.element(forTagName: "Columns")?.uint16Values?.first ?? 0)
            var segments: [DICOMSegmentation.SegmentDescription] = []
            var masks: [[[Bool]?]] = []
            for box in boxes {
                let parts = box.split(separator: ":")
                let corners = parts.count == 3 ? parts[1].split(separator: ",").compactMap { Int($0) } : []
                let range = parts.count == 3 ? parts[2].split(separator: ",").compactMap { Int($0) } : []
                guard corners.count == 4, range.count == 2 else { throw ValidationError("--box expects label:x0,y0,x1,y1:first,last") }
                segments.append(.init(label: String(parts[0]),
                                      category: DICOMCode("85756007", scheme: "SCT", meaning: "Tissue"),
                                      type: DICOMCode("85756007", scheme: "SCT", meaning: "Tissue")))
                masks.append(images.indices.map { image -> [Bool]? in
                    guard (range[0]...range[1]).contains(image) else { return nil }
                    return (0..<(rows * columns)).map { pixel in
                        let (row, column) = (pixel / columns, pixel % columns)
                        return (corners[0]..<corners[2]).contains(column) && (corners[1]..<corners[3]).contains(row)
                    }
                })
            }
            let dataSet = try DICOMSegmentation.binary(sources: images, segments: segments, masks: masks)
            try dataSet.writePart10(to: URL(fileURLWithPath: output))
        }
    }
}
