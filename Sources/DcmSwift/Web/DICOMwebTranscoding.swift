import Foundation

/// Representations of stored instances for the Retrieve Transaction:
/// Part 10 files in a Selected Transfer Syntax, metadata, and frames.
enum DICOMwebTranscoding {
    /// Encapsulated Transfer Syntaxes that are always reversible, which an
    /// origin server decompresses when Explicit VR Little Endian is asked.
    /// Others may hold lossy data, which PS3.18 8.7.3.4 lets the origin
    /// server return as stored.
    static let losslessEncapsulated: Set<String> = [
        "1.2.840.10008.1.2.5", "1.2.840.10008.1.2.8.1", "1.2.840.10008.1.2.4.57", "1.2.840.10008.1.2.4.58",
        "1.2.840.10008.1.2.4.65", "1.2.840.10008.1.2.4.66", "1.2.840.10008.1.2.4.70", "1.2.840.10008.1.2.4.80",
        "1.2.840.10008.1.2.4.90", "1.2.840.10008.1.2.4.92", "1.2.840.10008.1.2.4.201", "1.2.840.10008.1.2.4.202",
        "1.2.840.10008.1.2.4.110",
    ]

    /// Native syntaxes that can be re-encoded as Explicit VR Little Endian.
    static let native: Set<String> = [
        TransferSyntax.implicitVRLittleEndian, TransferSyntax.explicitVRLittleEndian,
        TransferSyntax.explicitVRBigEndian, TransferSyntax.deflatedExplicitVRLittleEndian,
    ]

    /// The Transfer Syntaxes in which an instance can be returned: as
    /// stored first, then Explicit VR Little Endian when it can be produced.
    static func availableTransferSyntaxes(of item: DICOMRetrieveItem) -> [String] {
        var syntaxes: [String] = []
        // Implicit VR and Big Endian are not used by Web Services (PS3.18 8.7.3).
        if item.transferSyntaxUID != TransferSyntax.implicitVRLittleEndian
            && item.transferSyntaxUID != TransferSyntax.explicitVRBigEndian {
            syntaxes.append(item.transferSyntaxUID)
        }
        if item.transferSyntaxUID != TransferSyntax.explicitVRLittleEndian
            && (native.contains(item.transferSyntaxUID) || losslessEncapsulated.contains(item.transferSyntaxUID)) {
            syntaxes.append(TransferSyntax.explicitVRLittleEndian)
        }
        return syntaxes
    }

    /// The data set bytes of `item` in `transferSyntax`, which must be one
    /// of `availableTransferSyntaxes(of:)`.
    static func payload(_ item: DICOMRetrieveItem, in transferSyntax: String) throws -> DICOMDataSetPayload {
        if transferSyntax == item.transferSyntaxUID { return item.payload }
        guard transferSyntax == TransferSyntax.explicitVRLittleEndian else {
            throw DICOMCommandError("cannot transcode \(item.transferSyntaxUID) to \(transferSyntax)")
        }
        let dataSet = try DICOMDataSetCoding.decode(item.payload.data(), transferSyntax: item.transferSyntaxUID)
        if losslessEncapsulated.contains(item.transferSyntaxUID) { try decompress(dataSet, from: item.transferSyntaxUID) }
        return DICOMDataSetPayload(data: try DICOMDataSetCoding.encode(dataSet, transferSyntax: transferSyntax))
    }

    /// Replaces encapsulated Pixel Data by its decoded frames, and the Image
    /// Pixel attributes by those of the decoded frames.
    static func decompress(_ dataSet: DataSet, from transferSyntax: String) throws {
        dataSet.transferSyntax = TransferSyntax(transferSyntax)
        let encapsulated = try DICOMEncapsulatedPixelData(dataset: dataSet)
        var pixels = Data()
        var decoded: DICOMPixelDescription?
        for frame in 0..<encapsulated.description.numberOfFrames {
            let result = try encapsulated.decodedFrame(frame)
            decoded = decoded ?? result.description
            pixels.append(result.data)
        }
        guard let decoded else { throw DICOMCommandError("no frame to decode") }
        if pixels.count % 2 == 1 { pixels.append(0) }
        if let element = dataSet.element(forTagName: "PixelData") { _ = dataSet.remove(dataElement: element) }
        _ = dataSet.set(value: decoded.photometricInterpretation.rawValue, forTagName: "PhotometricInterpretation")
        _ = dataSet.set(value: UInt16(decoded.bitsAllocated), forTagName: "BitsAllocated")
        _ = dataSet.set(value: UInt16(decoded.bitsStored), forTagName: "BitsStored")
        _ = dataSet.set(value: UInt16(decoded.highBit), forTagName: "HighBit")
        _ = dataSet.set(value: UInt16(decoded.samplesPerPixel), forTagName: "SamplesPerPixel")
        if decoded.samplesPerPixel > 1 {
            _ = dataSet.set(value: UInt16(decoded.planarConfiguration), forTagName: "PlanarConfiguration")
        }
        guard let element = dataSet.set(value: pixels, forTagName: "PixelData") else {
            throw DICOMCommandError("cannot set the decoded Pixel Data")
        }
        element.vr = decoded.bitsAllocated > 8 ? .OW : .OB
        dataSet.transferSyntax = TransferSyntax(TransferSyntax.explicitVRLittleEndian)
    }

    /// The data set of an instance.
    static func dataSet(_ item: DICOMRetrieveItem) throws -> DataSet {
        let dataSet = try DICOMDataSetCoding.decode(item.payload.data(), transferSyntax: item.transferSyntaxUID)
        dataSet.transferSyntax = TransferSyntax(item.transferSyntaxUID)
        return dataSet
    }

    /// Pixel Data attributes that metadata replaces by a Bulk Data URI.
    static let pixelDataTags: Set<String> = ["7fe00010", "7fe00008", "7fe00009"]

    /// The frames of an instance, one-based, as native little endian bytes
    /// (uncompressed Bulk Data, PS3.18 8.7.3.3.1) or as stored compressed
    /// bit streams.
    static func frames(_ dataSet: DataSet, numbers: [Int], compressed: Bool) throws -> [Data] {
        let description = try DICOMPixelDescription(dataset: dataSet)
        for number in numbers where number < 1 || number > description.numberOfFrames {
            throw DICOMPixelDataError.frameOutOfRange(number, numberOfFrames: description.numberOfFrames)
        }
        if description.isEncapsulated {
            let encapsulated = try DICOMEncapsulatedPixelData(dataset: dataSet)
            return try numbers.map {
                compressed ? try encapsulated.encodedFrame($0 - 1) : try encapsulated.decodedFrame($0 - 1).data
            }
        }
        let native = try DICOMNativePixelData(dataset: dataSet, description: description)
        return try numbers.map { try native.frameData($0 - 1) }
    }
}
