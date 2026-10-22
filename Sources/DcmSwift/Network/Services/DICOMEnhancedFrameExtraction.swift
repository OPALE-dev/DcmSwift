import Foundation

extension DICOMFrameExtraction {
    /// Pixel cells are selected unchanged. Independent encapsulated frames are
    /// copied as codestreams; collection codecs may decode losslessly when their
    /// output preserves the source Image Pixel Module.
    static func pixelSubset(_ dataSet: DataSet, frames: [Int]) throws -> (attribute: [String: Any], syntax: String) {
        let description = try DICOMPixelDescription(dataset: dataSet)
        if description.isEncapsulated {
            let encapsulated = try DICOMEncapsulatedPixelData(dataset: dataSet)
            if !DICOMEncapsulatedPixelData.collectionTransferSyntaxUIDs.contains(encapsulated.transferSyntaxUID) {
                var bytes = Data([0xfe, 0xff, 0x00, 0xe0, 0, 0, 0, 0]) // empty Basic Offset Table
                for number in frames {
                    var frame = try encapsulated.encodedFrame(number - 1)
                    if frame.count % 2 != 0 { frame.append(0) }
                    bytes.append(contentsOf: [0xfe, 0xff, 0x00, 0xe0])
                    bytes.append(uint32: UInt32(frame.count), bigEndian: false)
                    bytes.append(frame)
                }
                return (["vr": "OB", "InlineBinary": bytes.base64EncodedString()], encapsulated.transferSyntaxUID)
            }
            let original = ["PhotometricInterpretation", "SamplesPerPixel", "BitsAllocated", "BitsStored", "HighBit", "PixelRepresentation", "PlanarConfiguration"]
            let values = original.map { dataSet.element(forTagName: $0)?.data }
            try DICOMwebTranscoding.decompress(dataSet, from: encapsulated.transferSyntaxUID)
            guard zip(original, values).allSatisfy({ dataSet.element(forTagName: $0.0)?.data == $0.1 }) else {
                throw failure(0xAA02, "collection decoding changes Image Pixel attributes")
            }
            return try pixelSubset(dataSet, frames: frames)
        }
        let native = try DICOMNativePixelData(dataset: dataSet)
        var pixels = Data(count: (frames.count * description.bitsPerFrame + 7) / 8), outputBit = 0
        for frame in frames {
            var bytes = [UInt8](try native.frameData(frame - 1))
            if dataSet.transferSyntax?.byteOrder == .BigEndian, description.bitsAllocated > 8 {
                let width = description.bitsAllocated / 8
                for i in stride(from: 0, to: bytes.count, by: width) { bytes.replaceSubrange(i..<(i + width), with: bytes[i..<(i + width)].reversed()) }
            }
            if description.bitsAllocated == 1 {
                let first = ((frame - 1) * description.bitsPerFrame) % 8
                for bit in 0..<description.bitsPerFrame {
                    if bytes[(first + bit) / 8] & (1 << ((first + bit) % 8)) != 0 { pixels[outputBit / 8] |= 1 << (outputBit % 8) }
                    outputBit += 1
                }
            } else {
                pixels.replaceSubrange(outputBit / 8..<(outputBit / 8 + bytes.count), with: bytes)
                outputBit += description.bitsPerFrame
            }
        }
        if pixels.count % 2 != 0 { pixels.append(0) }
        let vr: String
        switch description.sampleFormat {
        case .integer: vr = description.bitsAllocated <= 8 ? "OB" : "OW"
        case .float32: vr = "OF"
        case .float64: vr = "OD"
        }
        return (["vr": vr, "InlineBinary": pixels.base64EncodedString()], TransferSyntax.explicitVRLittleEndian)
    }

    static func extractEnhanced(_ item: DICOMRetrieveItem, identifier: DataSet) throws -> DICOMRetrieveItem {
        typealias C = DICOMEnhancedMultiFrameConversion
        let dataSet = try DICOMDataSetCoding.decode(item.payload.data(), transferSyntax: item.transferSyntaxUID)
        guard dataSet.string(forTag: "SOPInstanceUID") == item.sopInstanceUID, dataSet.string(forTag: "SOPClassUID") == item.sopClassUID else {
            throw failure(0xAA02, "source DICOM identity mismatch")
        }
        let description = try DICOMPixelDescription(dataset: dataSet)
        var object = try DICOMJSON.object(dataSet, options: .init(numbersAsStrings: true))
        let allFrames = C.items(object, "52009230")
        guard allFrames.count == description.numberOfFrames, C.items(object, "52009229").count == 1,
              !object.keys.contains(where: { $0.hasPrefix("50") || $0.hasPrefix("60") }),
              ["54000100", "00286010", "00286020", "00286040", "00286100"].allSatisfy({ object[$0] == nil }) else {
            throw failure(0xAA02, "invalid or unsupported enhanced frame structure")
        }
        let zone = C.text(object, "00080201")
        let base = DICOMDateTimeValue.dateTime(C.text(object, "00080023") + C.text(object, "00080033") + zone)
        var times: [Double] = []
        if let base {
            for frame in allFrames {
                let content = C.items(frame, "00209111").first ?? [:]
                var value = C.text(content, "00189151")
                if !value.contains("+") && !value.contains("-") { value += zone }
                guard let parsed = DICOMDateTimeValue.dateTime(value) else { times = []; break }
                times.append(Double(parsed.lower - base.lower) / 1_000_000)
            }
        }
        if times.count != description.numberOfFrames {
            let vector = C.values(object, "00181065").compactMap(Double.init)
            if vector.count == description.numberOfFrames, vector.first == 0, vector.allSatisfy({ $0.isFinite && $0 >= 0 }) {
                var total = 0.0; times = vector.map { total += $0 / 1000; return total }
            } else if let interval = C.values(object, "00181063").first.flatMap(Double.init), interval.isFinite, interval > 0 {
                times = (0..<description.numberOfFrames).map { Double($0) * interval / 1000 }
            }
        }
        guard times.allSatisfy({ $0.isFinite }) else { throw failure(0xAA02, "invalid frame timing") }
        let selected = try frames(identifier, count: description.numberOfFrames, times: times.count == description.numberOfFrames ? times : nil)
        var subset = selected.map { allFrames[$0 - 1] }
        // Recompute ordinal dimension indexes while preserving the pointed-to
        // physical/stack attributes and their original values.
        let dimensions = subset.map { C.items($0, "00209111").first.map { C.values($0, "00209157") } ?? [] }
        if let count = dimensions.first?.count, count > 0 {
            guard dimensions.allSatisfy({ $0.count == count }) else { throw failure(0xAA02, "inconsistent dimension index values") }
            let maps = (0..<count).map { dimension -> [String: Int] in
                let values = Set(dimensions.map { $0[dimension] }).sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
                return Dictionary(uniqueKeysWithValues: values.enumerated().map { ($0.element, $0.offset + 1) })
            }
            for i in subset.indices {
                var content = C.items(subset[i], "00209111")[0]
                content["00209157"] = ["vr": "UL", "Value": dimensions[i].enumerated().map { maps[$0.offset][$0.element]! }]
                subset[i]["00209111"] = C.sequence([content])
            }
        }
        let pixels = try pixelSubset(dataSet, frames: selected)
        let pixelTag = description.sampleFormat == .float32 ? "7FE00008" : description.sampleFormat == .float64 ? "7FE00009" : "7FE00010"
        object[pixelTag] = pixels.attribute
        object["52009230"] = C.sequence(subset)
        object["00280008"] = C.attribute("IS", [String(selected.count)])
        object["00080018"] = C.attribute("UI", [UID.generate()])
        // The source's functional-group times remain exact. Content timestamp
        // follows the first selected reference time when that time is available.
        if times.count == description.numberOfFrames, let base {
            let moment = base.lower + Int((times[selected[0] - 1] * 1_000_000).rounded())
            let offset = zone.isEmpty ? 0 : (DICOMDateTimeValue.dateTime("20000101000000" + zone)!.lower - DICOMDateTimeValue.dateTime("20000101000000")!.lower)
            let local = moment - offset
            let date = Date(timeIntervalSince1970: Double(local / 1_000_000) - 62_135_596_800)
            let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.calendar = Calendar(identifier: .gregorian)
            format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "yyyyMMdd"
            object["00080023"] = C.attribute("DA", [format.string(from: date)])
            format.dateFormat = "HHmmss"
            object["00080033"] = C.attribute("TM", [format.string(from: date) + "." + String(format: "%06d", local % 1_000_000)])
        }
        var extraction = C.items(object, "00081164")
        var provenance = try DICOMJSON.object(identifier).filter { ["00081161", "00081162", "00081163"].contains($0.key) }
        provenance["00081167"] = C.attribute("UI", [item.sopInstanceUID]); extraction.append(provenance)
        object["00081164"] = C.sequence(extraction)
        var equipment = C.items(object, "0018A001")
        equipment.append(["0040A170": C.sequence([["00080100": C.attribute("SH", ["109105"]), "00080102": C.attribute("SH", ["DCM"]),
            "00080104": C.attribute("LO", ["Frame Extracting Equipment"])]]), "00080070": C.attribute("LO", ["DcmSwift"]),
            "00181020": C.attribute("LO", [DICOMImplementation.versionName])])
        object["0018A001"] = C.sequence(equipment)
        for tag in ["00287FE0", "7FE00001", "7FE00002", "7FE00003", "00209161", "00209162", "00209163", "00209228", "00200242"] { object.removeValue(forKey: tag) }
        object = strippingPrivate(object)
        let result = try DICOMJSON.dataSet(object)
        let validation = DICOMIODValidator().validate(result)
        guard validation.isValid else { throw failure(0xAA02, "extracted enhanced IOD is invalid: " + validation.findings.prefix(3).map(\.description).joined(separator: "; ")) }
        return try DICOMRetrieveItem(dataSet: result, transferSyntaxUID: pixels.syntax)
    }

    static func strippingPrivate(_ object: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (tag, value) in object {
            guard UInt16(tag.prefix(4), radix: 16).map({ $0 % 2 == 0 }) == true, var attribute = value as? [String: Any] else { continue }
            if let entries = attribute["Value"] as? [[String: Any]], attribute["vr"] as? String == "SQ" {
                attribute["Value"] = entries.map(strippingPrivate)
            }
            result[tag] = attribute
        }
        return result
    }
}
