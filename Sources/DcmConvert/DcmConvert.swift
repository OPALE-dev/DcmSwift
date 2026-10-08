import ArgumentParser
import DcmSwift
import Foundation

enum OutputFormat: String, CaseIterable, ExpressibleByArgument {
    case png
    case jpeg
    case tiff
    /// Netpbm: PGM for grayscale frames, PPM for RGB frames.
    case pnm

    var defaultExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .tiff: return "tiff"
        case .pnm: return "pnm"
        }
    }

    func fileExtension(for image: DICOMRenderedImage) -> String {
        guard self == .pnm else { return defaultExtension }
        return image.format == .gray8 ? "pgm" : "ppm"
    }

    func accepts(extension value: String) -> Bool {
        switch self {
        case .png: return value == "png"
        case .jpeg: return value == "jpg" || value == "jpeg"
        case .tiff: return value == "tif" || value == "tiff"
        case .pnm: return value == "pnm" || value == "pgm" || value == "ppm"
        }
    }
}

private struct ConversionSummary {
    var convertedFiles = 0
    var convertedFrames = 0
    var skippedFiles = 0
    var failures = 0
}

@main
struct DcmConvert: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dcmconvert",
        abstract: "Convert DICOM images to PNG, JPEG, TIFF, PGM, or PPM.",
        discussion: """
        INPUT may be one DICOM file or a directory. Directory conversion keeps
        the relative directory layout below OUTPUT. A multi-frame instance is
        written as one numbered image per frame.

        PNG, TIFF, PGM, and PPM are lossless 8-bit rendered exports. JPEG uses
        --quality. These rendered files do not retain the complete DICOM data
        set or replace the source DICOM instance.
        """)

    @Argument(help: "DICOM file or directory to convert.")
    var inputPath: String

    @Argument(help: "Output image path for one file, or output directory for batch/multi-frame conversion.")
    var outputPath: String

    @Option(name: .shortAndLong, help: "Output format: \(OutputFormat.allCases.map(\.rawValue).joined(separator: ", ")).")
    var format: OutputFormat

    @Option(name: .long, help: "JPEG quality from 1 to 100 (default: 90).")
    var quality = 90

    @Option(name: .long, help: "Convert only this frame, numbered from 1.")
    var frame: Int?

    @Option(name: .long, help: "Window center used for grayscale rendering; requires --window-width.")
    var windowCenter: Double?

    @Option(name: .long, help: "Window width used for grayscale rendering; requires --window-center.")
    var windowWidth: Double?

    @Flag(name: .long, help: "Use the frame's actual minimum and maximum values instead of the DICOM window/VOI LUT.")
    var minimumMaximum = false

    @Flag(name: .shortAndLong, help: "Search input subdirectories recursively.")
    var recursive = false

    @Flag(name: .long, help: "Replace output images that already exist.")
    var overwrite = false

    @Flag(name: .shortAndLong, help: "Print each converted and skipped file.")
    var verbose = false

    mutating func validate() throws {
        guard (1...100).contains(quality) else {
            throw ValidationError("--quality must be between 1 and 100")
        }
        if format != .jpeg, quality != 90 {
            throw ValidationError("--quality is only valid with --format jpeg")
        }
        if let frame, frame < 1 {
            throw ValidationError("--frame is numbered from 1")
        }
        if (windowCenter == nil) != (windowWidth == nil) {
            throw ValidationError("--window-center and --window-width must be provided together")
        }
        if let windowWidth, windowWidth < 1 {
            throw ValidationError("--window-width must be at least 1 for LINEAR rendering")
        }
        if minimumMaximum, windowCenter != nil {
            throw ValidationError("--minimum-maximum cannot be combined with an explicit window")
        }
    }

    mutating func run() throws {
        let manager = FileManager.default
        // Batch probing intentionally encounters non-DICOM files; report them
        // through this command's summary rather than the library logger.
        Logger.shared.outputs = []
        let input = URL(fileURLWithPath: inputPath).standardizedFileURL.resolvingSymlinksInPath()
        let output = URL(fileURLWithPath: outputPath).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: input.path, isDirectory: &isDirectory) else {
            throw ValidationError("input does not exist: \(input.path)")
        }

        let options = renderingOptions()
        var summary = ConversionSummary()
        if isDirectory.boolValue {
            var outputIsDirectory: ObjCBool = false
            if manager.fileExists(atPath: output.path, isDirectory: &outputIsDirectory), !outputIsDirectory.boolValue {
                throw ValidationError("batch output must be a directory: \(output.path)")
            }
            guard input.path != output.path else {
                throw ValidationError("batch output directory must differ from the input directory")
            }
            let inputs = try inputFiles(in: input, recursive: recursive)
                .filter { !isInside($0.0, directory: output) }
            try manager.createDirectory(at: output, withIntermediateDirectories: true)
            for (source, relative) in inputs {
                let destinationBase = output.appendingPathComponent(relative).deletingPathExtension()
                convert(source, destinationBase: destinationBase, exactOutput: nil, options: options, summary: &summary)
            }
        } else {
            let outputIsDirectory = (try? output.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            let exactOutput = !outputIsDirectory && !output.pathExtension.isEmpty ? output : nil
            if let exactOutput, !format.accepts(extension: exactOutput.pathExtension.lowercased()) {
                throw ValidationError("output extension .\(exactOutput.pathExtension) does not match --format \(format.rawValue)")
            }
            let destinationBase = exactOutput?.deletingPathExtension()
                ?? output.appendingPathComponent(input.deletingPathExtension().lastPathComponent)
            convert(input, destinationBase: destinationBase, exactOutput: exactOutput, options: options, summary: &summary)
        }

        print("Converted \(summary.convertedFiles) DICOM file(s), \(summary.convertedFrames) frame(s); "
              + "skipped \(summary.skippedFiles) non-DICOM file(s); \(summary.failures) failure(s).")
        if summary.convertedFiles == 0 || summary.failures > 0 {
            throw ExitCode.failure
        }
    }

    private func renderingOptions() -> DICOMRenderingOptions {
        let voi: DICOMVOISelection
        if minimumMaximum {
            voi = .minimumMaximum
        } else if let center = windowCenter, let width = windowWidth {
            voi = .window(DICOMWindow(center: center, width: width))
        } else {
            voi = .automatic
        }
        return DICOMRenderingOptions(voi: voi)
    }

    private func inputFiles(in directory: URL, recursive: Bool) throws -> [(URL, String)] {
        let manager = FileManager.default
        let relativePaths: [String]
        if recursive {
            guard let enumerator = manager.enumerator(atPath: directory.path) else {
                throw ValidationError("cannot enumerate input directory: \(directory.path)")
            }
            relativePaths = enumerator.compactMap { $0 as? String }
        } else {
            relativePaths = try manager.contentsOfDirectory(atPath: directory.path)
        }
        return try relativePaths
            .filter { !$0.split(separator: "/").contains(where: { $0.hasPrefix(".") }) }
            .compactMap { relative in
                let url = directory.appendingPathComponent(relative)
                return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
                    ? (url, relative) : nil
            }
            .sorted { $0.1 < $1.1 }
    }

    private func isInside(_ file: URL, directory: URL) -> Bool {
        let prefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        return file.path == directory.path || file.path.hasPrefix(prefix)
    }

    private func convert(
        _ source: URL, destinationBase: URL, exactOutput: URL?,
        options: DICOMRenderingOptions, summary: inout ConversionSummary
    ) {
        guard let file = DicomFile(forPath: source.path), let dataset = file.dataset else {
            summary.skippedFiles += 1
            if verbose { print("skip  \(source.path) (not a readable DICOM file)") }
            return
        }
        guard let image = DicomImage(dataset), image.numberOfFrames > 0 else {
            summary.failures += 1
            printError("error \(source.path): no image frames")
            return
        }

        let frames: [Int]
        if let frame {
            guard frame <= image.numberOfFrames else {
                summary.failures += 1
                printError("error \(source.path): frame \(frame) is outside 1...\(image.numberOfFrames)")
                return
            }
            frames = [frame - 1]
        } else {
            frames = Array(0..<image.numberOfFrames)
        }

        var wrote = 0
        for index in frames {
            do {
                let rendered = try image.renderedImage(forFrame: index, options: options)
                let fileExtension = format.fileExtension(for: rendered)
                let destination: URL
                if let exactOutput, frames.count == 1 {
                    let requestedExtension = exactOutput.pathExtension.lowercased()
                    if format == .pnm, requestedExtension != "pnm", requestedExtension != fileExtension {
                        throw ValidationError(".\(requestedExtension) does not match the rendered \(fileExtension.uppercased()) image")
                    }
                    destination = exactOutput
                } else if image.numberOfFrames == 1 {
                    destination = destinationBase.appendingPathExtension(fileExtension)
                } else {
                    let digits = max(4, String(image.numberOfFrames).count)
                    let number = String(format: "%0*d", digits, index + 1)
                    destination = URL(fileURLWithPath: destinationBase.path + "_" + number + "." + fileExtension)
                }
                if FileManager.default.fileExists(atPath: destination.path), !overwrite {
                    throw ValidationError("output exists (use --overwrite): \(destination.path)")
                }
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try encoded(rendered).write(to: destination, options: .atomic)
                wrote += 1
                summary.convertedFrames += 1
                if verbose { print("write \(destination.path)") }
            } catch {
                summary.failures += 1
                printError("error \(source.path), frame \(index + 1): \(error)")
            }
        }
        if wrote > 0 { summary.convertedFiles += 1 }
    }

    private func encoded(_ image: DICOMRenderedImage) throws -> Data {
        switch format {
        case .png: return try image.pngData()
        case .jpeg: return try image.jpegData(quality: quality)
        case .tiff: return image.tiffData()
        case .pnm: return image.pnmData()
        }
    }

    private func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
