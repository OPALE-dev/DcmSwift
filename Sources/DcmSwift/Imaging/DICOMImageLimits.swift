import Foundation

/// Resource limits applied before pixels are decoded or rendered.
///
/// The Image Pixel attributes and the headers of encoded streams declare the
/// dimensions of an image, and decoders allocate memory in proportion to
/// them. A small object may therefore declare an image far larger than its
/// data, such as 65535 × 65535 pixels in a few bytes of compressed data. The
/// limits are checked before any allocation proportional to the declared
/// dimensions, and a value beyond them raises
/// ``DICOMPixelDataError/limitExceeded(_:value:limit:)``.
///
/// The defaults admit the images met in practice: projection radiography and
/// mammography, the frames of tiled whole slide images, and long multi-frame
/// series. Raise individual limits for exceptionally large, trusted images.
public struct DICOMImageLimits: Hashable, Sendable {
    /// The default largest number of pixels of one frame: 16384 × 16384.
    public static let defaultMaximumPixelsPerFrame = 268_435_456
    /// The default largest buffer allocated for one frame: 2 GiB.
    public static let defaultMaximumFrameBytes = 2_147_483_648
    /// The default largest Number of Frames.
    public static let defaultMaximumNumberOfFrames = 1_000_000

    /// The largest number of pixels (Rows × Columns) of one frame, as declared
    /// by the Data Set or by an encoded stream.
    public var maximumPixelsPerFrame: Int
    /// The largest buffer, in bytes, allocated for one frame: its decoded
    /// samples, the stored or Modality values computed from them, or its
    /// rendered pixels. A codec that decodes several frames as one unit, such
    /// as a JPEG 2000 Part 2 component collection, is held to this bound for
    /// the whole unit.
    public var maximumFrameBytes: Int
    /// The largest Number of Frames (0028,0008).
    public var maximumNumberOfFrames: Int

    /// Creates limits; negative values are read as 0.
    ///
    /// - Parameters:
    ///   - maximumPixelsPerFrame: The largest number of pixels of one frame.
    ///   - maximumFrameBytes: The largest buffer, in bytes, allocated for one
    ///     frame or decoded unit.
    ///   - maximumNumberOfFrames: The largest Number of Frames.
    public init(
        maximumPixelsPerFrame: Int = DICOMImageLimits.defaultMaximumPixelsPerFrame,
        maximumFrameBytes: Int = DICOMImageLimits.defaultMaximumFrameBytes,
        maximumNumberOfFrames: Int = DICOMImageLimits.defaultMaximumNumberOfFrames
    ) {
        self.maximumPixelsPerFrame = max(0, maximumPixelsPerFrame)
        self.maximumFrameBytes = max(0, maximumFrameBytes)
        self.maximumNumberOfFrames = max(0, maximumNumberOfFrames)
    }

    /// Checks a frame before memory is allocated for it, for example from the
    /// dimensions that an encoded stream declares. Custom decoders registered
    /// in ``DICOMCodecRegistry`` call it before allocating their output.
    ///
    /// - Parameters:
    ///   - rows: The number of rows of the frame.
    ///   - columns: The number of columns of the frame.
    ///   - samplesPerPixel: The number of samples, or components, per pixel.
    ///   - bytesPerSample: The bytes allocated for each sample.
    /// - Throws: ``DICOMPixelDataError/limitExceeded(_:value:limit:)`` when
    ///   the frame has more pixels than ``maximumPixelsPerFrame`` or needs more
    ///   bytes than ``maximumFrameBytes``.
    public func checkFrame(rows: Int, columns: Int, samplesPerPixel: Int, bytesPerSample: Int) throws {
        let pixels = Self.product(rows, columns)
        guard pixels <= maximumPixelsPerFrame else {
            throw DICOMPixelDataError.limitExceeded("pixels per frame", value: pixels, limit: maximumPixelsPerFrame)
        }
        try checkBuffer(count: Self.product(pixels, samplesPerPixel), bytesPerElement: bytesPerSample)
    }

    /// Checks a buffer of `count` elements of `bytesPerElement` bytes against
    /// ``maximumFrameBytes``.
    func checkBuffer(count: Int, bytesPerElement: Int) throws {
        let bytes = Self.product(count, bytesPerElement)
        guard bytes <= maximumFrameBytes else {
            throw DICOMPixelDataError.limitExceeded("bytes per frame", value: bytes, limit: maximumFrameBytes)
        }
    }

    /// Checks the dimensions and frame count of an image description, using
    /// the bytes of its largest decoded sample.
    func check(_ description: DICOMPixelDescription) throws {
        guard description.numberOfFrames <= maximumNumberOfFrames else {
            throw DICOMPixelDataError.limitExceeded(
                "NumberOfFrames", value: description.numberOfFrames, limit: maximumNumberOfFrames)
        }
        try checkFrame(
            rows: description.rows, columns: description.columns,
            samplesPerPixel: description.samplesPerPixel, bytesPerSample: max(1, description.bitsAllocated / 8))
    }

    /// The product of non-negative factors, or `Int.max` when it overflows.
    static func product(_ first: Int, _ second: Int) -> Int {
        guard first >= 0, second >= 0 else { return .max }
        let (value, overflow) = first.multipliedReportingOverflow(by: second)
        return overflow ? .max : value
    }
}
