import Foundation

/// Resource limits applied while decoding an untrusted DICOM byte stream.
/// Increase individual limits for exceptionally large, trusted objects.
public struct DicomReadLimits: Equatable {
    public var maximumElementValueLength: Int
    public var maximumElementCount: Int
    public var maximumSequenceDepth: Int
    public var maximumItemCount: Int
    public var maximumPixelFragmentCount: Int
    public var maximumInflatedDataSetLength: Int

    public init(
        maximumElementValueLength: Int = 1_073_741_824,
        maximumElementCount: Int = 1_000_000,
        maximumSequenceDepth: Int = 64,
        maximumItemCount: Int = 1_000_000,
        maximumPixelFragmentCount: Int = 1_000_000,
        maximumInflatedDataSetLength: Int = 2_147_483_648
    ) {
        self.maximumElementValueLength = max(0, maximumElementValueLength)
        self.maximumElementCount = max(0, maximumElementCount)
        self.maximumSequenceDepth = max(0, maximumSequenceDepth)
        self.maximumItemCount = max(0, maximumItemCount)
        self.maximumPixelFragmentCount = max(0, maximumPixelFragmentCount)
        self.maximumInflatedDataSetLength = max(0, maximumInflatedDataSetLength)
    }
}
