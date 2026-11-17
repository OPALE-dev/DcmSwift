//
//  main.swift
//  DcmIzer
//
//  Created by Rafael Warnault on 31/01/2022.
//

import Foundation
import DcmSwift
import ArgumentParser

#if canImport(AppKit)
import AppKit
#endif


extension Data {
    var bytes: [UInt8] {
        [UInt8](self)
    }
}


// MARK: - Image encoding

private protocol DcmIzerImageEncoder {
    func encodeImage(atPath path: String) throws -> Data
}


private enum DcmIzerImageError: Error, CustomStringConvertible {
    case cannotOpenImage(String)
    case cannotCreateBitmap
    case cannotEncodeJPEG2000
    case unsupportedPlatform

    var description: String {
        switch self {
        case .cannotOpenImage(let path):
            return "Cannot open image at path: \(path)"
        case .cannotCreateBitmap:
            return "Cannot create bitmap representation from input image."
        case .cannotEncodeJPEG2000:
            return "Cannot encode input image as JPEG 2000."
        case .unsupportedPlatform:
            return """
            Image conversion is not available on this platform yet.
            The current implementation uses AppKit on macOS.
            A Linux backend (for example libvips, ImageMagick, OpenJPEG or another native image library)
            can be plugged into DcmIzerImageEncoder later.
            """
        }
    }
}


#if canImport(AppKit)

private struct AppleImageEncoder: DcmIzerImageEncoder {
    func encodeImage(atPath path: String) throws -> Data {
        guard let image = NSImage(contentsOfFile: path) else {
            throw DcmIzerImageError.cannotOpenImage(path)
        }

        guard
            let tiffRepresentation = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else {
            throw DcmIzerImageError.cannotCreateBitmap
        }

        guard let data = bitmap.representation(
            using: .jpeg2000,
            properties: [:]
        ) else {
            throw DcmIzerImageError.cannotEncodeJPEG2000
        }

        return data
    }
}

#endif


private struct UnsupportedImageEncoder: DcmIzerImageEncoder {
    func encodeImage(atPath path: String) throws -> Data {
        throw DcmIzerImageError.unsupportedPlatform
    }
}


private func makeImageEncoder() -> any DcmIzerImageEncoder {
#if canImport(AppKit)
    return AppleImageEncoder()
#else
    return UnsupportedImageEncoder()
#endif
}


// MARK: - CLI

struct DcmIzer: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "dcmizer",
        abstract: "Convert an image to a DICOM file."
    )

    @Argument(help: "Path of JPEG/PNG/TIFF image to dicomize")
    var inputPath: String

    @Argument(help: "Path of the DICOM output file")
    var outputPath: String


    mutating func run() throws {
        let encoder = makeImageEncoder()

        let pixelData: Data

        do {
            pixelData = try encoder.encodeImage(atPath: inputPath)
        } catch {
            throw ValidationError(String(describing: error))
        }

        let dataset = DataSet()

        _ = dataset.set(
            value: 200,
            forTagName: "FileMetaInformationGroupLength"
        )

        _ = dataset.set(
            value: 0x0001,
            forTagName: "FileMetaInformationVersion"
        )

        _ = dataset.set(
            value: "1.2.840.10008.5.1.4.1.1.2",
            forTagName: "MediaStorageSOPClassUID"
        )

        _ = dataset.set(
            value: "1.2.300000.400000000.500000000000.6",
            forTagName: "MediaStorageSOPInstanceUID"
        )

        _ = dataset.set(
            value: "1.2.840.10008.1.2.1",
            forTagName: "TransferSyntaxUID"
        )

        _ = dataset.set(
            value: "John^Doe",
            forTagName: "PatientName"
        )

        _ = dataset.set(
            value: "12345678",
            forTagName: "PatientID"
        )

        _ = dataset.set(
            value: pixelData,
            forTagName: "PixelData"
        )

        dataset.hasPreamble = true

        guard let file = DicomFile(
            withDataset: dataset,
            hasPreamble: true
        ) else {
            throw ValidationError("Cannot create DICOM file.")
        }

        guard file.write(atPath: outputPath) else {
            throw ValidationError(
                "Cannot write DICOM file at path: \(outputPath)"
            )
        }
    }
}


DcmIzer.main()
