import XCTest
@testable import DcmSwift

final class DcmSwiftQueryRetrieveExtensionTests: XCTestCase {
    typealias W = DcmSwiftWorkflowTests
    let explicit = TransferSyntax.explicitVRLittleEndian
    let sc = "1.2.840.10008.5.1.4.1.1.7.2"

    func context(_ model: String, options: DICOMQueryRetrieveOptions = []) -> DICOMServiceContext {
        DICOMServiceContext(callingAETitle: "SCU", calledAETitle: "SCP", remoteAddress: "localhost", userIdentity: nil,
            presentationContext: .init(id: 1, abstractSyntax: model, transferSyntax: explicit),
            queryRetrieveOptions: options, cancelled: { false })
    }
    func identifier(_ level: String = "STUDY", _ attributes: [String: String] = [:]) -> DataSet {
        let result = DataSet(); _ = result.set(value: level, forTagName: "QueryRetrieveLevel")
        for (key, value) in attributes { _ = result.set(value: value, forTagName: key) }
        return result
    }
    func testSOPSpecificNegotiationAndUnadvertisedCapabilities() throws {
        let all = DICOMQueryRetrieveOptions(rawValue: 127)
        XCTAssertEqual(try all.negotiation(for: DICOMSOPClass.studyRootFind).applicationInformation, [1,1,1,1,1,1,1])
        XCTAssertEqual(try all.negotiation(for: DICOMSOPClass.studyRootGet).applicationInformation, [1,1])
        XCTAssertEqual(try all.negotiation(for: DICOMSOPClass.compositeInstanceRetrieveWithoutBulkDataGet).applicationInformation, [0,1])
        XCTAssertEqual(try all.negotiation(for: DICOMSOPClass.compositeInstanceRootGet).applicationInformation, [0,1])
        let common = DICOMCommonExtendedNegotiation(sopClassUID: sc, serviceClassUID: "1.2.840.10008.4.2")
        let model = DICOMSOPClass.studyRootFind
        var request = DICOMAssociateRequest(calledAETitle: "SCP", callingAETitle: "SCU",
            presentationContexts: [.init(id: 1, abstractSyntax: model, transferSyntaxes: [explicit])],
            userInformation: .init(extendedNegotiations: [try all.negotiation(for: model)]))
        let policy = DICOMAcceptorPolicy(aeTitle: "SCP", abstractSyntaxes: [model: .init(transferSyntaxes: [explicit], queryRetrieveOptions: [.relational, .combinedDateTime])])
        request.userInformation.commonExtendedNegotiations = [common]
        let (accept, negotiated) = try DICOMAssociationNegotiator.respond(to: request, policy: policy).get()
        XCTAssertEqual(negotiated.commonExtendedNegotiations, [common])
        XCTAssertTrue(accept.userInformation.commonExtendedNegotiations.isEmpty, "Common Extended Negotiation has no AC reply")
        XCTAssertEqual(accept.userInformation.extendedNegotiations.first?.applicationInformation, [1,1,0,0,0,0,0])
        XCTAssertEqual(negotiated.queryRetrieveOptions(for: model), [.relational, .combinedDateTime])
        XCTAssertEqual(try DICOMAssociationNegotiator.negotiated(request: request, accept: accept), negotiated)
        request.userInformation.extendedNegotiations[0].applicationInformation = [1]
        let (legacy, _) = try DICOMAssociationNegotiator.respond(to: request, policy: policy).get()
        XCTAssertEqual(legacy.userInformation.extendedNegotiations.first?.applicationInformation, [1])
        var invalid = legacy
        invalid.userInformation.extendedNegotiations[0].applicationInformation = [1,1]
        XCTAssertThrowsError(try DICOMAssociationNegotiator.negotiated(request: request, accept: invalid))
        request.userInformation.extendedNegotiations = []
        let (baseline, local) = try DICOMAssociationNegotiator.respond(to: request, policy: policy).get()
        XCTAssertTrue(baseline.userInformation.extendedNegotiations.isEmpty)
        XCTAssertTrue(local.queryRetrieveOptions(for: model).isEmpty)
        XCTAssertThrowsError(try DICOMQueryRetrieveOptions(negotiation: .init(sopClassUID: model, applicationInformation: [2])))
        XCTAssertEqual(DICOMSOPClass.compositeInstanceRootGet, "1.2.840.10008.5.1.4.1.2.4.3")
        XCTAssertEqual(DICOMSOPClass.compositeInstanceRootMove, "1.2.840.10008.5.1.4.1.2.4.2")
    }

    func testCombinedMidnightRangeFuzzyAndTimezone() throws {
        let query = try W.dataSet(["00080020": ("DA", ["20261020-20261021"]), "00080030": ("TM", ["2300-0100"]),
            "00080201": ("SH", ["+0200"]), "00100010": ("PN", ["Anne Muller"])])
        let stored = try W.dataSet(["00080005": ("CS", ["ISO_IR 192"]), "00080020": ("DA", ["20261020"]), "00080030": ("TM", ["223000"]),
            "00080201": ("SH", ["+0000"]), "00100010": ("PN", ["Müller^Anne"])])
        let matcher = DICOMQueryMatcher(combinedDateTime: [("00080020", "00080030")], fuzzyPersonNames: true, timezoneAdjustment: true)
        XCTAssertNotNil(try matcher.match(query, against: stored))
        XCTAssertNil(try DICOMQueryMatcher().match(query, against: stored))
        XCTAssertTrue(try DICOMQuery(identifier: query, matcher: matcher).conditions.isEmpty, "adapters must not exclude fuzzy/timezone matches")
        let timeQuery = try W.dataSet(["00080030": ("TM", ["0030"]), "00080201": ("SH", ["+0200"])])
        XCTAssertNotNil(try matcher.match(timeQuery, against: stored), "clock adjustment crosses midnight")
        let dtQuery = try W.dataSet(["0008002A": ("DT", ["20261020120000-0500"])])
        let dtStored = try W.dataSet(["0008002A": ("DT", ["20261020170000+0000"])])
        _ = dtQuery.set(value: "+0200", forTagName: "TimezoneOffsetFromUTC")
        XCTAssertNotNil(try matcher.match(dtQuery, against: dtStored), "an explicit negative DT offset takes precedence over query timezone")
        let open = try W.dataSet(["00080030": ("TM", ["-0200"])])
        XCTAssertNil(try matcher.match(open, against: stored), "an open TM range must not match an arbitrary previous day")
    }

    func testIdentifierRulesAndRelationalRetrieve() throws {
        let query = identifier("SERIES", ["SeriesInstanceUID": "1.2.3"])
        XCTAssertThrowsError(try DICOMArchiveQueryRetrieve.validate(query, model: DICOMSOPClass.studyRootGet, options: [], retrieve: true))
        XCTAssertEqual(try DICOMArchiveQueryRetrieve.validate(query, model: DICOMSOPClass.studyRootGet, options: .relational, retrieve: true), "SERIES")
        _ = query.set(value: "CLASSIC", forTagName: "QueryRetrieveView")
        XCTAssertThrowsError(try DICOMArchiveQueryRetrieve.validate(query, model: DICOMSOPClass.studyRootGet, options: .relational, retrieve: true))
        let composite = identifier("IMAGE", ["SOPInstanceUID": "1.2.3\\1.2.4"])
        XCTAssertEqual(try DICOMArchiveQueryRetrieve.validate(composite, model: DICOMSOPClass.compositeInstanceRootGet, options: [], retrieve: true), "IMAGE")
        _ = composite.set(value: "ISO_IR 192", forTagName: "SpecificCharacterSet")
        XCTAssertThrowsError(try DICOMArchiveQueryRetrieve.validate(composite, model: DICOMSOPClass.compositeInstanceRootGet, options: [], retrieve: true))
    }

    func testRelationalArchivePreservesWholeEntityCounts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = DICOMArchive(directory: root)
        for (i, modality) in ["MR", "CT"].enumerated() {
            let dataSet = try W.dataSet(["00080016": ("UI", [sc]), "00080018": ("UI", ["1.2.3.\(i)"]),
                "0020000D": ("UI", ["1.2.3"]), "0020000E": ("UI", ["1.2.3.4.\(i)"]), "00080060": ("CS", [modality])])
            let item = try DICOMRetrieveItem(dataSet: dataSet)
            try await archive.store(.init(sopClassUID: sc, sopInstanceUID: item.sopInstanceUID, transferSyntaxUID: explicit,
                payload: item.payload, moveOriginatorAETitle: nil, moveOriginatorMessageID: nil, sourceAETitle: "SCU"))
        }
        let service = DICOMArchiveServices(archive: archive)
        let query = identifier("STUDY", ["Modality": "CT", "StudyInstanceUID": "", "NumberOfStudyRelatedInstances": ""])
        do { _ = try await service.find(query, informationModel: DICOMSOPClass.studyRootFind, context: context(DICOMSOPClass.studyRootFind)); XCTFail("accepted unnegotiated relational key") }
        catch let error as DICOMServiceError { XCTAssertEqual(error.status, .identifierDoesNotMatchSOPClass) }
        var matches: [DataSet] = []
        for try await match in try await service.find(query, informationModel: DICOMSOPClass.studyRootFind, context: context(DICOMSOPClass.studyRootFind, options: .relational)) { matches.append(match) }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.string(forTag: "NumberOfStudyRelatedInstances"), "2")
        XCTAssertEqual(matches.first?.string(forTag: "Modality"), "CT")
        // Modalities in Study is matched against the series of the study, with or without relational queries.
        for (modalities, count) in [("CT", 1), ("OT", 0), ("OT\\MR", 1)] {
            var found: [DataSet] = []
            let byModality = identifier("STUDY", ["StudyInstanceUID": "", "ModalitiesInStudy": modalities])
            for try await match in try await service.find(byModality, informationModel: DICOMSOPClass.studyRootFind, context: context(DICOMSOPClass.studyRootFind)) { found.append(match) }
            XCTAssertEqual(found.count, count, modalities)
            if count == 1 { XCTAssertEqual(found.first?.textValues(forTag: "ModalitiesInStudy"), ["CT", "MR"]) }
        }
        let items = try await service.retrieve(identifier("IMAGE", ["SOPInstanceUID": "1.2.3.1"]), informationModel: DICOMSOPClass.compositeInstanceRootGet, context: context(DICOMSOPClass.compositeInstanceRootGet))
        XCTAssertEqual(items.map(\.sopInstanceUID), ["1.2.3.1"])
    }

    func frameSource(bits: Int = 8) throws -> DataSet {
        let dataSet = try W.dataSet(["00080016": ("UI", [sc]), "00080018": ("UI", ["1.2.3.4"]),
            "00100020": ("LO", ["P1"]), "0020000D": ("UI", ["1.2.3"]), "0020000E": ("UI", ["1.2.3.1"]),
            "00280010": ("US", [1]), "00280011": ("US", [2]), "00280002": ("US", [1]),
            "00280004": ("CS", ["MONOCHROME2"]), "00280100": ("US", [bits]), "00280101": ("US", [bits]),
            "00280102": ("US", [bits-1]), "00280103": ("US", [0]), "00280008": ("IS", ["4"]),
            "00080023": ("DA", ["20261020"]), "00080033": ("TM", ["235959"]), "00181063": ("DS", ["1000"]),
            "00280009": ("AT", ["00181063"])])
        _ = dataSet.set(value: Data([10,11,20,21,30,31,40,41]), forTagName: "PixelData")
        dataSet.element(forTagName: "PixelData")?.vr = bits > 8 ? .OW : .OB
        return dataSet
    }

    func testBulkOmissionPreservesIconsAndWaveformMetadata() throws {
        let dataSet = try frameSource()
        var object = try DICOMJSON.object(dataSet)
        object["00880200"] = ["vr": "SQ", "Value": [["7FE00010": ["vr": "OB", "InlineBinary": "AQI="]]]]
        object["54000100"] = ["vr": "SQ", "Value": [["54001010": ["vr": "OW", "InlineBinary": "AQI="], "003A0005": ["vr": "US", "Value": [1]]]]]
        object["00420011"] = ["vr": "OB", "InlineBinary": "AQI="]
        object["60003000"] = ["vr": "OW", "InlineBinary": "AQI="]
        let item = try DICOMRetrieveItem(dataSet: DICOMJSON.dataSet(object))
        let stripped = try DICOMArchiveQueryRetrieve.withoutBulkData(item)
        let result = try DICOMDataSetCoding.decode(stripped.payload.data(), transferSyntax: stripped.transferSyntaxUID)
        XCTAssertEqual(stripped.sopInstanceUID, item.sopInstanceUID)
        XCTAssertNil(result.element(forTagName: "PixelData"))
        let json = try DICOMJSON.object(result)
        XCTAssertNil(json["00420011"]); XCTAssertNil(json["60003000"])
        XCTAssertNotNil(result.sequence(forTagName: "IconImageSequence")?.items.first?.element(withName: "PixelData"))
        XCTAssertNil(result.sequence(forTagName: "WaveformSequence")?.items.first?.element(withName: "WaveformData"))
        XCTAssertNotNil(result.sequence(forTagName: "WaveformSequence")?.items.first?.element(withName: "NumberOfWaveformChannels"))
        XCTAssertNotNil(dataSet.element(forTagName: "PixelData"), "original remains intact")
    }

    func testFrameExtractionPayloadIdentityTimingAndProvenance() throws {
        let item = try DICOMRetrieveItem(dataSet: frameSource())
        let request = identifier("FRAME", ["SOPInstanceUID": item.sopInstanceUID])
        _ = request.set(value: [UInt32(2), UInt32(4)], forTagName: "SimpleFrameList")
        let result = try DICOMFrameExtraction.extract(item, identifier: request)
        let dataSet = try DICOMDataSetCoding.decode(result.payload.data(), transferSyntax: result.transferSyntaxUID)
        XCTAssertEqual(result.sopClassUID, item.sopClassUID); XCTAssertNotEqual(result.sopInstanceUID, item.sopInstanceUID)
        XCTAssertEqual(dataSet.string(forTag: "NumberOfFrames"), "2")
        XCTAssertEqual(try dataSet.element(forTagName: "PixelData")?.loadData(), Data([20,21,40,41]))
        XCTAssertEqual(dataSet.string(forTag: "StudyInstanceUID"), "1.2.3")
        XCTAssertEqual(dataSet.textValues(forTag: "ContentDate")?.first, "20261021")
        XCTAssertEqual(dataSet.string(forTag: "FrameTimeVector"), "0\\2000")
        XCTAssertEqual(dataSet.sequence(forTagName: "FrameExtractionSequence")?.items.count, 1)
        XCTAssertEqual(dataSet.sequence(forTagName: "ContributingEquipmentSequence")?.items.count, 1)
        let repeatedRequest = identifier("FRAME", ["SOPInstanceUID": result.sopInstanceUID])
        _ = repeatedRequest.set(value: [UInt32(2)], forTagName: "SimpleFrameList")
        let repeated = try DICOMFrameExtraction.extract(result, identifier: repeatedRequest)
        let history = try DICOMDataSetCoding.decode(repeated.payload.data(), transferSyntax: repeated.transferSyntaxUID)
        XCTAssertEqual(history.sequence(forTagName: "FrameExtractionSequence")?.items.count, 2)
        XCTAssertEqual(history.sequence(forTagName: "ContributingEquipmentSequence")?.items.count, 2)
        _ = request.remove(elementForTagName: "SimpleFrameList")
        _ = request.set(value: [1.0, 2.0], forTagName: "TimeRange")
        let ranged = try DICOMFrameExtraction.extract(item, identifier: request)
        XCTAssertNotEqual(ranged.sopInstanceUID, result.sopInstanceUID)
    }

    func testCalculatedFramesAndFailureStatuses() throws {
        let query = identifier("FRAME")
        _ = query.set(value: [UInt32(2),9,3,12,UInt32.max,5], forTagName: "CalculatedFrameList")
        XCTAssertEqual(try DICOMFrameExtraction.frames(query, count: 25), [2,5,8,12,17,22])
        _ = query.set(value: [UInt32(2),9,0], forTagName: "CalculatedFrameList")
        XCTAssertThrowsError(try DICOMFrameExtraction.frames(query, count: 25)) { XCTAssertEqual(($0 as? DICOMServiceError)?.status.code, 0xAA04) }
        _ = query.remove(elementForTagName: "CalculatedFrameList")
        _ = query.set(value: [10.0, 20.0], forTagName: "TimeRange")
        XCTAssertThrowsError(try DICOMFrameExtraction.frames(query, count: 2)) { XCTAssertEqual(($0 as? DICOMServiceError)?.status.code, 0xAA03) }
        XCTAssertThrowsError(try DICOMFrameExtraction.frames(query, count: 2, times: [0,1])) { XCTAssertEqual(($0 as? DICOMServiceError)?.status.code, 0xAA00) }
    }

    func patientRecord(_ patient: String = "P1") throws -> DataSet {
        try W.dataSet(["00080005": ("CS", ["ISO_IR 192"]), "00100010": ("PN", ["Müller^Anne"]), "00100020": ("LO", [patient]), "00100021": ("LO", ["DOMAIN"]),
            "00100030": ("DA", []), "00100040": ("CS", []), "0040A032": ("DT", ["20261021120000"]),
            "0040A040": ("CS", ["CONTAINER"]), "0040A043": ("SQ", [["00080100": ("SH", ["1"]), "00080102": ("SH", ["99TEST"]), "00080104": ("LO", ["Summary"])]]),
            "0040A730": ("SQ", []), "0040A504": ("SQ", [["00080105": ("CS", ["DCMR"]), "0040DB00": ("CS", ["9007"])]])])
    }
    func patientQuery() throws -> DataSet {
        let result = try patientRecord()
        for name in ["PatientName", "ObservationDateTime", "ValueType"] { _ = result.set(value: "", forTagName: name) }
        for sequence in ["ConceptNameCodeSequence", "ContentSequence"] { result.sequence(forTagName: sequence)?.items = [] }
        return result
    }
    func testRelevantPatientContentAndSpecificFailures() async throws {
        let template = DICOMRelevantPatientInformationService.Template(identifier: "9007")
        let service = try DICOMRelevantPatientInformationService(records: [patientRecord()], supportedTemplates: [template])
        let model = DICOMSOPClass.generalRelevantPatientInformationFind
        var count = 0
        for try await match in try await service.find(patientQuery(), informationModel: model, context: context(model)) {
            count += 1; XCTAssertEqual(match.string(forTag: "PatientID"), "P1")
            XCTAssertEqual(match.string(forTag: "PatientName"), "Müller^Anne")
            XCTAssertEqual(match.sequence(forTagName: "ConceptNameCodeSequence")?.items.count, 1)
        }
        XCTAssertEqual(count, 1)
        do { _ = try await service.find(patientQuery(), informationModel: DICOMSOPClass.cardiacRelevantPatientInformationFind, context: context(model)); XCTFail() }
        catch let error as DICOMServiceError { XCTAssertEqual(error.status.code, 0xC200) }
        let duplicate = try DICOMRelevantPatientInformationService(records: [patientRecord(), patientRecord()], supportedTemplates: [template])
        do { _ = try await duplicate.find(patientQuery(), informationModel: model, context: context(model)); XCTFail() }
        catch let error as DICOMServiceError { XCTAssertEqual(error.status.code, 0xC100) }
        let query = try patientQuery(); _ = query.set(value: "P*", forTagName: "PatientID")
        do { _ = try await service.find(query, informationModel: model, context: context(model)); XCTFail() }
        catch let error as DICOMServiceError { XCTAssertEqual(error.status.code, 0xA900) }
    }
    func testWireNegotiationBulkGetRelationalGetAndPatientInformation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = DICOMArchive(directory: root)
        let item = try DICOMRetrieveItem(dataSet: frameSource())
        try await archive.store(.init(sopClassUID: sc, sopInstanceUID: item.sopInstanceUID, transferSyntaxUID: explicit,
            payload: item.payload, moveOriginatorAETitle: nil, moveOriginatorMessageID: nil, sourceAETitle: "SCU"))
        let service = DICOMArchiveServices(archive: archive)
        let patient = try DICOMRelevantPatientInformationService(records: [patientRecord()], supportedTemplates: [.init(identifier: "9007")])
        let server = try DICOMServer(configuration: .init(aeTitle: "SCP", host: "127.0.0.1", port: 0), query: service,
            relevantPatientInformation: patient, retrieve: service)
        let ready = AsyncStream<Int>.makeStream()
        let task = Task { try await server.run { ready.continuation.yield($0) } }
        var iterator = ready.stream.makeAsyncIterator()
        let bound = await iterator.next()
        let port = try XCTUnwrap(bound)
        do {
            let client = try DICOMClient(configuration: .init(aeTitle: "SCU"))
            let storage = DcmSwiftNetworkIntegrationTests.MemoryStorage()
            let models = [DICOMSOPClass.studyRootFind, DICOMSOPClass.studyRootGet, DICOMSOPClass.compositeInstanceRootGet,
                DICOMSOPClass.compositeInstanceRetrieveWithoutBulkDataGet, DICOMSOPClass.generalRelevantPatientInformationFind, sc]
            try await client.withAssociation(to: .init(aeTitle: "SCP", host: "127.0.0.1", port: port),
                presentationContexts: .proposals(abstractSyntaxes: models),
                roleSelections: [.init(sopClassUID: sc, scuRole: false, scpRole: true)],
                extendedNegotiations: [try DICOMQueryRetrieveOptions.relational.negotiation(for: DICOMSOPClass.studyRootGet),
                    try DICOMQueryRetrieveOptions(rawValue: 127).negotiation(for: DICOMSOPClass.studyRootFind)], storage: storage) { association in
                XCTAssertEqual(association.negotiated.queryRetrieveOptions(for: DICOMSOPClass.studyRootFind), service.queryRetrieveOptions)
                let query = identifier("SERIES", ["SeriesInstanceUID": "1.2.3.1"])
                let got = try await association.get(query)
                XCTAssertEqual(got.progress.completed, 1)
                let bulk = try await association.get(identifier("IMAGE", ["SOPInstanceUID": item.sopInstanceUID]), informationModel: DICOMSOPClass.compositeInstanceRetrieveWithoutBulkDataGet)
                XCTAssertEqual(bulk.progress.completed, 1)
                let received = storage.received.withLockedValue { $0 }
                XCTAssertNotNil(try received[0].dataSet().element(forTagName: "PixelData"))
                XCTAssertNil(try received[1].dataSet().element(forTagName: "PixelData"))
                var patients = 0
                for try await _ in association.find(try patientQuery(), informationModel: DICOMSOPClass.generalRelevantPatientInformationFind) { patients += 1 }
                XCTAssertEqual(patients, 1)
                let invalid = identifier("FRAME", ["SOPInstanceUID": item.sopInstanceUID])
                do { _ = try await association.get(invalid, informationModel: DICOMSOPClass.compositeInstanceRootGet); XCTFail("missing frame selector") }
                catch let error as DICOMServiceError { XCTAssertEqual(error.status.code, 0xAA04) }
            }
            task.cancel(); _ = try? await task.value
        } catch {
            task.cancel(); _ = try? await task.value
            throw error
        }
    }

    func testBitPackedAndBigEndianFrameExtraction() throws {
        let bits = try frameSource(bits: 1)
        _ = bits.set(value: "1.2.840.10008.5.1.4.1.1.7.1", forTagName: "SOPClassUID")
        _ = bits.set(value: Data([0b11100100, 0]), forTagName: "PixelData")
        let request = identifier("FRAME", ["SOPInstanceUID": "1.2.3.4"])
        _ = request.set(value: [UInt32(2), UInt32(4)], forTagName: "SimpleFrameList")
        let selected = try DICOMFrameExtraction.extract(DICOMRetrieveItem(dataSet: bits), identifier: request)
        let decoded = try DICOMDataSetCoding.decode(selected.payload.data(), transferSyntax: selected.transferSyntaxUID)
        XCTAssertEqual(try decoded.element(forTagName: "PixelData")?.loadData(), Data([0b1101, 0]), "selected bits are packed across frame boundaries and padded to even VL")
        let words = try frameSource(bits: 16)
        _ = words.set(value: "1.2.840.10008.5.1.4.1.1.7.3", forTagName: "SOPClassUID")
        _ = words.set(value: Data([1,0,2,0,3,0,4,0,5,0,6,0,7,0,8,0]), forTagName: "PixelData")
        let big = try DICOMRetrieveItem(dataSet: words, transferSyntaxUID: TransferSyntax.explicitVRBigEndian)
        let result = try DICOMFrameExtraction.extract(big, identifier: request)
        let dataSet = try DICOMDataSetCoding.decode(result.payload.data(), transferSyntax: result.transferSyntaxUID)
        XCTAssertEqual(try DICOMNativePixelData(dataset: dataSet).storedValues(frame: 0), [3,4])
        XCTAssertEqual(try DICOMNativePixelData(dataset: dataSet).storedValues(frame: 1), [7,8])
    }

    func testPatientInformationRejectsReferencesAndNonEmptyReturnKeys() async throws {
        let template = DICOMRelevantPatientInformationService.Template(identifier: "9007")
        let record = try patientRecord()
        var object = try DICOMJSON.object(record)
        object["0040A730"] = ["vr": "SQ", "Value": [["0040DB73": ["vr": "UL", "Value": [1]]]]]
        XCTAssertThrowsError(try DICOMRelevantPatientInformationService(records: [DICOMJSON.dataSet(object)], supportedTemplates: [template]))
        let service = try DICOMRelevantPatientInformationService(records: [record], supportedTemplates: [template])
        let query = try patientQuery(); _ = query.set(value: "Someone", forTagName: "PatientName")
        do { _ = try await service.find(query, informationModel: DICOMSOPClass.generalRelevantPatientInformationFind, context: context(DICOMSOPClass.generalRelevantPatientInformationFind)); XCTFail() }
        catch let error as DICOMServiceError { XCTAssertEqual(error.status.code, 0xA900) }
    }

    func testLiteralPNAndTimezoneInheritance() throws {
        let query = try W.dataSet(["00100010": ("PN", ["Muller^Anne"])])
        let record = try patientRecord()
        XCTAssertNil(try DICOMArchiveQueryRetrieve.matcher([]).match(query, against: record), "accents remain significant without fuzzy negotiation")
        XCTAssertNotNil(try DICOMArchiveQueryRetrieve.matcher(.fuzzyPersonNames).match(query, against: record))
        let nestedQuery = try W.dataSet(["00080201": ("SH", ["+0200"]), "00400275": ("SQ", [["0008002A": ("DT", ["20261021010000"])]] )])
        let nestedEntity = try W.dataSet(["00080201": ("SH", ["+0000"]), "00400275": ("SQ", [["0008002A": ("DT", ["20261020230000"])]] )])
        XCTAssertNotNil(try DICOMQueryMatcher(timezoneAdjustment: true).match(nestedQuery, against: nestedEntity))
    }

    func testFrameDependentVectorsAreRefusedWithoutRewritingThem() throws {
        let source = try frameSource()
        let request = identifier("FRAME", ["SOPInstanceUID": "1.2.3.4"])
        _ = request.set(value: [UInt32(2)], forTagName: "SimpleFrameList")
        for (tag, attribute) in [
            "00182003": ["vr": "DS", "Value": ["0", "1", "2", "3"]],
            "00286020": ["vr": "US", "Value": [2]]
        ] as [String: [String: Any]] {
            var object = try DICOMJSON.object(source)
            object[tag] = attribute
            let item = try DICOMRetrieveItem(dataSet: DICOMJSON.dataSet(object))
            XCTAssertThrowsError(try DICOMFrameExtraction.extract(item, identifier: request)) {
                XCTAssertEqual(($0 as? DICOMServiceError)?.status.code, 0xAA02)
            }
        }
    }

}
