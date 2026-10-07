import Foundation

/// Errors raised while interpreting Pixel Data and the attributes describing
/// it. Every error identifies the attribute or condition at fault so that
/// malformed images are reported instead of rendered incorrectly.
public enum DICOMPixelDataError: Error, Equatable, CustomStringConvertible {
    case missingAttribute(String)
    case invalidAttribute(String, String)
    case unsupportedPhotometricInterpretation(String)
    case missingPixelData
    /// Encapsulated (compressed) Pixel Data needs a codec for this Transfer
    /// Syntax.
    case encapsulatedPixelData(transferSyntax: String)
    case truncatedPixelData(expectedBytes: Int, actualBytes: Int)
    case frameOutOfRange(Int, numberOfFrames: Int)
    case invalidLookupTable(String, String)

    public var description: String {
        switch self {
        case .missingAttribute(let name):
            return "Missing \(name)"
        case .invalidAttribute(let name, let reason):
            return "Invalid \(name): \(reason)"
        case .unsupportedPhotometricInterpretation(let value):
            return "Unsupported Photometric Interpretation \(value)"
        case .missingPixelData:
            return "Missing Pixel Data"
        case .encapsulatedPixelData(let transferSyntax):
            return "Encapsulated Pixel Data requires a codec for Transfer Syntax \(transferSyntax)"
        case .truncatedPixelData(let expected, let actual):
            return "Pixel Data holds \(actual) bytes but \(expected) are required"
        case .frameOutOfRange(let frame, let count):
            return "Frame \(frame) is outside 0..<\(count)"
        case .invalidLookupTable(let name, let reason):
            return "Invalid \(name): \(reason)"
        }
    }
}

/// Photometric Interpretation (0028,0004), PS3.3 C.7.6.3.1.2.
public struct DICOMPhotometricInterpretation: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let monochrome1 = Self(rawValue: "MONOCHROME1")
    public static let monochrome2 = Self(rawValue: "MONOCHROME2")
    public static let paletteColor = Self(rawValue: "PALETTE COLOR")
    public static let rgb = Self(rawValue: "RGB")
    public static let ybrFull = Self(rawValue: "YBR_FULL")
    public static let ybrFull422 = Self(rawValue: "YBR_FULL_422")
    public static let ybrPartial420 = Self(rawValue: "YBR_PARTIAL_420")
    public static let ybrICT = Self(rawValue: "YBR_ICT")
    public static let ybrRCT = Self(rawValue: "YBR_RCT")

    public var isMonochrome: Bool { self == .monochrome1 || self == .monochrome2 }
}

/// The Image Pixel Description of PS3.3 C.7.6.3.3, validated against the
/// encoding rules of PS3.5 8.1.1.
public struct DICOMPixelDescription: Equatable, Sendable {
    public enum SampleFormat: Equatable, Sendable {
        /// Pixel Data (7FE0,0010) integer samples.
        case integer
        /// Float Pixel Data (7FE0,0008).
        case float32
        /// Double Float Pixel Data (7FE0,0009).
        case float64
    }

    public let rows: Int
    public let columns: Int
    public let samplesPerPixel: Int
    public let photometricInterpretation: DICOMPhotometricInterpretation
    public let bitsAllocated: Int
    public let bitsStored: Int
    public let highBit: Int
    /// Pixel Representation 0001H (2's complement).
    public let isSigned: Bool
    /// 0 for color-by-pixel, 1 for color-by-plane.
    public let planarConfiguration: Int
    public let numberOfFrames: Int
    public let sampleFormat: SampleFormat

    public var pixelsPerFrame: Int { rows * columns }

    /// Encoded samples per frame. YBR_FULL_422 stores two chrominance samples
    /// per pair of pixels (PS3.3 C.7.6.3.1.2).
    public var encodedSamplesPerFrame: Int {
        photometricInterpretation == .ybrFull422 ? pixelsPerFrame * 2 : pixelsPerFrame * samplesPerPixel
    }

    /// Bits per frame. Native frames are concatenated without padding, so
    /// with one bit allocated a frame may start inside a byte (PS3.5 8.1.1).
    public var bitsPerFrame: Int { encodedSamplesPerFrame * bitsAllocated }

    /// The smallest and largest stored value Bits Stored and Pixel
    /// Representation allow.
    public var storedValueRange: ClosedRange<Int64> {
        isSigned
            ? -(Int64(1) << (bitsStored - 1))...((Int64(1) << (bitsStored - 1)) - 1)
            : 0...((Int64(1) << bitsStored) - 1)
    }

    public init(dataset: DataSet) throws {
        let scope = DICOMAttributeScope(dataset: dataset)
        let sampleFormat: SampleFormat
        if scope.element("PixelData") != nil {
            sampleFormat = .integer
        } else if scope.element("FloatPixelData") != nil {
            sampleFormat = .float32
        } else if scope.element("DoubleFloatPixelData") != nil {
            sampleFormat = .float64
        } else {
            sampleFormat = .integer
        }
        try self.init(scope: scope, sampleFormat: sampleFormat)
    }

    init(scope: DICOMAttributeScope, sampleFormat: SampleFormat) throws {
        func required(_ name: String) throws -> Int {
            guard let value = scope.integer(name) else { throw DICOMPixelDataError.missingAttribute(name) }
            return value
        }

        rows = try required("Rows")
        columns = try required("Columns")
        guard rows > 0 else { throw DICOMPixelDataError.invalidAttribute("Rows", "must be at least 1") }
        guard columns > 0 else { throw DICOMPixelDataError.invalidAttribute("Columns", "must be at least 1") }

        samplesPerPixel = try required("SamplesPerPixel")
        guard samplesPerPixel >= 1 else {
            throw DICOMPixelDataError.invalidAttribute("SamplesPerPixel", "must be at least 1")
        }
        guard let photometric = scope.strings("PhotometricInterpretation").first, !photometric.isEmpty else {
            throw DICOMPixelDataError.missingAttribute("PhotometricInterpretation")
        }
        photometricInterpretation = DICOMPhotometricInterpretation(rawValue: photometric)

        self.sampleFormat = sampleFormat
        bitsAllocated = try required("BitsAllocated")
        switch sampleFormat {
        case .integer:
            guard bitsAllocated == 1 || (bitsAllocated % 8 == 0 && bitsAllocated <= 32) else {
                throw DICOMPixelDataError.invalidAttribute(
                    "BitsAllocated", "\(bitsAllocated) is not 1 or a multiple of 8 up to 32")
            }
            bitsStored = try required("BitsStored")
            highBit = try required("HighBit")
            guard (1...bitsAllocated).contains(bitsStored) else {
                throw DICOMPixelDataError.invalidAttribute(
                    "BitsStored", "\(bitsStored) is not within 1...\(bitsAllocated)")
            }
            // PS3.5 now requires High Bit = Bits Stored - 1; earlier editions
            // allowed other positions, which remain readable.
            guard highBit >= bitsStored - 1, highBit < bitsAllocated else {
                throw DICOMPixelDataError.invalidAttribute(
                    "HighBit", "\(highBit) does not place \(bitsStored) bits within \(bitsAllocated)")
            }
            switch try required("PixelRepresentation") {
            case 0: isSigned = false
            case 1: isSigned = true
            case let value: throw DICOMPixelDataError.invalidAttribute("PixelRepresentation", "\(value)")
            }
        case .float32, .float64:
            // Float pixel cells occupy all allocated bits (PS3.5 8.1.1).
            let expected = sampleFormat == .float32 ? 32 : 64
            guard bitsAllocated == expected else {
                throw DICOMPixelDataError.invalidAttribute(
                    "BitsAllocated", "\(bitsAllocated) for floating point Pixel Data must be \(expected)")
            }
            bitsStored = bitsAllocated
            highBit = bitsAllocated - 1
            isSigned = true
        }

        if samplesPerPixel > 1 {
            // Type 1C; absent values are read as color-by-pixel.
            let value = scope.integer("PlanarConfiguration") ?? 0
            guard value == 0 || value == 1 else {
                throw DICOMPixelDataError.invalidAttribute("PlanarConfiguration", "\(value)")
            }
            planarConfiguration = value
        } else {
            planarConfiguration = 0
        }

        if let frames = scope.strings("NumberOfFrames").first, !frames.isEmpty {
            guard let value = Int(frames), value >= 1 else {
                throw DICOMPixelDataError.invalidAttribute("NumberOfFrames", frames)
            }
            numberOfFrames = value
        } else {
            numberOfFrames = 1
        }

        try validatePhotometricConstraints()
    }

    private func validatePhotometricConstraints() throws {
        let name = photometricInterpretation.rawValue
        switch photometricInterpretation {
        case .monochrome1, .monochrome2, .paletteColor:
            guard samplesPerPixel == 1 else {
                throw DICOMPixelDataError.invalidAttribute("SamplesPerPixel", "\(name) requires 1")
            }
        case .rgb, .ybrFull:
            guard samplesPerPixel == 3 else {
                throw DICOMPixelDataError.invalidAttribute("SamplesPerPixel", "\(name) requires 3")
            }
        case .ybrFull422:
            guard samplesPerPixel == 3, planarConfiguration == 0, columns % 2 == 0, bitsAllocated >= 8 else {
                throw DICOMPixelDataError.invalidAttribute(
                    "PhotometricInterpretation",
                    "YBR_FULL_422 requires 3 samples, Planar Configuration 0, and an even number of columns")
            }
        default:
            break
        }
        if photometricInterpretation == .paletteColor && sampleFormat != .integer {
            throw DICOMPixelDataError.invalidAttribute("PhotometricInterpretation", "PALETTE COLOR requires integer samples")
        }
    }
}

/// Attribute lookup restricted to one Data Set level: the top level, a
/// Sequence Item, or a Functional Group. Values are never taken from nested
/// Sequences by accident.
struct DICOMAttributeScope {
    let elements: [DataElement]

    init(dataset: DataSet) {
        elements = dataset.datasetElements
    }

    init(item: DataItem) {
        elements = item.elements
    }

    func element(_ keyword: String) -> DataElement? {
        elements.first { $0.name == keyword }
    }

    func items(_ keyword: String) -> [DataItem] {
        (element(keyword) as? DataSequence)?.items ?? []
    }

    /// Text values split on the value delimiter and trimmed.
    func strings(_ keyword: String) -> [String] {
        guard let element = element(keyword), let text = element.value as? String else { return [] }
        return text.components(separatedBy: "\\").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        }
    }

    /// Decimal or Integer String values; nil when absent or not numeric.
    func doubles(_ keyword: String) -> [Double]? {
        let values = strings(keyword).filter { !$0.isEmpty }
        guard !values.isEmpty else { return nil }
        let numbers = values.compactMap(Double.init)
        return numbers.count == values.count ? numbers : nil
    }

    /// The first value of a US, SS, UL, SL, or IS attribute.
    func integer(_ keyword: String) -> Int? {
        guard let element = element(keyword) else { return nil }
        switch element.vr {
        case .US: return words(of: element).first.map(Int.init)
        case .SS: return words(of: element).first.map { Int(Int16(bitPattern: $0)) }
        case .IS, .DS: return strings(keyword).first.flatMap { Int($0) }
        default:
            if let value = element.value as? UInt16 { return Int(value) }
            if let value = element.value as? Int16 { return Int(value) }
            if let value = element.value as? UInt32 { return Int(value) }
            if let value = element.value as? Int32 { return Int(value) }
            return words(of: element).first.map(Int.init)
        }
    }

    /// The Value Field as 16-bit words in the element's byte order.
    func words(of element: DataElement) -> [UInt16] {
        guard let data = try? element.loadData() else { return [] }
        let bytes = [UInt8](data)
        let bigEndian = element.byteOrder == .BigEndian
        return stride(from: 0, to: bytes.count - 1, by: 2).map { index in
            bigEndian
                ? UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
                : UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
        }
    }
}
