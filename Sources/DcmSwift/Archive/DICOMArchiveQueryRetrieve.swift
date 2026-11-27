import Foundation

/// Identifier rules for the standard archive information models (PS3.4 C, Y, Z).
enum DICOMArchiveQueryRetrieve {
    static func validate(_ identifier: DataSet, model: String, options: DICOMQueryRetrieveOptions,
                         retrieve: Bool) throws -> String {
        func invalid(_ reason: String) throws -> Never {
            throw DICOMServiceError(status: .identifierDoesNotMatchSOPClass, comment: reason)
        }
        let composite = [DICOMSOPClass.compositeInstanceRootGet, DICOMSOPClass.compositeInstanceRootMove,
                         DICOMSOPClass.compositeInstanceRetrieveWithoutBulkDataGet].contains(model)
        guard (retrieve ? DICOMQueryRetrieveOptions.retrieveModels + [DICOMSOPClass.compositeInstanceRetrieveWithoutBulkDataGet]
                        : DICOMQueryRetrieveOptions.findModels).contains(model) else { try invalid("unsupported information model") }
        if let zone = identifier.string(forTag: "TimezoneOffsetFromUTC"), !zone.isEmpty {
            guard zone.count == 5, zone.first == "+" || zone.first == "-",
                  let hours = Int(zone.dropFirst().prefix(2)), let minutes = Int(zone.suffix(2)),
                  zone.dropFirst().allSatisfy({ $0 >= "0" && $0 <= "9" }), minutes < 60,
                  hours < (zone.first == "-" ? 12 : 14) || (hours == (zone.first == "-" ? 12 : 14) && minutes == 0) else {
                try invalid("invalid Timezone Offset From UTC")
            }
        }
        if identifier.element(forTagName: "QueryRetrieveView") != nil {
            guard options.contains(.enhancedMultiFrameConversion),
                  let view = identifier.string(forTag: "QueryRetrieveView"), DICOMEnhancedMultiFrameConversion.View(rawValue: view) != nil else {
                try invalid("invalid or unnegotiated Query/Retrieve View")
            }
        }
        let level = identifier.string(forTag: "QueryRetrieveLevel") ?? ""
        if composite {
            guard ["IMAGE", "FRAME"].contains(level),
                  model != DICOMSOPClass.compositeInstanceRetrieveWithoutBulkDataGet || level == "IMAGE",
                  identifier.element(forTagName: "SpecificCharacterSet") == nil else { try invalid("invalid Composite Instance Root identifier") }
            try requireUID(identifier, keyword: "SOPInstanceUID", list: level == "IMAGE")
            let allowed: Set<String> = ["QueryRetrieveLevel", "SOPInstanceUID", "SimpleFrameList", "CalculatedFrameList", "TimeRange", "QueryRetrieveView"]
            guard identifier.allElements.allSatisfy({ allowed.contains($0.name) }),
                  level == "FRAME" || identifier.allElements.allSatisfy({ !["SimpleFrameList", "CalculatedFrameList", "TimeRange"].contains($0.name) }) else {
                try invalid("unexpected key in Composite Instance Root identifier")
            }
            return level
        }
        let hierarchy = hierarchy(model)
        guard let depth = hierarchy.firstIndex(where: { $0.level == level }) else { try invalid("invalid Query/Retrieve Level") }
        if !options.contains(.relational) {
            for ancestor in hierarchy.prefix(depth) {
                if !retrieve, identifier.allElements.contains(where: { ancestor.keys.contains($0.name) && $0.name != ancestor.unique }) {
                    try invalid("ancestor query keys must be unique keys")
                }
                if ancestor.unique == "PatientID" {
                    let value = identifier.textValues(forTag: ancestor.unique) ?? []
                    guard value.count == 1, !value[0].isEmpty, !value[0].contains("*"), !value[0].contains("?") else {
                        try invalid("ancestor Patient ID is required")
                    }
                } else { try requireUID(identifier, keyword: ancestor.unique, list: false) }
            }
            if !retrieve {
                let descendants = hierarchy.dropFirst(depth + 1).flatMap(\.keys)
                guard !identifier.allElements.contains(where: { descendants.contains($0.name) }) else {
                    try invalid("keys below query level require relational queries")
                }
            }
        }
        if retrieve {
            if level == "PATIENT" {
                guard let value = identifier.string(forTag: "PatientID"), !value.isEmpty,
                      !value.contains("*"), !value.contains("?"), !value.contains("\\") else { try invalid("Patient ID is required") }
            } else { try requireUID(identifier, keyword: hierarchy[depth].unique, list: true) }
            // Other keys (Patient ID in Study Root, Patient's Name…) are
            // ignored rather than refused, as most archives do: many SCUs
            // send them with a C-MOVE or a C-GET (PS3.4 C.4.2.2.1 asks for
            // unique keys only). `retrievalKeys` leaves them out of matching.
        }
        return level
    }

    /// The levels of an information model, from its root.
    static func hierarchy(_ model: String) -> [(level: String, unique: String, keys: [String])] {
        let patientStudy = [DICOMSOPClass.patientStudyOnlyFind, DICOMSOPClass.patientStudyOnlyGet, DICOMSOPClass.patientStudyOnlyMove].contains(model)
        let studyRoot = [DICOMSOPClass.studyRootFind, DICOMSOPClass.studyRootGet, DICOMSOPClass.studyRootMove].contains(model)
        return Array(DICOMArchive.levels.dropFirst(studyRoot ? 1 : 0).prefix(patientStudy ? 2 : 4))
    }

    /// A retrieval identifier with its unique keys only, those of `level`
    /// and the levels above it in `model`: the others do not take part in
    /// matching.
    static func retrievalKeys(_ identifier: DataSet, model: String, level: String) -> DataSet {
        let hierarchy = hierarchy(model)
        let depth = hierarchy.firstIndex(where: { $0.level == level }) ?? hierarchy.count - 1
        let kept = Set(hierarchy.prefix(depth + 1).map(\.unique) + ["QueryRetrieveLevel", "SpecificCharacterSet", "IssuerOfPatientID", "QueryRetrieveView"])
        let keys = DataSet()
        for keyword in kept {
            guard let values = identifier.textValues(forTag: keyword) else { continue }
            _ = keys.set(value: values.joined(separator: "\\"), forTagName: keyword)
        }
        return keys
    }

    static func requireUID(_ identifier: DataSet, keyword: String, list: Bool) throws {
        let values = identifier.textValues(forTag: keyword) ?? []
        guard !values.isEmpty, list || values.count == 1,
              values.allSatisfy(DICOMUniqueIdentifier.isValid) else {
            throw DICOMServiceError(status: .identifierDoesNotMatchSOPClass, comment: "invalid or missing \(keyword)")
        }
    }

    static func matcher(_ options: DICOMQueryRetrieveOptions) -> DICOMQueryMatcher {
        DICOMQueryMatcher(combinedDateTime: options.contains(.combinedDateTime) ? [("00080020", "00080030")] : [],
            echoed: ["00080052"], fuzzyPersonNames: options.contains(.fuzzyPersonNames),
            timezoneAdjustment: options.contains(.timezoneAdjustment), literalPersonNames: true)
    }

    /// PS3.4 Z.1.3: only these top-level attributes and nested waveform samples.
    /// Icon Image Sequence pixel data and private attributes are retained.
    static func withoutBulkData(_ item: DICOMRetrieveItem) throws -> DICOMRetrieveItem {
        let dataSet = try DICOMDataSetCoding.decode(item.payload.data(), transferSyntax: item.transferSyntaxUID)
        let tags: Set<String> = ["7fe00010", "7fe00008", "7fe00009", "00287fe0", "56000020", "00420011"]
        for element in dataSet.allElements {
            let code = element.tag.code.lowercased()
            let repeating = (element.group.hasPrefix("60") && element.element == "3000") ||
                (element.group.hasPrefix("50") && ["3000", "200c"].contains(element.element.lowercased()))
            if tags.contains(code) || repeating { _ = dataSet.remove(dataElement: element) }
        }
        for waveform in dataSet.sequence(forTagName: "WaveformSequence")?.items ?? [] {
            waveform.elements.removeAll { $0.tag.code.lowercased() == "54001010" }
        }
        // Retaining the original transfer syntax also preserves compressed icon
        // images. No stored bytes or UIDs are changed.
        return try DICOMRetrieveItem(dataSet: dataSet, transferSyntaxUID: item.transferSyntaxUID)
    }
}

extension DICOMArchive {
    /// DIMSE matching with negotiated behavior. Group first so relational
    /// predicates select complete response entities and counts, not fragments.
    func extendedMatches(_ identifier: DataSet, level: String, options: DICOMQueryRetrieveOptions) async throws -> [[Record]] {
        let depth = Self.levels.firstIndex(where: { $0.level == level })!
        let keys = options.contains(.relational) ? Self.indexedKeys : Self.levels[...depth].flatMap(\.keys)
        let allowed = Set(keys.compactMap { Self.tags[$0] } + ["00080052", "00080201"])
        let object = try DICOMJSON.object(identifier, options: .init(numbersAsStrings: true)).filter { allowed.contains($0.key) }
        let matcher = DICOMArchiveQueryRetrieve.matcher(options)
        // Adapters may narrow candidates only with predicates compatible with
        // negotiated matching. Fetch complete entities in a second query so
        // descendant constraints cannot truncate counts or return attributes.
        let candidateQuery = DICOMQuery(identifier: object, matcher: matcher)
        let candidates = try await index.documents(in: .instances, matching: candidateQuery)
        let unique = Self.levels[depth].unique
        let ids = Set(candidates.filter { matcher.match(object, against: $0.attributes) != nil }
            .compactMap { Self.record($0).attributes[unique] })
        if ids.isEmpty { return [] }
        let documents: [DICOMArchiveDocument]
        if candidateQuery.conditions.isEmpty { documents = candidates }
        else {
            let tag = Self.tags[unique]!
            documents = try await index.documents(in: .instances, matching: DICOMQuery(conditions: [
                .init(path: [tag], vr: unique == "PatientID" ? "LO" : "UI", constraint: .equals(Array(ids)))
            ]))
        }
        var groups: [String: [DICOMArchiveDocument]] = [:]
        for document in documents {
            let record = Self.record(document)
            let identity = Self.levels[depth].unique
            let key = (record.attributes[identity] ?? "") + (level == "PATIENT" ? "\u{0}" + (record.attributes["IssuerOfPatientID"] ?? "") : "")
            groups[key, default: []].append(document)
        }
        return groups.keys.sorted().compactMap { key in
            let group = groups[key]!
            guard group.contains(where: { matcher.match(object, against: $0.attributes) != nil }) else { return nil }
            let sorted = group.sorted { ($0.metadata["location"] ?? "") < ($1.metadata["location"] ?? "") }
            let matching = sorted.filter { matcher.match(object, against: $0.attributes) != nil }
            let other = sorted.filter { matcher.match(object, against: $0.attributes) == nil }
            return (matching + other).map(Self.record)
        }
    }

    func extendedFind(_ identifier: DataSet, level: String, options: DICOMQueryRetrieveOptions) async throws -> [DataSet] {
        let groups = Self.matchingModalities(try await extendedMatches(identifier, level: level, options: options),
                                             identifier, level: level)
        let requested = Set(identifier.allElements.map(\.name) + [Self.levels.first(where: { $0.level == level })!.unique])
        return groups.map { group in
            let response = DataSet()
            for key in requested {
                if key == "SpecificCharacterSet" { continue }
                if key == "QueryRetrieveView" {
                    _ = response.set(value: identifier.string(forTag: key) ?? "", forTagName: key)
                    continue
                }
                if let value = Self.value(of: key, in: group, level: level) { _ = response.set(value: value, forTagName: key) }
                else if let element = identifier.element(forTagName: key), element.vr != .SQ { _ = response.set(value: "", forTagName: key) }
            }
            if response.allElements.contains(where: { [.PN, .LO, .SH, .ST, .LT, .UT].contains($0.vr) }) {
                _ = response.set(value: "ISO_IR 192", forTagName: "SpecificCharacterSet")
                // Reset strings after setting the character set so non-ASCII
                // return values are encoded as UTF-8, not default ASCII.
                for key in requested {
                    if let value = Self.value(of: key, in: group, level: level) { _ = response.set(value: value, forTagName: key) }
                }
            }
            return response
        }
    }
}
