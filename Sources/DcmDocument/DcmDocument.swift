//
//  DcmDocument.swift
//
//  Wraps PDF, CDA, STL, OBJ, and MTL documents in DICOM, and extracts them.
//

import ArgumentParser
import DcmSwift
import Foundation

@main
struct DcmDocument: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Wrap PDF, CDA, STL, OBJ, and MTL documents in DICOM instances, or extract them.",
        subcommands: [Wrap.self, Extract.self])

    struct Wrap: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Wrap a document in an Encapsulated Document instance.")

        @Argument(help: "PDF, CDA (.xml), STL, OBJ, or MTL file")
        var document: String

        @Argument(help: "DICOM file to write")
        var output: String

        @Option(help: "Document Title")
        var title: String?

        @Option(help: "A DICOM file of the same patient and study, whose attributes are copied")
        var context: String?

        mutating func run() throws {
            let url = URL(fileURLWithPath: document)
            guard let kind = DICOMEncapsulatedDocument.Kind(pathExtension: url.pathExtension) else {
                throw ValidationError("unknown document type .\(url.pathExtension)")
            }
            let content = try Data(contentsOf: url)
            if kind == .stl, DICOMEncapsulatedDocument.isASCIISTL(content) {
                throw ValidationError("\(document) is an ASCII STL file; DICOM holds binary STL only")
            }
            var contextDataSet: DataSet?
            if let context {
                guard let file = DicomFile(forPath: context), let dataSet = file.dataset else {
                    throw ValidationError("cannot read \(context) as DICOM")
                }
                contextDataSet = dataSet
            }
            let wrapped = DICOMEncapsulatedDocument(
                kind: kind, document: content, title: title ?? url.deletingPathExtension().lastPathComponent)
            let dataSet = wrapped.dataSet(context: contextDataSet)
            try dataSet.writePart10(to: URL(fileURLWithPath: output))
        }
    }

    struct Extract: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Extract the document of an Encapsulated Document instance.")

        @Argument(help: "DICOM file")
        var input: String

        @Argument(help: "File to write the document to")
        var output: String

        mutating func run() throws {
            guard let file = DicomFile(forPath: input), let dataSet = file.dataset,
                  let document = DICOMEncapsulatedDocument(dataSet: dataSet) else {
                throw ValidationError("\(input) is not an Encapsulated Document instance")
            }
            try document.document.write(to: URL(fileURLWithPath: output))
            print("\(document.kind.mimeType): \(document.document.count) bytes, \(document.title)")
        }
    }
}
