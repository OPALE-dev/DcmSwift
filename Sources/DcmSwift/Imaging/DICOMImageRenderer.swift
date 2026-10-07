import Foundation

/// An 8-bit image produced by `DICOMImageRenderer`, independent of any
/// platform graphics framework.
public struct DICOMRenderedImage: Equatable, Sendable {
    public enum Format: Equatable, Sendable {
        /// One byte per pixel, 0 black.
        case gray8
        /// Three bytes per pixel: red, green, blue.
        case rgb8

        public var bytesPerPixel: Int { self == .gray8 ? 1 : 3 }
    }

    public let width: Int
    public let height: Int
    public let format: Format
    /// Row-major pixels without row padding.
    public let pixels: [UInt8]

    public init(width: Int, height: Int, format: Format, pixels: [UInt8]) {
        precondition(pixels.count == width * height * format.bytesPerPixel)
        self.width = width
        self.height = height
        self.format = format
        self.pixels = pixels
    }
}

/// Window Center, Window Width, and VOI LUT Function (PS3.3 C.11.2.1.2-3).
public struct DICOMWindow: Equatable, Sendable {
    public enum Function: String, Equatable, Sendable {
        case linear = "LINEAR"
        case linearExact = "LINEAR_EXACT"
        case sigmoid = "SIGMOID"
    }

    public let center: Double
    public let width: Double
    public let function: Function

    public init(center: Double, width: Double, function: Function = .linear) {
        self.center = center
        self.width = width
        self.function = function
    }

    /// Maps an input value to `minimum...maximum` with the normative
    /// pseudo-code of the selected function.
    public func apply(_ x: Double, minimum: Double = 0, maximum: Double = 255) -> Double {
        let c = center
        let w = width
        switch function {
        case .linear:
            if x <= c - 0.5 - (w - 1) / 2 { return minimum }
            if x > c - 0.5 + (w - 1) / 2 { return maximum }
            return ((x - (c - 0.5)) / (w - 1) + 0.5) * (maximum - minimum) + minimum
        case .linearExact:
            if x <= c - w / 2 { return minimum }
            if x > c + w / 2 { return maximum }
            return ((x - c) / w + 0.5) * (maximum - minimum) + minimum
        case .sigmoid:
            return (maximum - minimum) / (1 + exp(-4 * (x - c) / w)) + minimum
        }
    }

    fileprivate func validate() throws {
        switch function {
        case .linear:
            guard width >= 1 else { throw DICOMPixelDataError.invalidAttribute("WindowWidth", "\(width) is below 1") }
        case .linearExact, .sigmoid:
            guard width > 0 else { throw DICOMPixelDataError.invalidAttribute("WindowWidth", "\(width) is not positive") }
        }
    }
}

/// Values of Interest selection for grayscale rendering.
public enum DICOMVOISelection: Equatable, Sendable {
    /// The first window, else the first VOI LUT, else `identity`.
    case automatic
    case window(DICOMWindow)
    /// An Item of VOI LUT Sequence (0028,3010).
    case lookupTable(index: Int)
    /// The identity VOI: the full possible output range of the Modality
    /// transformation is mapped to the display range (PS3.3 C.11.2.1.2.2).
    case identity
    /// The range of values actually present in the frame.
    case minimumMaximum
}

public struct DICOMRenderingOptions: Equatable, Sendable {
    public var voi: DICOMVOISelection
    /// Displays MONOCHROME1 images with their minimum value as white.
    public var honorsMonochrome1: Bool

    public init(voi: DICOMVOISelection = .automatic, honorsMonochrome1: Bool = true) {
        self.voi = voi
        self.honorsMonochrome1 = honorsMonochrome1
    }
}

/// Renders native or decodable encapsulated Pixel Data through the grayscale pipeline (Modality LUT or
/// Rescale, VOI LUT or window, MONOCHROME1 polarity) or the color
/// conversions of PS3.3 C.7.6.3.1.2, on every platform.
///
/// Frame-level values come from the Per-Frame Functional Groups, then the
/// Shared Functional Groups, then the top-level Data Set.
public struct DICOMImageRenderer {
    public let description: DICOMPixelDescription
    /// Native Pixel Data, when the Pixel Data is not encapsulated.
    public let pixelData: DICOMNativePixelData?
    /// Encapsulated Pixel Data, decoded frame by frame by a registered codec.
    public let encapsulatedPixelData: DICOMEncapsulatedPixelData?
    private let scope: DICOMAttributeScope
    private let shared: DICOMAttributeScope?
    private let perFrame: [DICOMAttributeScope]

    public init(dataset: DataSet) throws {
        let scope = DICOMAttributeScope(dataset: dataset)
        if scope.element("PixelData") is DataSequence {
            let encapsulated = try DICOMEncapsulatedPixelData(dataset: dataset)
            guard DICOMCodecRegistry.decoder(for: encapsulated.transferSyntaxUID) != nil else {
                throw DICOMPixelDataError.encapsulatedPixelData(transferSyntax: encapsulated.transferSyntaxUID)
            }
            self.pixelData = nil
            self.encapsulatedPixelData = encapsulated
            self.description = encapsulated.description
        } else {
            let pixelData = try DICOMNativePixelData(dataset: dataset)
            self.pixelData = pixelData
            self.encapsulatedPixelData = nil
            self.description = pixelData.description
        }
        self.scope = scope
        self.shared = scope.items("SharedFunctionalGroupsSequence").first.map(DICOMAttributeScope.init(item:))
        self.perFrame = scope.items("PerFrameFunctionalGroupsSequence").map(DICOMAttributeScope.init(item:))
    }

    // MARK: Frame-level attributes

    /// The Functional Group macro Item that applies to a frame.
    private func macro(_ sequence: String, frame: Int) -> DICOMAttributeScope? {
        if frame < perFrame.count, let item = perFrame[frame].items(sequence).first {
            return DICOMAttributeScope(item: item)
        }
        return shared?.items(sequence).first.map(DICOMAttributeScope.init(item:))
    }

    /// Rescale Slope and Intercept for a frame; identity when absent.
    public func rescale(frame: Int = 0) throws -> (slope: Double, intercept: Double) {
        let source = macro("PixelValueTransformationSequence", frame: frame) ?? scope
        let slope = source.doubles("RescaleSlope")?.first ?? 1
        let intercept = source.doubles("RescaleIntercept")?.first ?? 0
        guard slope.isFinite, intercept.isFinite, slope != 0 else {
            throw DICOMPixelDataError.invalidAttribute("RescaleSlope", "\(slope)")
        }
        return (slope, intercept)
    }

    /// The windows a frame proposes, in order.
    public func windows(frame: Int = 0) throws -> [DICOMWindow] {
        let source = macro("FrameVOILUTSequence", frame: frame) ?? scope
        guard let centers = source.doubles("WindowCenter"), let widths = source.doubles("WindowWidth") else {
            return []
        }
        guard centers.count == widths.count else {
            throw DICOMPixelDataError.invalidAttribute("WindowWidth", "\(widths.count) Values for \(centers.count) centers")
        }
        let functionName = source.strings("VOILUTFunction").first.flatMap { $0.isEmpty ? nil : $0 } ?? "LINEAR"
        guard let function = DICOMWindow.Function(rawValue: functionName) else {
            throw DICOMPixelDataError.invalidAttribute("VOILUTFunction", functionName)
        }
        return zip(centers, widths).map { DICOMWindow(center: $0, width: $1, function: function) }
    }

    private var modalityLookupTable: DICOMLookupTable? {
        get throws {
            guard let item = scope.items("ModalityLUTSequence").first else { return nil }
            let lut = DICOMAttributeScope(item: item)
            guard let descriptor = lut.element("LUTDescriptor") else {
                throw DICOMPixelDataError.invalidLookupTable("ModalityLUTSequence", "missing LUT Descriptor")
            }
            return try DICOMLookupTable(
                descriptor: descriptor, data: lut.element("LUTData"),
                signedFirstValue: description.isSigned, name: "ModalityLUTSequence")
        }
    }

    private func voiLookupTable(index: Int, signedInput: Bool) throws -> DICOMLookupTable {
        let items = scope.items("VOILUTSequence")
        guard items.indices.contains(index) else {
            throw DICOMPixelDataError.invalidLookupTable("VOILUTSequence", "no Item \(index)")
        }
        let lut = DICOMAttributeScope(item: items[index])
        guard let descriptor = lut.element("LUTDescriptor") else {
            throw DICOMPixelDataError.invalidLookupTable("VOILUTSequence", "missing LUT Descriptor")
        }
        return try DICOMLookupTable(
            descriptor: descriptor, data: lut.element("LUTData"),
            signedFirstValue: signedInput, name: "VOILUTSequence")
    }

    // MARK: Frames

    /// Native samples of a frame and the index to read them at: the frame
    /// itself for native Pixel Data, or 0 in a decoded single-frame source.
    private func source(of frame: Int) throws -> (pixels: DICOMNativePixelData, index: Int) {
        if let pixelData {
            return (pixelData, frame)
        }
        guard let encapsulatedPixelData else { throw DICOMPixelDataError.missingPixelData }
        guard (0..<description.numberOfFrames).contains(frame) else {
            throw DICOMPixelDataError.frameOutOfRange(frame, numberOfFrames: description.numberOfFrames)
        }
        let decoded = try encapsulatedPixelData.decodedFrame(frame)
        return (try DICOMNativePixelData(description: decoded.description, decodedFrames: decoded.data), 0)
    }

    /// Stored sample values of a frame, decoding it first when encapsulated.
    public func storedValues(frame: Int = 0) throws -> [Int64] {
        let source = try source(of: frame)
        return try source.pixels.storedValues(frame: source.index)
    }

    // MARK: Rendering

    public func render(frame: Int = 0, options: DICOMRenderingOptions = DICOMRenderingOptions()) throws
        -> DICOMRenderedImage {
        let source = try source(of: frame)
        let frameDescription = source.pixels.description
        switch frameDescription.photometricInterpretation {
        case .monochrome1, .monochrome2:
            return try renderGrayscale(frame: frame, source: source, options: options)
        case .rgb, .ybrFull, .ybrFull422:
            return try renderColor(source: source)
        case .paletteColor:
            return try renderPalette(source: source)
        default:
            throw DICOMPixelDataError.unsupportedPhotometricInterpretation(
                frameDescription.photometricInterpretation.rawValue)
        }
    }

    /// Output of the Modality transformation for every pixel of a frame:
    /// Modality LUT, else Rescale Slope and Intercept. Floating point Pixel
    /// Data is returned unchanged.
    public func modalityValues(frame: Int = 0) throws -> [Double] {
        try modalityValues(frame: frame, source: source(of: frame))
    }

    private func modalityValues(
        frame: Int, source: (pixels: DICOMNativePixelData, index: Int)
    ) throws -> [Double] {
        guard source.pixels.description.photometricInterpretation.isMonochrome else {
            throw DICOMPixelDataError.unsupportedPhotometricInterpretation(
                source.pixels.description.photometricInterpretation.rawValue)
        }
        if description.sampleFormat != .integer {
            return try source.pixels.floatingPointValues(frame: source.index)
        }
        let stored = try source.pixels.storedValues(frame: source.index)
        if let lut = try modalityLookupTable {
            return stored.map { Double(lut.entry(for: Int($0))) }
        }
        let (slope, intercept) = try rescale(frame: frame)
        return stored.map { Double($0) * slope + intercept }
    }

    private func renderGrayscale(
        frame: Int, source: (pixels: DICOMNativePixelData, index: Int), options: DICOMRenderingOptions
    ) throws -> DICOMRenderedImage {
        let modalityLUT = try modalityLookupTable
        let (slope, intercept) = try rescale(frame: frame)

        // The possible range of the Modality output (PS3.3 C.11.1.1.1).
        let possibleRange: ClosedRange<Double>
        if let modalityLUT {
            possibleRange = 0...Double(modalityLUT.maximumEntryValue)
        } else {
            let stored = description.storedValueRange
            let ends = [Double(stored.lowerBound) * slope + intercept, Double(stored.upperBound) * slope + intercept]
            possibleRange = ends.min()!...ends.max()!
        }

        let values = try modalityValues(frame: frame, source: source)

        var selection = options.voi
        if selection == .automatic {
            if let window = try windows(frame: frame).first {
                selection = .window(window)
            } else if !scope.items("VOILUTSequence").isEmpty {
                selection = .lookupTable(index: 0)
            } else if description.sampleFormat == .integer {
                selection = .identity
            } else {
                // Floating point Pixel Data has no bounded possible range.
                selection = .minimumMaximum
            }
        }

        let voi: (Double) -> Double
        switch selection {
        case .automatic:
            preconditionFailure("resolved above")
        case .window(let window):
            try window.validate()
            voi = { window.apply($0) }
        case .lookupTable(let index):
            let lut = try voiLookupTable(index: index, signedInput: possibleRange.lowerBound < 0)
            let scale = 255 / Double(lut.maximumEntryValue)
            voi = { Double(lut.entry(for: Int($0.rounded(.down)))) * scale }
        case .identity:
            voi = Self.linearMap(possibleRange)
        case .minimumMaximum:
            let finite = values.filter(\.isFinite)
            let range = (finite.min() ?? 0)...(finite.max() ?? 0)
            voi = Self.linearMap(range)
        }

        let invert = options.honorsMonochrome1 && source.pixels.description.photometricInterpretation == .monochrome1
        let pixels = values.map { value -> UInt8 in
            let output = value.isFinite ? voi(value) : 0
            let byte = UInt8(clamping: Int(min(max(output, 0), 255).rounded()))
            return invert ? 255 - byte : byte
        }
        return DICOMRenderedImage(width: description.columns, height: description.rows, format: .gray8, pixels: pixels)
    }

    private static func linearMap(_ range: ClosedRange<Double>) -> (Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return { $0 > range.lowerBound ? 255 : 0 } }
        return { ($0 - range.lowerBound) / span * 255 }
    }

    private func renderColor(source: (pixels: DICOMNativePixelData, index: Int)) throws -> DICOMRenderedImage {
        let description = source.pixels.description
        guard description.sampleFormat == .integer else {
            throw DICOMPixelDataError.unsupportedPhotometricInterpretation("floating point color")
        }
        let samples = try source.pixels.storedValues(frame: source.index)
        let maximum = Double(description.storedValueRange.upperBound)
        let toByte = { (value: Double) -> UInt8 in
            UInt8(clamping: Int((min(max(value, 0), maximum) / maximum * 255).rounded()))
        }
        var pixels = [UInt8](repeating: 0, count: description.pixelsPerFrame * 3)

        if description.photometricInterpretation == .rgb {
            for index in samples.indices {
                pixels[index] = toByte(Double(samples[index]))
            }
        } else {
            // YBR_FULL: black is Y = 0 and no color is half full scale
            // (PS3.3 C.7.6.3.1.2); inverse of the CCIR 601-2 equations.
            let half = Double(Int64(1) << (description.bitsStored - 1))
            for pixel in 0..<description.pixelsPerFrame {
                let y = Double(samples[pixel * 3])
                let cb = Double(samples[pixel * 3 + 1]) - half
                let cr = Double(samples[pixel * 3 + 2]) - half
                pixels[pixel * 3] = toByte(y + 1.402 * cr)
                pixels[pixel * 3 + 1] = toByte(y - 0.344136 * cb - 0.714136 * cr)
                pixels[pixel * 3 + 2] = toByte(y + 1.772 * cb)
            }
        }
        return DICOMRenderedImage(width: description.columns, height: description.rows, format: .rgb8, pixels: pixels)
    }

    private func renderPalette(source: (pixels: DICOMNativePixelData, index: Int)) throws -> DICOMRenderedImage {
        let palettes = try ["Red", "Green", "Blue"].map { color -> DICOMLookupTable in
            let name = "\(color)PaletteColorLookupTableDescriptor"
            guard let descriptor = scope.element(name) else { throw DICOMPixelDataError.missingAttribute(name) }
            return try DICOMLookupTable(
                descriptor: descriptor,
                data: scope.element("\(color)PaletteColorLookupTableData"),
                segmentedData: scope.element("Segmented\(color)PaletteColorLookupTableData"),
                signedFirstValue: description.isSigned,
                allowedBits: 8...16,
                name: name)
        }
        guard palettes[0].entries.count == palettes[1].entries.count,
              palettes[0].entries.count == palettes[2].entries.count,
              palettes[0].firstValueMapped == palettes[1].firstValueMapped,
              palettes[0].firstValueMapped == palettes[2].firstValueMapped else {
            throw DICOMPixelDataError.invalidLookupTable(
                "PaletteColorLookupTableDescriptor", "Red, Green, and Blue descriptors differ")
        }
        let samples = try source.pixels.storedValues(frame: source.index)
        var pixels = [UInt8](repeating: 0, count: samples.count * 3)
        for (index, sample) in samples.enumerated() {
            for channel in 0..<3 {
                let palette = palettes[channel]
                let entry = palette.entry(for: Int(sample))
                // 16-bit entries span 0...65535; keep the most significant byte.
                pixels[index * 3 + channel] = palette.bitsPerEntry > 8
                    ? UInt8(entry >> UInt16(palette.bitsPerEntry - 8))
                    : UInt8(entry)
            }
        }
        return DICOMRenderedImage(width: description.columns, height: description.rows, format: .rgb8, pixels: pixels)
    }
}
