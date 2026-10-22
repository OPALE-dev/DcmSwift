import XCTest
@testable import DcmSwift

final class DcmSwiftEnhancedConversionTests: XCTestCase {
    typealias C = DICOMEnhancedMultiFrameConversion

    func source(_ frame: Int, kind: Int = 0) -> DataSet {
        let dataSet = DcmSwiftIODValidationTests.secondaryCaptureImage()
        let values: [(String, Any)] = [
            ("SOPClassUID", C.classicClasses[kind]), ("SOPInstanceUID", "1.2.826.0.1.3680043.10.999.\(kind).\(frame)"),
            ("SeriesInstanceUID", "1.2.826.0.1.3680043.10.999.\(kind)"), ("Modality", ["CT", "MR", "PT"][kind]),
            ("ImageType", "ORIGINAL\\PRIMARY\\" + ["AXIAL", "M", "STATIC"][kind]), ("InstanceNumber", String(frame)),
            ("Manufacturer", "Test"), ("ContentDate", "20261021"), ("ContentTime", "120000"),
            ("SeriesDate", "20261021"), ("SeriesTime", "110000"),
            ("AcquisitionDate", "20261021"), ("AcquisitionTime", "120000"), ("AcquisitionNumber", "1"),
            ("FrameOfReferenceUID", "1.2.826.0.1.3680043.10.999.99"), ("PositionReferenceIndicator", ""),
            ("PixelSpacing", "1\\1"), ("ImagePositionPatient", "0\\0\\\(frame)"), ("ImageOrientationPatient", "1\\0\\0\\0\\1\\0"),
            ("SliceThickness", "1"), ("BodyPartExamined", "CHEST"),
            ("BitsAllocated", UInt16(16)), ("BitsStored", UInt16(16)), ("HighBit", UInt16(15)),
            ("RescaleIntercept", "0"), ("RescaleSlope", "1"), ("RescaleType", kind == 0 ? "HU" : "US"),
            ("WindowCenter", "40"), ("WindowWidth", "400"), ("KVP", "120"),
            ("ScanningSequence", "SE"), ("SequenceVariant", "NONE"), ("ScanOptions", ""), ("MRAcquisitionType", "2D"),
            ("EchoTime", "10"), ("EchoTrainLength", "1"), ("RepetitionTime", "500"),
        ]
        for (name, value) in values { _ = dataSet.set(value: value, forTagName: name) }
        if kind == 2 {
            for (name, value) in [("ContentQualification", "PRODUCT"), ("Units", "BQML"), ("CountsSource", "EMISSION"), ("SeriesType", "STATIC\\IMAGE"),
                ("NumberOfSlices", "2"), ("CorrectedImage", ""), ("DecayCorrection", "START"), ("DecayFactor", "1"),
                ("CollimatorType", ""), ("FrameReferenceTime", "0"), ("ImageIndex", String(frame)), ("ActualFrameDuration", "1000")] {
                _ = dataSet.set(value: value, forTagName: name)
            }
            for name in ["RadiopharmaceuticalInformationSequence", "PatientOrientationCodeSequence", "PatientGantryRelationshipCodeSequence"] {
                let builder = DICOMDataSetBuilder()
                if let sequence = builder.sequence(name, items: []) { dataSet.add(element: sequence) }
            }
        }
        let bytes = (0..<4).flatMap { [UInt8(frame * 10 + $0), UInt8(0)] }
        _ = dataSet.set(value: Data(bytes), forTagName: "PixelData")
        dataSet.element(forTagName: "PixelData")?.vr = .OW
        return dataSet
    }
    func report(_ image: DataSet, frames: [Int] = []) -> DataSet {
        let ref = DICOMSRReference(sopClassUID: image.string(forTag: "SOPClassUID")!, sopInstanceUID: image.string(forTag: "SOPInstanceUID")!, frames: frames)
        let root = DICOMSRContentItem(nil, DICOMCode("1", scheme: "99TEST", meaning: "Summary"), .container(continuity: "SEPARATE"),
            children: [DICOMSRContentItem("CONTAINS", DICOMCode("2", scheme: "99TEST", meaning: "Image"), .image(ref))])
        return DICOMStructuredReport(root: root).dataSet(context: image)
    }
    func decode(_ item: DICOMRetrieveItem) throws -> DataSet { try DICOMDataSetCoding.decode(item.payload.data(), transferSyntax: item.transferSyntaxUID) }

    func testCTViewPixelsGeometryDeterminismAndInverse() throws {
        let images = [source(1), source(2)]
        for image in images {
            let validation = DICOMIODValidator().validate(image)
            XCTAssertTrue(validation.isValid, validation.findings.map(\.description).joined(separator: "\n"))
        }
        let input = try images.map { try DICOMRetrieveItem(dataSet: $0) }
        let enhanced = try C.convert(input, to: .enhanced)
        XCTAssertEqual(enhanced.count, 1)
        XCTAssertEqual(enhanced.first?.sopClassUID, C.legacyClasses[0])
        let dataSet = try decode(enhanced[0])
        XCTAssertEqual(dataSet.string(forTag: "NumberOfFrames"), "2")
        XCTAssertEqual(dataSet.string(forTag: "StudyInstanceUID"), images[0].string(forTag: "StudyInstanceUID"))
        XCTAssertNotEqual(dataSet.string(forTag: "SeriesInstanceUID"), images[0].string(forTag: "SeriesInstanceUID"))
        XCTAssertEqual(try DICOMNativePixelData(dataset: dataSet).storedValues(frame: 1), [20,21,22,23])
        XCTAssertEqual(dataSet.sequence(forTagName: "PerFrameFunctionalGroupsSequence")?.items.count, 2)
        XCTAssertTrue(DICOMIODValidator().validate(dataSet).isValid)
        let again = try C.convert(Array(input.reversed()), to: .enhanced)
        XCTAssertEqual(again.map(\.sopInstanceUID), enhanced.map(\.sopInstanceUID))
        XCTAssertEqual(try again[0].payload.data(), try enhanced[0].payload.data())
        let classic = try C.convert(enhanced, to: .classic)
        XCTAssertEqual(classic.count, 2)
        let recovered = try classic.map(decode).sorted { ($0.string(forTag: "ImagePositionPatient") ?? "") < ($1.string(forTag: "ImagePositionPatient") ?? "") }
        XCTAssertEqual(try recovered.map { try DICOMNativePixelData(dataset: $0).storedValues(frame: 0) }, [[10,11,12,13],[20,21,22,23]])
        for image in recovered { XCTAssertTrue(DICOMIODValidator().validate(image).isValid) }
    }

    func testDependentSRReferenceClosureAndExpansion() throws {
        let images = [source(1), source(2)]
        let sr = report(images[1])
        let originalSRUID = sr.string(forTag: "SOPInstanceUID")!
        let converted = try C.convert(try (images + [sr]).map { try DICOMRetrieveItem(dataSet: $0) }, to: .enhanced)
        XCTAssertEqual(converted.count, 2)
        let enhanced = try XCTUnwrap(converted.first { $0.sopClassUID == C.legacyClasses[0] })
        let srItem = try XCTUnwrap(converted.first { $0.sopClassUID == DICOMStructuredReport.comprehensive3DSR })
        XCTAssertNotEqual(srItem.sopInstanceUID, originalSRUID)
        let parsed = try XCTUnwrap(DICOMStructuredReport(dataSet: decode(srItem)))
        guard case .image(let ref) = parsed.root.children[0].value else { return XCTFail() }
        XCTAssertEqual(ref.sopInstanceUID, enhanced.sopInstanceUID)
        XCTAssertEqual(ref.sopClassUID, enhanced.sopClassUID)
        XCTAssertEqual(ref.frames, [2])
        let inverse = try C.convert(converted, to: .classic)
        let inverseSR = try decode(XCTUnwrap(inverse.first { $0.sopClassUID == srItem.sopClassUID }))
        let inverseReport = try XCTUnwrap(DICOMStructuredReport(dataSet: inverseSR))
        guard case .image(let recovered) = inverseReport.root.children[0].value else { return XCTFail() }
        XCTAssertTrue(inverse.contains { $0.sopInstanceUID == recovered.sopInstanceUID && $0.sopClassUID == C.classicClasses[0] })
        XCTAssertTrue(recovered.frames.isEmpty)
        let wholeSR = report(try decode(enhanced))
        let expanded = try C.convert([enhanced, DICOMRetrieveItem(dataSet: wholeSR)], to: .classic)
        let expandedReport = try XCTUnwrap(DICOMStructuredReport(dataSet: decode(XCTUnwrap(expanded.first { $0.sopClassUID == srItem.sopClassUID }))))
        XCTAssertEqual(expandedReport.root.children.count, 2, "one IMAGE content item per classic target, each with one reference")
    }

    func testMRAndPETLegacyConversions() throws {
        for kind in [1,2] {
            let converted = try C.convert([DICOMRetrieveItem(dataSet: source(1, kind: kind)), DICOMRetrieveItem(dataSet: source(2, kind: kind))], to: .enhanced)
            XCTAssertEqual(converted.count, 1)
            XCTAssertEqual(converted[0].sopClassUID, C.legacyClasses[kind])
            let inverse = try C.convert(converted, to: .classic)
            XCTAssertEqual(inverse.count, 2)
            XCTAssertTrue(inverse.allSatisfy { $0.sopClassUID == C.classicClasses[kind] })
        }
    }
    func testEnhancedFrameExtractionSelectorsAndCompressedCodestreams() throws {
        let converted = try C.convert([DICOMRetrieveItem(dataSet: source(1)), DICOMRetrieveItem(dataSet: source(2))], to: .enhanced)[0]
        let dataSet = try decode(converted)
        var object = try DICOMJSON.object(dataSet, options: .init(numbersAsStrings: true))
        var frames = C.items(object, "52009230")
        var content = C.items(frames[1], "00209111")[0]
        content["00189151"] = C.attribute("DT", ["20261021120001"])
        frames[1]["00209111"] = C.sequence([content])
        let dimensionUID = C.uid("test dimensions")
        object["00209221"] = C.sequence([["00209164": C.attribute("UI", [dimensionUID])]])
        object["00209222"] = C.sequence([["00209164": C.attribute("UI", [dimensionUID]), "00209165": ["vr": "AT", "Value": ["00209057"]], "00209167": ["vr": "AT", "Value": ["00209111"]]]])
        for i in frames.indices {
            var frame = C.items(frames[i], "00209111")[0]
            frame["00209157"] = ["vr": "UL", "Value": [i + 1]]
            frame["00209056"] = C.attribute("SH", ["1"]); frame["00209057"] = ["vr": "UL", "Value": [i + 1]]
            frames[i]["00209111"] = C.sequence([frame])
        }
        object["52009230"] = C.sequence(frames)
        let timed = try DICOMRetrieveItem(dataSet: DICOMJSON.dataSet(object))
        let request = DataSet()
        _ = request.set(value: "FRAME", forTagName: "QueryRetrieveLevel")
        _ = request.set(value: timed.sopInstanceUID, forTagName: "SOPInstanceUID")
        _ = request.set(value: [1.0,1.0], forTagName: "TimeRange")
        let temporal = try DICOMFrameExtraction.extract(timed, identifier: request)
        let selected = try decode(temporal)
        XCTAssertEqual(try DICOMNativePixelData(dataset: selected).storedValues(frame: 0), [20,21,22,23])
        XCTAssertEqual(selected.string(forTag: "SeriesInstanceUID"), dataSet.string(forTag: "SeriesInstanceUID"))
        XCTAssertNotEqual(temporal.sopInstanceUID, timed.sopInstanceUID)
        XCTAssertTrue(DICOMIODValidator().validate(selected).isValid)
        let frameContent = try XCTUnwrap(selected.sequence(forTagName: "PerFrameFunctionalGroupsSequence")?.items.first?.element(withName: "FrameContentSequence") as? DataSequence)
        XCTAssertEqual(frameContent.items[0].element(withName: "DimensionIndexValues")?.uint32Values, [1])
        XCTAssertEqual(frameContent.items[0].element(withName: "InStackPositionNumber")?.uint32Values, [2])
        _ = request.remove(elementForTagName: "TimeRange")
        _ = request.set(value: [UInt32(2), UInt32.max, 1], forTagName: "CalculatedFrameList")
        XCTAssertEqual(try decode(DICOMFrameExtraction.extract(timed, identifier: request)).string(forTag: "NumberOfFrames"), "1")
        _ = request.remove(elementForTagName: "CalculatedFrameList")
        _ = request.set(value: [UInt32(2)], forTagName: "SimpleFrameList")
        let native = try DICOMNativePixelData(dataset: dataSet), description = try DICOMPixelDescription(dataset: dataSet)
        var fragments = Data([0xfe,0xff,0,0xe0,0,0,0,0])
        for i in 0..<2 {
            var encoded = try DICOMRLECodec().encode(native.frameData(i), description: description)
            if encoded.count % 2 != 0 { encoded.append(0) }
            fragments.append(contentsOf: [0xfe,0xff,0,0xe0]); fragments.append(uint32: UInt32(encoded.count), bigEndian: false)
            fragments.append(encoded)
        }
        object["7FE00010"] = ["vr": "OB", "InlineBinary": fragments.base64EncodedString()]
        let compressed = try DICOMRetrieveItem(dataSet: DICOMJSON.dataSet(object), transferSyntaxUID: DICOMRLECodec.transferSyntaxUID)
        let extracted = try DICOMFrameExtraction.extract(compressed, identifier: request)
        XCTAssertEqual(extracted.transferSyntaxUID, DICOMRLECodec.transferSyntaxUID)
        let encapsulated = try DICOMEncapsulatedPixelData(dataset: decode(extracted))
        XCTAssertEqual(try encapsulated.decodedFrame(0).data, try native.frameData(1))
        let original = try DICOMEncapsulatedPixelData(dataset: decode(compressed))
        XCTAssertEqual(try encapsulated.encodedFrame(0), try original.encodedFrame(1), "compressed bytes are selected without re-encoding")
    }

    func testViewValidationAndAtomicFailure() throws {
        let original = source(1)
        _ = original.remove(elementForTagName: "WindowWidth")
        let input = try DICOMRetrieveItem(dataSet: original)
        XCTAssertThrowsError(try C.convert([input], to: .enhanced))
        XCTAssertEqual(original.string(forTag: "SOPInstanceUID"), input.sopInstanceUID)
        let request = DataSet()
        _ = request.set(value: "STUDY", forTagName: "QueryRetrieveLevel")
        _ = request.set(value: "ENHANCED", forTagName: "QueryRetrieveView")
        XCTAssertThrowsError(try DICOMArchiveQueryRetrieve.validate(request, model: DICOMSOPClass.studyRootFind, options: [], retrieve: false))
        XCTAssertEqual(try DICOMArchiveQueryRetrieve.validate(request, model: DICOMSOPClass.studyRootFind, options: .enhancedMultiFrameConversion, retrieve: false), "STUDY")
    }

    func testArchiveViewFindRetrieveAndReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = DICOMArchive(directory: directory)
        let sourceData = [source(1), source(2)]
        for data in sourceData {
            let item = try DICOMRetrieveItem(dataSet: data)
            try await archive.store(.init(sopClassUID: item.sopClassUID, sopInstanceUID: item.sopInstanceUID, transferSyntaxUID: item.transferSyntaxUID,
                payload: item.payload, moveOriginatorAETitle: nil, moveOriginatorMessageID: nil, sourceAETitle: "SCU"))
        }
        let services = DICOMArchiveServices(archive: archive)
        func identifier(_ level: String, _ attributes: [String: String]) -> DataSet {
            let result = DataSet(); _ = result.set(value: level, forTagName: "QueryRetrieveLevel")
            for (key, value) in attributes { _ = result.set(value: value, forTagName: key) }
            return result
        }
        func context(_ model: String, options: DICOMQueryRetrieveOptions) -> DICOMServiceContext {
            DICOMServiceContext(callingAETitle: "SCU", calledAETitle: "SCP", remoteAddress: "localhost", userIdentity: nil,
                presentationContext: .init(id: 1, abstractSyntax: model, transferSyntax: TransferSyntax.explicitVRLittleEndian),
                queryRetrieveOptions: options, cancelled: { false })
        }
        let query = identifier("IMAGE", ["QueryRetrieveView": "ENHANCED", "SOPInstanceUID": "", "SOPClassUID": ""])
        let queryContext = context(DICOMSOPClass.studyRootFind, options: [.enhancedMultiFrameConversion, .relational])
        var found: [DataSet] = []
        for try await match in try await services.find(query, informationModel: DICOMSOPClass.studyRootFind, context: queryContext) { found.append(match) }
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].string(forTag: "QueryRetrieveView"), "ENHANCED")
        let uid = try XCTUnwrap(found[0].string(forTag: "SOPInstanceUID"))
        let request = identifier("IMAGE", ["QueryRetrieveView": "ENHANCED", "SOPInstanceUID": uid])
        let items = try await services.retrieve(request, informationModel: DICOMSOPClass.compositeInstanceRootGet,
            context: context(DICOMSOPClass.compositeInstanceRootGet, options: .enhancedMultiFrameConversion))
        XCTAssertEqual(items.map(\.sopInstanceUID), [uid])
        let original = try await archive.record(sourceData[0].string(forTag: "SOPInstanceUID")!)
        let derived = try await archive.record(uid)
        XCTAssertNotNil(original); XCTAssertNil(derived, "view does not overwrite or implicitly persist derived objects")
        let reopened = DICOMArchive(directory: directory)
        _ = try await reopened.scan()
        let again = try await reopened.queryRetrieveView(request)
        let stable = try await again.record(uid)
        XCTAssertNotNil(stable)
        let metadata = try await services.retrieve(request, informationModel: DICOMSOPClass.compositeInstanceRetrieveWithoutBulkDataGet,
            context: context(DICOMSOPClass.compositeInstanceRetrieveWithoutBulkDataGet, options: .enhancedMultiFrameConversion))
        XCTAssertNil(try decode(metadata[0]).element(forTagName: "PixelData"))
        XCTAssertEqual(metadata[0].sopInstanceUID, uid)
    }

    func testTransitiveCyclicReferencesAreClosed() throws {
        let image = source(1)
        let a = DcmSwiftIODValidationTests.secondaryCaptureImage(), b = DcmSwiftIODValidationTests.secondaryCaptureImage()
        _ = a.set(value: "1.2.826.0.1.3680043.10.888.1", forTagName: "SOPInstanceUID")
        _ = b.set(value: "1.2.826.0.1.3680043.10.888.2", forTagName: "SOPInstanceUID")
        func references(_ target: DataSet, _ sources: [DataSet]) throws -> DataSet {
            var object = try DICOMJSON.object(target)
            object["00082112"] = C.sequence(try sources.map { C.reference(try DICOMJSON.object($0)) })
            return try DICOMJSON.dataSet(object)
        }
        let objects = try [image, references(a, [b]), references(b, [a, image])].map { try DICOMRetrieveItem(dataSet: $0) }
        let view = try C.convert(objects, to: .enhanced)
        XCTAssertEqual(view.count, 3)
        let ids = Set(view.map(\.sopInstanceUID))
        for item in view where item.sopClassUID != C.legacyClasses[0] {
            let object = try DICOMJSON.object(decode(item))
            for reference in C.items(object, "00082112") { XCTAssertTrue(ids.contains(C.text(reference, "00081155"))) }
        }
        XCTAssertTrue(ids.isDisjoint(with: objects.map(\.sopInstanceUID)))
    }

    func testTimestampPairsAndFrameTimezoneArePreserved() throws {
        let first = source(1), second = source(2)
        _ = first.set(value: "120000", forTagName: "SeriesTime")
        _ = second.set(value: "20261022", forTagName: "SeriesDate")
        _ = second.set(value: "110000", forTagName: "SeriesTime")
        for data in [first,second] { _ = data.set(value: "+0200", forTagName: "TimezoneOffsetFromUTC") }
        _ = second.set(value: "20261022", forTagName: "AcquisitionDate")
        _ = second.set(value: "20261022110000+0100", forTagName: "AcquisitionDateTime")
        let enhanced = try C.convert([DICOMRetrieveItem(dataSet: first), DICOMRetrieveItem(dataSet: second)], to: .enhanced)
        let object = try DICOMJSON.object(decode(enhanced[0]))
        XCTAssertEqual(C.text(object, "00080021"), "20261021")
        XCTAssertEqual(C.text(object, "00080031"), "120000")
        XCTAssertEqual(C.text(C.items(C.items(object, "52009230")[0], "00209111")[0], "00189074"), "20261021120000+0200")
        let classic = try C.convert(enhanced, to: .classic)
        let recovered = try classic.map(decode).first { $0.textValues(forTag: "AcquisitionDateTime")?.first == "20261022110000+0100" }
        XCTAssertEqual(recovered?.textValues(forTag: "AcquisitionTime")?.first, "120000")
    }

    func testDerivedSourceReferencesAndAbsentVOIPreserveInformation() throws {
        let data = source(1)
        _ = data.set(value: "DERIVED\\PRIMARY\\AXIAL", forTagName: "ImageType")
        _ = data.remove(elementForTagName: "WindowCenter"); _ = data.remove(elementForTagName: "WindowWidth")
        var object = try DICOMJSON.object(data)
        object["00082112"] = C.sequence([C.reference(try DICOMJSON.object(source(2)))])
        let input = try DICOMRetrieveItem(dataSet: DICOMJSON.dataSet(object))
        let enhanced = try C.convert([input], to: .enhanced)
        let result = try DICOMJSON.object(decode(enhanced[0]))
        let frame = C.items(result, "52009230")[0]
        XCTAssertEqual(C.text(C.items(frame, "00189329")[0], "00089207"), "UNKNOWN")
        XCTAssertFalse(C.items(frame, "00089124").isEmpty)
        XCTAssertEqual(C.text(C.items(frame, "00289132")[0], "00281055"), "Full representable modality range")
        XCTAssertEqual(try DICOMNativePixelData(dataset: decode(enhanced[0])).storedValues(frame: 0), [10,11,12,13])
    }

    func testTrueEnhancedCTRecoveryAndFrameExtraction() throws {
        let legacy = try C.convert([DICOMRetrieveItem(dataSet: source(1)), DICOMRetrieveItem(dataSet: source(2))], to: .enhanced)[0]
        var object = try DICOMJSON.object(decode(legacy))
        object["00080016"] = C.attribute("UI", [C.trueClasses[0]])
        object["00080018"] = C.attribute("UI", ["1.2.826.0.1.3680043.10.999.777"])
        object["00080008"] = C.attribute("CS", ["DERIVED", "PRIMARY", "VOLUME", "NONE"])
        for (tag, value) in [("00189004", "PRODUCT"), ("00280301", "NO"), ("00282110", "00"),
                             ("00081090", "Test"), ("00181000", "Test"), ("00181020", "Test")] {
            object[tag] = C.attribute(tag == "00181000" || tag == "00181020" || tag == "00081090" ? "LO" : "CS", [value])
        }
        object["52009229"] = C.sequence([[:]])
        object["00209221"] = C.sequence([["00209164": C.attribute("UI", [C.uid("true CT dimensions")])]])
        var frames = C.items(object, "52009230")
        for i in frames.indices {
            frames[i].removeValue(forKey: "00209171"); frames[i].removeValue(forKey: "00209172")
            var type = C.items(frames[i], "00189329")[0]
            type["00089007"] = object["00080008"]; frames[i]["00189329"] = C.sequence([type])
            frames[i]["00189477"] = C.sequence([["00083010": C.attribute("UI", ["1.2.826.0.1.3680043.10.999.778"])]])
        }
        object["52009230"] = C.sequence(frames)
        for tag in ["00280030", "00200032", "00200037", "00180050", "00281052", "00281053", "00281054", "00281050", "00281051", "00200012", "00180060"] { object.removeValue(forKey: tag) }
        let enhanced = try DICOMJSON.dataSet(object)
        let validation = DICOMIODValidator().validate(enhanced)
        XCTAssertTrue(validation.isValid, validation.findings.map(\.description).joined(separator: "\n"))
        let item = try DICOMRetrieveItem(dataSet: enhanced)
        let recovered = try C.convert([item], to: .classic)
        XCTAssertEqual(recovered.count, 2)
        for classic in recovered { XCTAssertTrue(DICOMIODValidator().validate(try decode(classic)).isValid) }
        let request = DataSet()
        _ = request.set(value: "FRAME", forTagName: "QueryRetrieveLevel")
        _ = request.set(value: item.sopInstanceUID, forTagName: "SOPInstanceUID")
        _ = request.set(value: [UInt32(2)], forTagName: "SimpleFrameList")
        let extracted = try DICOMFrameExtraction.extract(item, identifier: request)
        XCTAssertEqual(extracted.sopClassUID, C.trueClasses[0])
        XCTAssertTrue(DICOMIODValidator().validate(try decode(extracted)).isValid)
        XCTAssertEqual(try DICOMNativePixelData(dataset: decode(extracted)).storedValues(frame: 0), [20,21,22,23])
    }

}
