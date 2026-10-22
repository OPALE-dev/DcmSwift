import Foundation
import Crypto

/// Deterministic, lossless Q/R view conversion (PS3.4 C.3.5).
/// Unsupported source/reference structures fail the view atomically.
public enum DICOMEnhancedMultiFrameConversion {
    public enum View: String, Sendable { case classic = "CLASSIC", enhanced = "ENHANCED" }
    typealias Object = [String: Any]
    struct Target {
        var uid: String
        var sopClass: String
        var sourceFrame: Int?
        var targetFrame: Int?
    }
    static let bodyParts: [String: [String: String]] = {
        guard let url = Bundle.module.url(forResource: "dicom-body-parts-2026d", withExtension: "json"),
              let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? Object else { return [:] }
        return object["entries"] as? [String: [String: String]] ?? [:]
    }()
    static let classicClasses = ["1.2.840.10008.5.1.4.1.1.2", "1.2.840.10008.5.1.4.1.1.4", "1.2.840.10008.5.1.4.1.1.128"]
    static let legacyClasses = ["1.2.840.10008.5.1.4.1.1.2.2", "1.2.840.10008.5.1.4.1.1.4.4", "1.2.840.10008.5.1.4.1.1.128.1"]
    static let trueClasses = ["1.2.840.10008.5.1.4.1.1.2.1", "1.2.840.10008.5.1.4.1.1.4.1", "1.2.840.10008.5.1.4.1.1.130"]
    static func error(_ message: String) -> DICOMServiceError { .init(status: .unableToProcess, comment: message) }
    static func values(_ object: Object, _ tag: String) -> [String] { DICOMQueryMatcher.strings(object[tag] as? Object ?? [:]) }
    static func text(_ object: Object, _ tag: String) -> String { values(object, tag).first ?? "" }
    static func sequence(_ items: [Object]) -> Object { ["vr": "SQ", "Value": items] }
    static func items(_ object: Object, _ tag: String) -> [Object] { (object[tag] as? Object)?["Value"] as? [Object] ?? [] }
    static func attribute(_ vr: String, _ values: [String]) -> Object { values.isEmpty ? ["vr": vr] : ["vr": vr, "Value": values] }
    static func canonical(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]) }

    /// UUID-derived namespace, with an RFC 9562 version-8 payload from SHA-256.
    /// The decimal representation is valid on platforms without UInt128.
    static func uid(_ identity: String) -> String {
        var bytes = Array(SHA256.hash(data: Data(("DcmSwift.QR.C35.v1\u{0}" + identity).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80; bytes[8] = (bytes[8] & 0x3f) | 0x80
        var digits = [0]
        for byte in bytes {
            var carry = Int(byte)
            for i in digits.indices { let value = digits[i] * 256 + carry; digits[i] = value % 10; carry = value / 10 }
            while carry > 0 { digits.append(carry % 10); carry /= 10 }
        }
        return "2.25." + digits.reversed().map(String.init).joined()
    }

    /// Converts the complete supplied scope before callers apply query keys.
    /// Include all known objects for each affected patient, including non-images.
    public static func convert(_ instances: [DICOMRetrieveItem], to view: View) throws -> [DICOMRetrieveItem] {
        var sources: [String: Object] = [:], sourceItems: [String: DICOMRetrieveItem] = [:]
        for instance in instances {
            guard sources[instance.sopInstanceUID] == nil else { throw error("duplicate SOP Instance UID in conversion scope") }
            let dataSet = try DICOMDataSetCoding.decode(instance.payload.data(), transferSyntax: instance.transferSyntaxUID)
            guard dataSet.string(forTag: "SOPClassUID") == instance.sopClassUID,
                  dataSet.string(forTag: "SOPInstanceUID") == instance.sopInstanceUID else { throw error("source DICOM identity mismatch") }
            let object = try DICOMJSON.object(dataSet, options: .init(numbersAsStrings: true))
            guard !contains(object, tag: "04000500") else { throw error("encrypted attributes cannot be converted without decryption") }
            sources[instance.sopInstanceUID] = object; sourceItems[instance.sopInstanceUID] = instance
        }
        var mapping: [String: [Target]] = [:], output: [String: Object] = [:]
        var changedSeries = Set<String>()
        if view == .enhanced {
            var groups: [Data: [String]] = [:]
            for id in sources.keys.sorted() {
                let source = sources[id]!
                guard classicClasses.contains(text(source, "00080016")) else { continue }
                let keys = ["00100020", "00100021", "00100010", "00100030", "00100040", "00080201", "0020000D", "0020000E", "00200052", "00080016", "00280010", "00280011",
                            "00280002", "00280004", "00280100", "00280101", "00280102", "00280103", "00280006", "00280120", "00280121", "00280034", "00400275"]
                var invariantKeys = keys
                let invariantModules: Set<String> = ["Patient", "Clinical Trial Subject", "General Study", "Patient Study", "Clinical Trial Study", "Frame of Reference", "Synchronization"]
                if let iod = DICOMIODSpecification.shared.iod(forSOPClass: text(source, "00080016")) {
                    for module in iod.modules where invariantModules.contains(module.name) {
                        if let table = module.table { invariantKeys += DICOMIODSpecification.shared.tree(table).map(\.tag) }
                    }
                }
                let key = try canonical(source.filter { invariantKeys.contains($0.key) })
                groups[key, default: []].append(id)
            }
            for ids in groups.values {
                let ordered = ids.sorted { a, b in
                    let x = Int(text(sources[a]!, "00200013")) ?? 0, y = Int(text(sources[b]!, "00200013")) ?? 0
                    return x == y ? a < b : x < y
                }
                let result = try enhance(ordered.map { sources[$0]! }, instances: ordered.map { sourceItems[$0]! })
                let newID = text(result, "00080018")
                output[newID] = result
                for (index, id) in ordered.enumerated() {
                    mapping[id] = [Target(uid: newID, sopClass: text(result, "00080016"), targetFrame: index + 1)]
                    changedSeries.insert(text(sources[id]!, "0020000E"))
                }
            }
        } else {
            for id in sources.keys.sorted() {
                let source = sources[id]!
                guard (legacyClasses + trueClasses).contains(text(source, "00080016")) else { continue }
                let results = try classic(source, instance: sourceItems[id]!)
                mapping[id] = results.enumerated().map { index, object in
                    Target(uid: text(object, "00080018"), sopClass: text(object, "00080016"), sourceFrame: index + 1)
                }
                for object in results { output[text(object, "00080018")] = object }
                changedSeries.insert(text(source, "0020000E"))
            }
        }
        // Transitive reference closure, including cycles and every member of a
        // changed series. No dependent presentation/SR object is omitted.
        var grew = true
        while grew {
            grew = false
            let changedUIDs = Set(mapping.keys).union(changedSeries)
            for id in sources.keys.sorted() where mapping[id] == nil {
                let source = sources[id]!, series = text(source, "0020000E")
                if changedSeries.contains(series) || references(source, any: changedUIDs) {
                    let target = uid(view.rawValue + ":dependent:" + id)
                    mapping[id] = [Target(uid: target, sopClass: text(source, "00080016"))]
                    var converted = source
                    converted["00080018"] = attribute("UI", [target])
                    converted["0020000E"] = attribute("UI", [uid(view.rawValue + ":series:" + series)])
                    converted["00209172"] = sequence([reference(source)])
                    contribute(&converted, description: "Updated UID references during Legacy Enhanced Classic conversion")
                    output[target] = converted
                    changedSeries.insert(series); grew = true
                }
            }
        }
        let seriesMap = Dictionary(uniqueKeysWithValues: changedSeries.map { ($0, uid(view.rawValue + ":series:" + $0)) })
        var result: [DICOMRetrieveItem] = []
        for id in sources.keys.sorted() where mapping[id] == nil { result.append(sourceItems[id]!) }
        for id in output.keys.sorted() {
            if contains(output[id]!, tag: "0040DB73"), mapping.values.contains(where: { $0.count > 1 }) {
                throw error("by-reference SR content needs content identifier remapping")
            }
            var object = try rewrite(output[id]!, mapping: mapping, series: seriesMap)
            if let originalSeries = values(object, "0020000E").first, let newSeries = seriesMap[originalSeries] {
                object["0020000E"] = attribute("UI", [newSeries])
            }
            removeInvalidated(&object)
            fillMandatoryEmptyAttributes(&object)
            let dataSet = try DICOMJSON.dataSet(object)
            let validation = DICOMIODValidator().validate(dataSet)
            guard validation.isValid else {
                throw error("converted IOD is invalid: " + validation.findings.prefix(4).map(\.description).joined(separator: "; "))
            }
            result.append(try DICOMRetrieveItem(dataSet: dataSet))
        }
        return result.sorted { $0.sopInstanceUID < $1.sopInstanceUID }
    }

    static func contains(_ object: Object, tag: String) -> Bool {
        object[tag] != nil || object.values.contains { value in
            guard let a = value as? Object, let entries = a["Value"] as? [Object] else { return false }
            return entries.contains { contains($0, tag: tag) }
        }
    }
    static func references(_ object: Object, any changed: Set<String>) -> Bool {
        for (tag, value) in object where tag != "00209172" && tag != "00080018" {
            guard let a = value as? Object else { continue }
            if a["vr"] as? String == "UI", !Set(DICOMQueryMatcher.strings(a)).isDisjoint(with: changed) { return true }
            if let entries = a["Value"] as? [Object], entries.contains(where: { references($0, any: changed) }) { return true }
        }
        return false
    }
    static func reference(_ source: Object, frame: Int? = nil) -> Object {
        var result: Object = ["00081150": attribute("UI", [text(source, "00080016")]), "00081155": attribute("UI", [text(source, "00080018")])]
        if let frame { result["00081160"] = attribute("IS", [String(frame)]) }
        return result
    }
    static func contribute(_ object: inout Object, description: String) {
        var equipment = items(object, "0018A001")
        equipment.append(["0040A170": sequence([["00080100": attribute("SH", ["109106"]), "00080102": attribute("SH", ["DCM"]),
            "00080104": attribute("LO", ["Enhanced Multi-frame Conversion Equipment"])]]),
            "00080070": attribute("LO", ["DcmSwift"]), "00181020": attribute("LO", [DICOMImplementation.versionName]),
            "0018A003": attribute("ST", [description])])
        object["0018A001"] = sequence(equipment)
    }
    static func removeInvalidated(_ object: inout Object) {
        for (tag, value) in object {
            guard var attribute = value as? Object, attribute["vr"] as? String == "SQ", var entries = attribute["Value"] as? [Object] else { continue }
            for i in entries.indices { removeInvalidatedSignatures(&entries[i]) }
            attribute["Value"] = entries; object[tag] = attribute
        }
        for tag in ["FFFAFFFA", "4FFE0001", "00209161", "00209162", "00209163", "00209228", "00200242", "7FE00001", "7FE00002", "7FE00003"] { object.removeValue(forKey: tag) }
    }

    static func removeInvalidatedSignatures(_ object: inout Object) {
        object.removeValue(forKey: "FFFAFFFA"); object.removeValue(forKey: "4FFE0001")
        for (tag, value) in object {
            guard var attribute = value as? Object, attribute["vr"] as? String == "SQ", var entries = attribute["Value"] as? [Object] else { continue }
            for i in entries.indices { removeInvalidatedSignatures(&entries[i]) }
            attribute["Value"] = entries; object[tag] = attribute
        }
    }

    /// Type 2 permits an explicitly unknown value; Type 1 is never invented.
    static func fillMandatoryEmptyAttributes(_ object: inout Object) {
        let specification = DICOMIODSpecification.shared
        guard let iod = specification.iod(forSOPClass: text(object, "00080016")) else { return }
        for module in iod.modules where module.usage == "M" {
            guard let table = module.table else { continue }
            for node in specification.tree(table) where node.type == "2" && object[node.tag] == nil {
                guard case .unconditional = node.inclusion,
                      let vr = DicomSpec.shared.vrForTag(withCode: node.tag.lowercased()) else { continue }
                object[node.tag] = ["vr": "\(vr)"]
            }
        }
    }

    static func dateAndTime(_ dateTime: String, zone: String) -> (date: String, time: String)? {
        var input = dateTime
        if !input.contains("+") && !input.contains("-") { input += zone }
        // Do not manufacture precision for a partially specified DT.
        guard dateTime.prefix(14).allSatisfy({ $0 >= "0" && $0 <= "9" }), dateTime.count >= 14,
              let instant = DICOMDateTimeValue.dateTime(input),
              let local = DICOMDateTimeValue.dateTime("20000101000000" + zone),
              let utc = DICOMDateTimeValue.dateTime("20000101000000") else { return nil }
        let microseconds = instant.lower + utc.lower - local.lower
        let date = Date(timeIntervalSince1970: Double(microseconds / 1_000_000) - 62_135_596_800)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"; let day = formatter.string(from: date)
        formatter.dateFormat = "HHmmss"
        let fractionDigits = dateTime.split(separator: ".", maxSplits: 1).dropFirst().first.map { $0.prefix { $0 >= "0" && $0 <= "9" }.count } ?? 0
        let suffix = fractionDigits == 0 ? "" : "." + String(String(format: "%06d", microseconds % 1_000_000).prefix(fractionDigits))
        return (day, formatter.string(from: date) + suffix)
    }

    static func native(_ instance: DICOMRetrieveItem) throws -> DataSet {
        let dataSet = try DICOMDataSetCoding.decode(instance.payload.data(), transferSyntax: instance.transferSyntaxUID)
        if !DICOMAssociation.isUncompressed(instance.transferSyntaxUID) {
            try DICOMwebTranscoding.decompress(dataSet, from: instance.transferSyntaxUID)
        }
        return dataSet
    }

    static func enhance(_ sources: [Object], instances: [DICOMRetrieveItem]) throws -> Object {
        let first = sources[0], kind = classicClasses.firstIndex(of: text(first, "00080016"))!
        guard sources.allSatisfy({ !$0.keys.contains { $0.hasPrefix("60") || $0.hasPrefix("50") } && $0["00700001"] == nil }) else {
            throw error("overlay/curve/graphic conversion requires a qualified presentation converter")
        }
        let dataSets = try instances.map(native)
        let descriptions = try dataSets.map(DICOMPixelDescription.init(dataset:))
        guard descriptions.allSatisfy({ $0.numberOfFrames == 1 && $0 == descriptions[0] }),
              descriptions[0].photometricInterpretation == .monochrome2 else { throw error("incompatible classic pixel descriptions") }
        var pixels = Data()
        for dataSet in dataSets {
            var bytes = try DICOMNativePixelData(dataset: dataSet).frameData(0)
            if dataSet.transferSyntax?.byteOrder == .BigEndian, descriptions[0].bitsAllocated > 8 {
                let width = descriptions[0].bitsAllocated / 8
                for i in stride(from: 0, to: bytes.count, by: width) { bytes.replaceSubrange(i..<(i + width), with: bytes[i..<(i + width)].reversed()) }
            }
            pixels.append(bytes)
        }
        if pixels.count % 2 != 0 { pixels.append(0) }
        var result = first
        let sourceIDs = sources.map { text($0, "00080018") }.sorted().joined(separator: "\u{0}")
        result["00080016"] = attribute("UI", [legacyClasses[kind]])
        result["00080018"] = attribute("UI", [uid("ENHANCED:images:" + sourceIDs)])
        result["0020000E"] = attribute("UI", [uid("ENHANCED:series:" + text(first, "0020000E"))])
        result["00280008"] = attribute("IS", [String(sources.count)])
        result["00200013"] = attribute("IS", ["1"])
        result["7FE00010"] = ["vr": descriptions[0].bitsAllocated > 8 ? "OW" : "OB", "InlineBinary": pixels.base64EncodedString()]
        result["20500020"] = attribute("CS", ["IDENTITY"])
        if result["00400555"] == nil { result["00400555"] = sequence([]) }
        // Only equal attributes may remain shared at the top level.
        var shared: Object = [:]
        let excluded: Set<String> = ["7FE00010", "00080018", "00209172", "0018A001"]
        for (tag, value) in first where !excluded.contains(tag) {
            if try sources.dropFirst().allSatisfy({ try canonical($0[tag] ?? NSNull()) == canonical(value) }) { shared[tag] = value }
            else { result.removeValue(forKey: tag) }
        }
        // Required multi-frame timestamps come from source content/acquisition,
        // never from the wall clock.
        let contentSources = sources.filter { !text($0, "00080023").isEmpty && !text($0, "00080033").isEmpty }
        guard let earliest = contentSources.min(by: { text($0, "00080023") + text($0, "00080033") < text($1, "00080023") + text($1, "00080033") }) else { throw error("source content timestamp missing") }
        result["00080023"] = earliest["00080023"]; result["00080033"] = earliest["00080033"]
        if let earliestSeries = sources.filter({ !text($0, "00080021").isEmpty }).min(by: { text($0, "00080021") + text($0, "00080031") < text($1, "00080021") + text($1, "00080031") }) {
            result["00080021"] = earliestSeries["00080021"]; result["00080031"] = earliestSeries["00080031"]
        }
        var frames: [Object] = []
        for source in sources {
            var fg: Object = [:]
            func macro(_ tag: String, _ keys: [String], mandatory: Bool = false) {
                let content = source.filter { keys.contains($0.key) }
                if mandatory || !content.isEmpty { fg[tag] = sequence([content]) }
            }
            macro("00289110", ["00280030", "00180050", "00180088"], mandatory: true)
            macro("00209113", ["00200032"], mandatory: true)
            macro("00209116", ["00200037"], mandatory: true)
            var content: Object = [:]
            if var dt = values(source, "0008002A").first {
                if !dt.contains("+") && !dt.contains("-") { dt += text(source, "00080201") }
                content["00189074"] = attribute("DT", [dt]); content["00189151"] = content["00189074"]
            }
            else if !text(source, "00080022").isEmpty, !text(source, "00080032").isEmpty {
                content["00189074"] = attribute("DT", [text(source, "00080022") + text(source, "00080032") + text(source, "00080201")])
                content["00189151"] = content["00189074"]
            }
            fg["00209111"] = sequence([content])
            var frameType = values(source, "00080008")
            guard frameType.count >= 2 else { throw error("source Image Type missing") }
            while frameType.count < 4 { frameType.append(frameType.count == 2 ? "OTHER" : "NONE") }
            let calculation = frameType[0] == "ORIGINAL" ? "NONE" : "UNKNOWN"
            if frameType[0] != "ORIGINAL", frameType[3] == "NONE", values(source, "00080008").count < 4 { frameType[3] = "UNKNOWN" }
            let volumetric = frameType.contains("LOCALIZER") ? "SAMPLED" : "VOLUME"
            fg[["00189329", "00189226", "00189751"][kind]] = sequence([["00089007": attribute("CS", frameType),
                "00089205": attribute("CS", ["MONOCHROME"]), "00089206": source["00089206"] ?? attribute("CS", [volumetric]), "00089207": source["00089207"] ?? attribute("CS", [calculation])]])
            var transform = source.filter { ["00281052", "00281053", "00281054"].contains($0.key) }
            if !transform.isEmpty || kind != 1 {
                guard transform["00281052"] != nil, transform["00281053"] != nil else { throw error("source rescale transform missing") }
                if transform["00281054"] == nil { transform["00281054"] = attribute("LO", [kind == 0 ? "HU" : "US"]) }
                fg["00289145"] = sequence([transform])
            }
            macro("00289132", ["00281050", "00281051", "00281055", "00281056", "00283010"], mandatory: kind != 1)
            if kind != 1, text(source, "00281050").isEmpty || text(source, "00281051").isEmpty {
                guard text(source, "00281050").isEmpty && text(source, "00281051").isEmpty,
                      let slope = Double(text(source, "00281053")), let intercept = Double(text(source, "00281052")),
                      slope.isFinite, slope != 0, intercept.isFinite else { throw error("incomplete source VOI/rescale") }
                let range = descriptions[0].storedValueRange
                let a = Double(range.lowerBound) * slope + intercept, b = Double(range.upperBound) * slope + intercept
                let center = (min(a,b) + max(a,b) + 1) / 2, width = abs(b-a) + 1
                guard center.isFinite, width.isFinite else { throw error("VOI range overflow") }
                var voi = items(fg, "00289132").first ?? [:]
                voi["00281050"] = attribute("DS", [DICOMSRContentItem.decimalString(center)])
                voi["00281051"] = attribute("DS", [DICOMSRContentItem.decimalString(width)])
                voi["00281055"] = attribute("LO", ["Full representable modality range"])
                fg["00289132"] = sequence([voi])
            }
            if let references = source["00082112"] {
                var derivation: Object = ["00082112": references]
                for tag in ["00082111", "00089215"] where source[tag] != nil { derivation[tag] = source[tag] }
                fg["00089124"] = sequence([derivation])
            }
            macro("00081140", ["00081140"])
            if let reference = source["00081140"] { fg["00081140"] = reference }
            if let event = source["00083010"] { fg["00189477"] = sequence([["00083010": event]]) }
            var anatomy = source["00082218"]
            if anatomy == nil, let code = bodyParts[text(source, "00180015")] {
                anatomy = sequence([["00080100": attribute("SH", [code["value"]!]), "00080102": attribute("SH", [code["scheme"]!]),
                    "00080104": attribute("LO", [code["meaning"]!])]])
            }
            if let anatomy {
                fg["00209071"] = sequence([["00082218": anatomy, "00209072": source["00200062"] ?? attribute("CS", ["U"])]])
            }
            // Populate optional macros whose standard attributes are available.
            for module in DICOMIODSpecification.shared.iod(forSOPClass: legacyClasses[kind])!.functionalGroups {
                guard let table = module.table.flatMap(DICOMIODSpecification.shared.table),
                      let tag = table.entries.first?.tag, fg[tag] == nil,
                      !["00209170", "00209171", "00209172", "00089124"].contains(tag) else { continue }
                if let value = source[tag] { fg[tag] = value; continue }
                var keys = table.entries.filter { $0.depth == 1 }.compactMap(\.tag)
                for include in table.entries where include.depth == 1 {
                    if let nested = include.include.flatMap(DICOMIODSpecification.shared.table) { keys += nested.entries.filter { $0.depth == 0 }.compactMap(\.tag) }
                }
                let content = source.filter { keys.contains($0.key) }
                if !content.isEmpty { fg[tag] = sequence([content]) }
            }
            var remaining = source.filter { !excluded.contains($0.key) && shared[$0.key] == nil }
            if let history = source["0018A001"] { remaining["0018A001"] = history }
            fg["00209171"] = sequence([remaining])
            fg["00209172"] = sequence([reference(source)])
            frames.append(fg)
        }
        let types = frames.compactMap { items($0, ["00189329", "00189226", "00189751"][kind]).first?["00089007"] as? Object }
        if let firstType = types.first {
            let common = DICOMQueryMatcher.strings(firstType)
            let merged = common.indices.map { index in types.allSatisfy { DICOMQueryMatcher.strings($0)[index] == common[index] } ? common[index] : "MIXED" }
            result["00080008"] = attribute("CS", merged)
        }
        // Empty legacy PET orientation attributes carry no information and
        // must not accidentally activate the enhanced Type 1 orientation module.
        if items(result, "00540410").isEmpty { result.removeValue(forKey: "00540410") }
        else {
            guard !items(result, "00540414").isEmpty else { throw error("enhanced patient/equipment orientation is unavailable") }
            result["30100030"] = result["00540414"]
        }
        result.removeValue(forKey: "00540414")
        result["00200013"] = attribute("IS", ["1"])
        result["00089205"] = attribute("CS", ["MONOCHROME"])
        for tag in ["00089206", "00089207"] {
            let values = frames.compactMap { items($0, ["00189329", "00189226", "00189751"][kind]).first.map { text($0, tag) } }
            result[tag] = attribute("CS", [Set(values).count == 1 ? values[0] : "MIXED"])
        }
        result["52009229"] = sequence([["00209170": sequence([shared])]])
        result["52009230"] = sequence(frames)
        // Consistent equipment history is retained; differing source histories
        // remain in the unassigned per-frame attributes, rather than being lost.
        if try sources.dropFirst().contains(where: { try canonical($0["0018A001"] ?? NSNull()) != canonical(first["0018A001"] ?? NSNull()) }) { result.removeValue(forKey: "0018A001") }
        contribute(&result, description: "Legacy Enhanced Image created from Classic Images")
        return result
    }

    static func classic(_ source: Object, instance: DICOMRetrieveItem) throws -> [Object] {
        let sopClass = text(source, "00080016")
        let kind = legacyClasses.firstIndex(of: sopClass) ?? trueClasses.firstIndex(of: sopClass)!
        let dataSet = try native(instance), description = try DICOMPixelDescription(dataset: dataSet)
        let native = try DICOMNativePixelData(dataset: dataSet)
        let shared = items(source, "52009229").first ?? [:], frames = items(source, "52009230")
        guard frames.count == description.numberOfFrames else { throw error("per-frame functional group count mismatch") }
        var result: [Object] = []
        for frame in 0..<description.numberOfFrames {
            var object = source
            func flatten(_ fg: Object) throws {
                for (tag, value) in fg where tag != "00209172" {
                    guard let entries = (value as? Object)?["Value"] as? [Object] else { continue }
                    if ["00209170", "00209171"].contains(tag) {
                        if let attributes = entries.first { for (key, value) in attributes { object[key] = value } }
                    } else if let attributes = entries.first {
                        for (key, value) in attributes { object[key] = value }
                    }
                }
            }
            try flatten(shared); try flatten(frames[frame])
            if let type = object["00089007"] { object["00080008"] = type }
            if let dt = values(object, "00189074").first ?? values(object, "00189151").first {
                object["0008002A"] = attribute("DT", [dt])
                if let fields = dateAndTime(dt, zone: text(source, "00080201")) {
                    object["00080022"] = attribute("DA", [fields.date]); object["00080032"] = attribute("TM", [fields.time])
                }
            }
            var pixels = try native.frameData(frame)
            if dataSet.transferSyntax?.byteOrder == .BigEndian, description.bitsAllocated > 8 {
                let width = description.bitsAllocated / 8
                for i in stride(from: 0, to: pixels.count, by: width) { pixels.replaceSubrange(i..<(i + width), with: pixels[i..<(i + width)].reversed()) }
            }
            if pixels.count % 2 != 0 { pixels.append(0) }
            object["7FE00010"] = ["vr": description.bitsAllocated > 8 ? "OW" : "OB", "InlineBinary": pixels.base64EncodedString()]
            object["00080016"] = attribute("UI", [classicClasses[kind]])
            object["00080018"] = attribute("UI", [uid("CLASSIC:image:" + instance.sopInstanceUID + ":" + String(frame + 1))])
            object["0020000E"] = attribute("UI", [uid("CLASSIC:series:" + text(source, "0020000E"))])
            object["00200013"] = attribute("IS", [String(frame + 1)])
            for tag in ["52009229", "52009230", "00280008", "00280009", "00209221", "00209222", "00209311", "00089007"] { object.removeValue(forKey: tag) }
            var equipment = items(source, "0018A001")
            for history in items(object, "0018A001") {
                if try !equipment.contains(where: { try canonical($0) == canonical(history) }) { equipment.append(history) }
            }
            if !equipment.isEmpty { object["0018A001"] = sequence(equipment) }
            object["00209172"] = sequence([reference(source, frame: frame + 1)])
            contribute(&object, description: "Classic Image created from Enhanced Image")
            result.append(object)
        }
        return result
    }

    static func rewrite(_ source: Object, mapping: [String: [Target]], series: [String: String]) throws -> Object {
        var object = source
        if ["SCOORD", "SCOORD3D", "TCOORD"].contains(text(source, "0040A040")) {
            for content in items(source, "0040A730") {
                for reference in items(content, "00081199") {
                    if let targets = mapping[text(reference, "00081155")], targets.count > 1,
                       values(reference, "00081160").count != 1 { throw error("coordinate SR reference expansion is ambiguous") }
                }
            }
        }
        if let targets = mapping[text(source, "00081155")] {
            let selected = values(source, "00081160").compactMap(Int.init)
            let applicable = targets.filter { $0.sourceFrame == nil || selected.isEmpty || selected.contains($0.sourceFrame!) }
            guard applicable.count == 1 else { throw error("multi-target image reference needs sequence expansion") }
            let target = applicable[0]
            object["00081155"] = attribute("UI", [target.uid]); object["00081150"] = attribute("UI", [target.sopClass])
            if let frame = target.targetFrame { object["00081160"] = attribute("IS", [String(frame)]) }
            else { object.removeValue(forKey: "00081160") }
        }
        for (tag, value) in object where tag != "00209172" && tag != "00080018" && tag != "00081155" && tag != "00081150" {
            guard UInt16(tag.prefix(4), radix: 16).map({ $0 % 2 == 0 }) == true, var a = value as? Object else { continue }
            if let entries = a["Value"] as? [Object] {
                var rewritten: [Object] = []
                for entry in entries {
                    let referenceItems = items(entry, "00081199")
                    if tag == "0040A730", ["IMAGE", "COMPOSITE"].contains(text(entry, "0040A040")), referenceItems.count == 1,
                       let targets = mapping[text(referenceItems[0], "00081155")], targets.count > 1 {
                        let selected = values(referenceItems[0], "00081160").compactMap(Int.init)
                        let applicable = targets.filter { selected.isEmpty || $0.sourceFrame.map(selected.contains) == true }
                        guard !applicable.isEmpty else { throw error("SR referenced frame is outside source image") }
                        for target in applicable {
                            var content = entry, reference = referenceItems[0]
                            reference["00081160"] = attribute("IS", [String(target.sourceFrame!)])
                            content["00081199"] = sequence([reference])
                            rewritten.append(try rewrite(content, mapping: mapping, series: series))
                        }
                        continue
                    }
                    if let targets = mapping[text(entry, "00081155")], targets.count > 1 {
                        let selected = values(entry, "00081160").compactMap(Int.init)
                        let applicable = targets.filter { selected.isEmpty || $0.sourceFrame.map(selected.contains) == true }
                        guard !applicable.isEmpty else { throw error("referenced frame is outside the source image") }
                        for target in applicable {
                            var single = entry
                            single["00081160"] = attribute("IS", [String(target.sourceFrame!)])
                            rewritten.append(try rewrite(single, mapping: mapping, series: series))
                        }
                    } else { rewritten.append(try rewrite(entry, mapping: mapping, series: series)) }
                }
                a["Value"] = rewritten; object[tag] = a
            } else if a["vr"] as? String == "UI" {
                var replacements: [String] = []
                for value in DICOMQueryMatcher.strings(a) {
                    if let mapped = series[value] { replacements.append(mapped) }
                    else if let targets = mapping[value] {
                        guard targets.count == 1 else { throw error("ambiguous non-image UID reference") }
                        replacements.append(targets[0].uid)
                    } else { replacements.append(value) }
                }
                a["Value"] = replacements; object[tag] = a
            }
        }
        return object
    }
}
