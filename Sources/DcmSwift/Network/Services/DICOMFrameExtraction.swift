import Foundation

/// Native multi-frame Secondary Capture extraction (PS3.4 Y.3.2, Y.3.3).
/// Other SOP Classes and compressed/video sources receive a defined failure.
public enum DICOMFrameExtraction {
    static func failure(_ code: UInt16, _ comment: String) -> DICOMServiceError {
        DICOMServiceError(status: DICOMStatus(code: code), comment: comment)
    }

    /// Expands one of the three frame selectors into increasing, one-based frames.
    public static func frames(_ identifier: DataSet, count: Int, times: [Double]? = nil) throws -> [Int] {
        let selectors = ["SimpleFrameList", "CalculatedFrameList", "TimeRange"].filter { identifier.element(forTagName: $0) != nil }
        guard count > 0, selectors.count == 1 else { throw failure(0xAA04, "exactly one frame selector is required") }
        let selector = selectors[0]
        // Numeric UL and FD values are exposed through the JSON Model so their
        // interpretation does not depend on the source element's byte order.
        let object = try DICOMJSON.object(identifier, options: .init(numbersAsStrings: true))
        let tag = DicomSpec.shared.dataTag(forName: selector)!.code.uppercased()
        let numbers = DICOMQueryMatcher.strings(object[tag] as? [String: Any] ?? [:])
        var frames: [Int] = []
        if selector == "TimeRange" {
            guard numbers.count == 2, let low = Double(numbers[0]), let high = Double(numbers[1]),
                  low.isFinite, high.isFinite, low >= 0, high >= low else { throw failure(0xAA04, "invalid Time Range") }
            guard let times, times.count == count else { throw failure(0xAA03, "frame timing is unavailable") }
            frames = times.enumerated().filter { $0.element >= low && $0.element <= high }.map { $0.offset + 1 }
        } else {
            let parsed = numbers.compactMap(UInt32.init)
            guard !parsed.isEmpty, parsed.count == numbers.count else { throw failure(0xAA04, "invalid frame list") }
            if selector == "SimpleFrameList" {
                guard parsed.count <= 16383, parsed.allSatisfy({ $0 > 0 }),
                      zip(parsed, parsed.dropFirst()).allSatisfy({ $0 < $1 }) else { throw failure(0xAA04, "frame list must strictly increase") }
                frames = parsed.map(Int.init).filter { $0 <= count }
            } else {
                guard parsed.count % 3 == 0 else { throw failure(0xAA04, "calculated list requires triples") }
                var previousEnd: UInt32 = 0
                for i in stride(from: 0, to: parsed.count, by: 3) {
                    let first = parsed[i], last = parsed[i + 1], step = parsed[i + 2]
                    guard first > previousEnd, last >= first, step > 0,
                          last <= count || i + 3 == parsed.count else { throw failure(0xAA04, "invalid calculated frame range") }
                    previousEnd = last
                    if first <= count { frames += stride(from: Int(first), through: min(Int(last), count), by: Int(step)) }
                }
            }
        }
        guard !frames.isEmpty else { throw failure(0xAA00, "no requested frames exist") }
        return frames
    }

    public static func extract(_ item: DICOMRetrieveItem, identifier: DataSet) throws -> DICOMRetrieveItem {
        do { return try extractNative(item, identifier: identifier) }
        catch let error as DICOMServiceError { throw error }
        catch { throw failure(0xAA02, "cannot extract frames: \(error)") }
    }

    private static func extractNative(_ item: DICOMRetrieveItem, identifier: DataSet) throws -> DICOMRetrieveItem {
        let supported = ["1.2.840.10008.5.1.4.1.1.7.1", "1.2.840.10008.5.1.4.1.1.7.2",
                         "1.2.840.10008.5.1.4.1.1.7.3", "1.2.840.10008.5.1.4.1.1.7.4"]
        guard supported.contains(item.sopClassUID) else { throw failure(0xAA01, "frame extraction is supported for multi-frame Secondary Capture") }
        guard DICOMAssociation.isUncompressed(item.transferSyntaxUID) else { throw failure(0xAA02, "compressed frame extraction is not supported") }
        let dataSet = try DICOMDataSetCoding.decode(item.payload.data(), transferSyntax: item.transferSyntaxUID)
        let description = try DICOMPixelDescription(dataset: dataSet)
        let type = supported.firstIndex(of: item.sopClassUID)!
        let validPixels = description.sampleFormat == .integer && !description.isSigned &&
            (type == 0 ? description.bitsAllocated == 1 && description.samplesPerPixel == 1 && description.photometricInterpretation == .monochrome2 :
             type == 1 ? description.bitsAllocated == 8 && description.samplesPerPixel == 1 && description.photometricInterpretation == .monochrome2 :
             type == 2 ? description.bitsAllocated == 16 && description.samplesPerPixel == 1 && description.photometricInterpretation == .monochrome2 :
                         description.bitsAllocated == 8 && description.samplesPerPixel == 3 && description.photometricInterpretation == .rgb)
        guard validPixels, description.bitsAllocated <= 8 || dataSet.element(forTagName: "PixelData")?.vr == .OW else { throw failure(0xAA02, "unsupported Secondary Capture pixel layout") }
        let native = try DICOMNativePixelData(dataset: dataSet, description: description)
        var object = try DICOMJSON.object(dataSet, options: .init(numbersAsStrings: true))
        func strings(_ tag: String) -> [String] { DICOMQueryMatcher.strings(object[tag] as? [String: Any] ?? [:]) }
        // Reject frame-indexed structures whose semantics this extractor cannot
        // rewrite. Enhanced image extraction requires a dedicated implementation.
        let unsupported = ["52009230", "00209161", "54000100",
            "00182001", "00182002", "00182003", "00182004", "00182005", "00182006",
            "00286010", "00286020", "00286022", "00286023", "00286040", "00286100"]
        guard !object.keys.contains(where: { $0.hasPrefix("50") || $0.hasPrefix("60") }),
              !unsupported.contains(where: { object[$0] != nil }) else { throw failure(0xAA02, "unsupported frame-dependent attributes") }
        let pointers = strings("00280009")
        guard !pointers.isEmpty, pointers.allSatisfy({ ["00181063", "00181065"].contains($0.uppercased()) }) else {
            throw failure(0xAA02, "unsupported Frame Increment Pointer")
        }
        var times: [Double]?
        let vector = strings("00181065").compactMap(Double.init)
        if vector.count == description.numberOfFrames, vector.allSatisfy({ $0.isFinite && $0 >= 0 }), vector.first == 0 {
            var total = 0.0
            times = vector.map { total += $0 / 1000; return total }
        } else if let interval = strings("00181063").first.flatMap(Double.init), interval.isFinite, interval > 0 {
            times = (0..<description.numberOfFrames).map { Double($0) * interval / 1000 }
        }
        if times?.allSatisfy({ $0.isFinite }) == false { times = nil }
        let selected = try frames(identifier, count: description.numberOfFrames, times: times)
        guard times != nil else { throw failure(0xAA02, "invalid frame timing") }
        var pixels = Data(count: (selected.count * description.bitsPerFrame + 7) / 8)
        var outputBit = 0
        for frame in selected {
            var bytes = [UInt8](try native.frameData(frame - 1))
            if dataSet.transferSyntax?.byteOrder == .BigEndian, description.bitsAllocated > 8 {
                let width = description.bitsAllocated / 8
                for i in stride(from: 0, to: bytes.count, by: width) { bytes.replaceSubrange(i..<(i + width), with: bytes[i..<(i + width)].reversed()) }
            }
            if description.bitsAllocated == 1 {
                let inputBit = ((frame - 1) * description.bitsPerFrame) % 8
                for bit in 0..<description.bitsPerFrame {
                    if bytes[(inputBit + bit) / 8] & (1 << ((inputBit + bit) % 8)) != 0 { pixels[outputBit / 8] |= 1 << (outputBit % 8) }
                    outputBit += 1
                }
            } else {
                let start = outputBit / 8
                pixels.replaceSubrange(start..<(start + bytes.count), with: bytes)
                outputBit += description.bitsPerFrame
            }
        }
        // Re-encode native frames as little endian. JSON export/import also
        // normalizes every numeric attribute when the original was Big Endian.
        if pixels.count % 2 == 1 { pixels.append(0) }
        object["7FE00010"] = ["vr": description.bitsAllocated <= 8 ? "OB" : "OW", "InlineBinary": pixels.base64EncodedString()]
        object["00280008"] = ["vr": "IS", "Value": [String(selected.count)]]
        object["00080018"] = ["vr": "UI", "Value": [UID.generate()]]
        if let times {
            let offsets = selected.map { times[$0 - 1] }
            let start = offsets[0]
            guard let date = strings("00080023").first, let time = strings("00080033").first,
                  let original = DICOMDateTimeValue.dateTime(date + time) else { throw failure(0xAA02, "timed extraction needs Content Date and Time") }
            let maximum = DICOMDateTimeValue.dateTime("99991231235959.999999")!.upper
            guard original.lower >= 0, original.lower <= maximum,
                  start >= 0, start * 1_000_000 <= Double(maximum - original.lower) else {
                throw failure(0xAA02, "frame timing exceeds DICOM date range")
            }
            let microseconds = original.lower + Int((start * 1_000_000).rounded())
            guard microseconds <= maximum else { throw failure(0xAA02, "rounded timing exceeds DICOM date range") }
            let instant = Date(timeIntervalSince1970: Double(microseconds / 1_000_000) - 62_135_596_800)
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd"; object["00080023"] = ["vr": "DA", "Value": [formatter.string(from: instant)]]
            formatter.dateFormat = "HHmmss"
            let fraction = String(format: "%06d", microseconds % 1_000_000)
            object["00080033"] = ["vr": "TM", "Value": [formatter.string(from: instant) + "." + fraction]]
            if let delay = strings("00181066").first.flatMap(Double.init), delay.isFinite {
                object["00181066"] = ["vr": "DS", "Value": [DICOMSRContentItem.decimalString(delay + start * 1000)]]
            }
            object.removeValue(forKey: "00181063")
            object["00181065"] = ["vr": "DS", "Value": offsets.enumerated().map { i, value in i == 0 ? "0" : DICOMSRContentItem.decimalString((value - offsets[i - 1]) * 1000) }]
            object["00280009"] = ["vr": "AT", "Value": ["00181065"]]
        }
        let query = try DICOMJSON.object(identifier, options: .init(numbersAsStrings: true))
        var provenance = query.filter { ["00081161", "00081162", "00081163"].contains($0.key) }
        provenance["00081167"] = ["vr": "UI", "Value": [item.sopInstanceUID]]
        func append(_ tag: String, item: [String: Any]) {
            var entries = (object[tag] as? [String: Any])?["Value"] as? [[String: Any]] ?? []
            entries.append(item); object[tag] = ["vr": "SQ", "Value": entries]
        }
        append("00081164", item: provenance)
        append("0018A001", item: [
            "0040A170": ["vr": "SQ", "Value": [[
                "00080100": ["vr": "SH", "Value": ["109105"]], "00080102": ["vr": "SH", "Value": ["DCM"]],
                "00080104": ["vr": "LO", "Value": ["Frame Extracting Equipment"]]]]],
            "00080070": ["vr": "LO", "Value": ["DcmSwift"]],
            "00181020": ["vr": "LO", "Value": [DICOMImplementation.versionName]]])
        func stripPrivate(_ attributes: [String: Any]) -> [String: Any] {
            var clean: [String: Any] = [:]
            for (tag, value) in attributes {
                guard let group = UInt16(tag.prefix(4), radix: 16), group % 2 == 0 else { continue }
                if var attribute = value as? [String: Any], attribute["vr"] as? String == "SQ" {
                    attribute["Value"] = (attribute["Value"] as? [[String: Any]] ?? []).map(stripPrivate)
                    clean[tag] = attribute
                } else { clean[tag] = value }
            }
            return clean
        }
        object = stripPrivate(object)
        for tag in ["00287FE0", "7FE00001", "7FE00002", "00209161", "00209162", "00209163", "00209228", "00082142", "00082143", "00180040", "00182140"] { object.removeValue(forKey: tag) }
        return try DICOMRetrieveItem(dataSet: DICOMJSON.dataSet(object))
    }
}
