import Foundation
import XCTest
@testable import DcmSwift

/// PS3.16 report templates: TID 2000, 2010, the dose reports, CAD and
/// ultrasound readers, each through an encoded data set and back.
final class DcmSwiftReportTemplateTests: XCTestCase {
    private func roundTrip(_ document: DICOMStructuredReport, context: DataSet? = nil) throws -> (DICOMStructuredReport, DataSet) {
        let dataSet = document.dataSet(context: context)
        dataSet.hasPreamble = true
        _ = dataSet.set(value: "1.2.826.0.1.3680043.10.999", forTagName: "ImplementationClassUID")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sr-template-\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(try DicomOutputStream(url: url).write(dataset: dataSet))
        let read = try XCTUnwrap(try DicomInputStream(url: url).readDataset())
        return (try XCTUnwrap(DICOMStructuredReport(dataSet: read)), read)
    }

    private let image = DICOMSRReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.826.0.1.3680043.10.9.1",
                                         studyInstanceUID: "1.2.826.0.1.3680043.10.9", seriesInstanceUID: "1.2.826.0.1.3680043.10.9.10")

    func testDiagnosticImagingReportRoundTrip() throws {
        typealias H = DICOMDiagnosticImagingReport.Headings
        let report = DICOMDiagnosticImagingReport(
            title: H.radiologyReport, language: DICOMCode("fr-FR", scheme: "RFC5646", meaning: "French (France)"),
            observers: [.person(name: "Martin^Claire", organization: "Radiologie Nord")],
            procedures: [DICOMCode("77477000", scheme: "SCT", meaning: "CT")],
            sections: [
                .init(heading: H.indications, observations: [.text("Douleur thoracique", concept: DICOMDiagnosticImagingReport.element(for: H.indications))]),
                .init(heading: H.findings, observations: [
                    .init(concept: H.finding, value: .text("Nodule de 8 mm"),
                          inferredFrom: [.init(purpose: DICOMCode("121080", scheme: "DCM", meaning: "Best illustration of finding"), reference: image)]),
                    .init(concept: H.finding, value: .code(DICOMCode("27925004", scheme: "SCT", meaning: "Nodule"))),
                ]),
                .init(heading: H.conclusions, observer: .person(name: "Durand^Paul"),
                      observations: [.text("Contrôle à 3 mois", concept: H.conclusion)]),
            ])
        var document = report.document(completionFlag: "COMPLETE", verificationFlag: "VERIFIED")
        document.preliminaryFlag = "FINAL"
        document.verifyingObservers = [.init(name: "Martin^Claire", organization: "Radiologie Nord", dateTime: "20261028120000")]
        document.predecessorDocuments = [DICOMSRReference(sopClassUID: DICOMStructuredReport.basicTextSR, sopInstanceUID: "1.2.3.4.5",
                                                          studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")]
        let (read, dataSet) = try roundTrip(document)
        XCTAssertEqual(dataSet.string(forTag: "SOPClassUID"), DICOMStructuredReport.basicTextSR)
        XCTAssertEqual(read.template?.identifier, "2000")
        XCTAssertEqual(read.preliminaryFlag, "FINAL")
        XCTAssertEqual(read.verificationFlag, "VERIFIED")
        XCTAssertEqual(read.verifyingObservers.first?.organization, "Radiologie Nord")
        XCTAssertEqual(read.predecessorDocuments.first?.seriesInstanceUID, "1.2.3.4")
        let back = try XCTUnwrap(DICOMDiagnosticImagingReport(document: read))
        XCTAssertTrue(back.title.sameConcept(as: H.radiologyReport))
        XCTAssertEqual(back.language?.value, "fr-FR")
        XCTAssertEqual(back.observers, [.person(name: "Martin^Claire", organization: "Radiologie Nord", role: nil)])
        XCTAssertEqual(back.procedures.first?.value, "77477000")
        XCTAssertEqual(back.sections.map(\.heading.value), ["18785-6", "59776-5", "55110-1"])
        XCTAssertEqual(back.sections[1].observations.count, 2)
        XCTAssertEqual(back.sections[1].observations[0].inferredFrom.first?.reference.sopInstanceUID, image.sopInstanceUID)
        XCTAssertEqual(back.sections[2].observer, .person(name: "Durand^Paul", organization: nil, role: nil))
        XCTAssertTrue(back.text.contains("Nodule de 8 mm"))
        // The evidence names the referenced study and series.
        let evidence = DICOMStructuredReport.hierarchicalReferences(dataSet.element(forTagName: "CurrentRequestedProcedureEvidenceSequence"))
        XCTAssertEqual(evidence.first?.seriesInstanceUID, image.seriesInstanceUID)
        // A document of another template is not read as TID 2000.
        XCTAssertNil(DICOMDiagnosticImagingReport(document: DICOMKeyObjectSelection(references: [image]).document()))
    }

    func testKeyObjectSelectionRoundTrip() throws {
        var second = image
        second.sopInstanceUID = "1.2.826.0.1.3680043.10.9.2"
        second.seriesInstanceUID = "1.2.826.0.1.3680043.10.9.11"
        let pdf = DICOMSRReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.104.1", sopInstanceUID: "1.2.826.0.1.3680043.10.9.3",
                                   studyInstanceUID: image.studyInstanceUID, seriesInstanceUID: "1.2.826.0.1.3680043.10.9.12")
        let selection = DICOMKeyObjectSelection(title: DICOMKeyObjectSelection.Titles.rejectedForQualityReasons,
                                                modifiers: [DICOMCode("111210", scheme: "DCM", meaning: "Motion blur")],
                                                observers: [.person(name: "Tech^Anne")], description: "Flou",
                                                references: [image, second, pdf])
        let (read, dataSet) = try roundTrip(selection.document())
        XCTAssertEqual(dataSet.string(forTag: "Modality"), "KO")
        XCTAssertNil(dataSet.element(forTagName: "CompletionFlag"))
        XCTAssertNil(dataSet.element(forTagName: "VerificationFlag"))
        var back = try XCTUnwrap(DICOMKeyObjectSelection(document: read))
        XCTAssertTrue(back.title.sameConcept(as: DICOMKeyObjectSelection.Titles.rejectedForQualityReasons))
        XCTAssertEqual(back.modifiers.first?.value, "111210")
        XCTAssertEqual(back.description, "Flou")
        XCTAssertEqual(back.references.map(\.sopInstanceUID), [image, second, pdf].map(\.sopInstanceUID))
        XCTAssertTrue(read.root.children.contains { if case .composite = $0.value { return true }; return false })
        back.locate(in: dataSet)
        XCTAssertEqual(back.references.map(\.seriesInstanceUID), [image, second, pdf].map(\.seriesInstanceUID))
    }

    func testCTDoseReportRoundTrip() throws {
        typealias C = DICOMRadiationDoseReport.Codes
        let chest = DICOMCode("43799004", scheme: "SCT", meaning: "Chest")
        let acquisitions = [
            DICOMRadiationDoseReport.CTAcquisition(protocolName: "Thorax", targetRegion: chest, ctdiVol: 6.2, dlp: 210.5,
                exposureTime: 4.1, scanningLength: 340, singleCollimationWidth: 0.625, totalCollimationWidth: 40, pitchFactor: 0.984,
                kvp: 120, maximumTubeCurrent: 300, tubeCurrent: 180, exposureTimePerRotation: 0.5),
            DICOMRadiationDoseReport.CTAcquisition(protocolName: "Repérage", targetRegion: chest, type: DICOMCode("113805", scheme: "DCM",
                meaning: "Constant Angle Acquisition"), ctdiVol: 0.1, dlp: 3.2, exposureTime: 2, scanningLength: 400,
                singleCollimationWidth: 0.625, totalCollimationWidth: 0.625, kvp: 100, maximumTubeCurrent: 20, tubeCurrent: 20),
        ]
        let document = DICOMRadiationDoseReport.ct(device: .device(uid: "1.2.826.0.1.3680043.10.9.99", name: "CT_SALLE1", manufacturer: "Synthetic"),
                                                   studyInstanceUID: "1.2.826.0.1.3680043.10.9", start: "20261028100000",
                                                   end: "20261028100500", acquisitions: acquisitions)
        let (read, dataSet) = try roundTrip(document)
        XCTAssertEqual(dataSet.string(forTag: "SOPClassUID"), DICOMStructuredReport.xRayRadiationDose)
        let report = try XCTUnwrap(DICOMRadiationDoseReport(document: read))
        XCTAssertEqual(report.kind, .ct)
        XCTAssertEqual(report.studyInstanceUID, "1.2.826.0.1.3680043.10.9")
        XCTAssertEqual(try XCTUnwrap(report.ctDoseLengthProductTotal), 213.7, accuracy: 0.001)
        XCTAssertEqual(report.accumulated(C.totalNumberOfIrradiationEvents)?.value, 2)
        XCTAssertEqual(report.events.count, 2)
        XCTAssertEqual(report.events[0].protocolName, "Thorax")
        XCTAssertEqual(report.events[0].value(C.meanCTDIvol)?.value, 6.2)
        XCTAssertEqual(report.events[0].value(C.kvp)?.units?.value, "kV")
        XCTAssertEqual(report.events[1].type?.value, "113805")
        XCTAssertEqual(report.events[0].targetRegion?.value, "43799004")
        guard case .device(let uid, let name, _, _, _)? = report.observers.first else { return XCTFail("device observer") }
        XCTAssertEqual(uid, "1.2.826.0.1.3680043.10.9.99")
        XCTAssertEqual(name, "CT_SALLE1")
    }

    func testProjectionAndRadiopharmaceuticalDoseReportsAreRead() throws {
        typealias C = DICOMRadiationDoseReport.Codes
        let gym2 = DICOMCode("Gy.m2", scheme: "UCUM", meaning: "Gy.m2")
        func num(_ concept: DICOMCode, _ value: Double, _ units: String) -> DICOMSRContentItem {
            DICOMSRContentItem("CONTAINS", concept, .number(value, units: DICOMCode(units, scheme: "UCUM", meaning: units), qualifier: nil))
        }
        let projection = DICOMStructuredReport(sopClassUID: DICOMStructuredReport.xRayRadiationDose, template: ("DCMR", "10001"),
            root: DICOMSRContentItem(nil, C.xRayRadiationDoseReport, .container(continuity: "SEPARATE"), children: [
                DICOMSRContentItem("HAS CONCEPT MOD", DICOMSRCodes.procedureReported, .code(C.projectionXRay)),
                DICOMSRContentItem("CONTAINS", C.accumulatedXRayDoseData, .container(continuity: "SEPARATE"), children: [
                    DICOMSRContentItem("CONTAINS", C.doseAreaProductTotal, .number(0.0012, units: gym2, qualifier: nil)),
                    num(C.totalFluoroTime, 95, "s"),
                ]),
                DICOMSRContentItem("CONTAINS", C.irradiationEventXRayData, .container(continuity: "SEPARATE"), children: [
                    DICOMSRContentItem("CONTAINS", C.irradiationEventUID, .uidReference("1.2.3.9")),
                    DICOMSRContentItem("CONTAINS", C.dateTimeStarted, .dateTime("20261028101010")),
                    DICOMSRContentItem("CONTAINS", C.doseAreaProduct, .number(0.0004, units: gym2, qualifier: nil)),
                ]),
            ]))
        let x = try XCTUnwrap(DICOMRadiationDoseReport(document: try roundTrip(projection).0))
        XCTAssertEqual(x.kind, .projectionXRay)
        XCTAssertEqual(x.accumulated(C.doseAreaProductTotal)?.value, 0.0012)
        XCTAssertEqual(x.events.first?.uid, "1.2.3.9")
        XCTAssertEqual(x.events.first?.startedAt, "20261028101010")

        let nuclear = DICOMStructuredReport(sopClassUID: DICOMStructuredReport.radiopharmaceuticalRadiationDose,
            root: DICOMSRContentItem(nil, C.radiopharmaceuticalRadiationDoseReport, .container(continuity: "SEPARATE"), children: [
                DICOMSRContentItem("CONTAINS", C.radiopharmaceuticalAdministration, .container(continuity: "SEPARATE"), children: [
                    DICOMSRContentItem("CONTAINS", C.administrationEventUID, .uidReference("1.2.3.10")),
                    num(C.administeredActivity, 350, "MBq"),
                ]),
            ]))
        let n = try XCTUnwrap(DICOMRadiationDoseReport(document: try roundTrip(nuclear).0))
        XCTAssertEqual(n.kind, .radiopharmaceutical)
        XCTAssertEqual(n.events.first?.value(C.administeredActivity)?.value, 350)
        XCTAssertNil(DICOMRadiationDoseReport(document: DICOMKeyObjectSelection(references: [image]).document()))
    }

    func testMammographyCADFindingsAreRead() throws {
        typealias C = DICOMCADReport.Codes
        let mass = DICOMCode("4147007", scheme: "SCT", meaning: "Mass")
        let required = DICOMCode("111150", scheme: "DCM", meaning: "Presentation Required: Rendering device is expected to present")
        func single(_ x: Double) -> DICOMSRContentItem {
            DICOMSRContentItem("INFERRED FROM", C.singleImageFinding, .code(mass), children: [
                DICOMSRContentItem("HAS PROPERTIES", C.renderingIntent, .code(required)),
                DICOMSRContentItem("HAS PROPERTIES", C.certaintyOfFinding, .number(87, units: DICOMCode("%", scheme: "UCUM", meaning: "%"), qualifier: nil)),
                DICOMSRContentItem("HAS PROPERTIES", DICOMCode("111010", scheme: "DCM", meaning: "Center"),
                                   .spatialCoordinates(graphicType: "POINT", points: [x, 200]),
                                   children: [DICOMSRContentItem("SELECTED FROM", nil, .image(image))]),
            ])
        }
        let document = DICOMStructuredReport(sopClassUID: DICOMStructuredReport.mammographyCAD, template: ("DCMR", "4000"),
            root: DICOMSRContentItem(nil, C.mammographyCADReport, .container(continuity: "SEPARATE"), children: [
                DICOMSRContentItem("CONTAINS", C.summary, .code(DICOMCode("111242", scheme: "DCM", meaning: "All algorithms succeeded; with findings")),
                                   children: [
                    DICOMSRContentItem("INFERRED FROM", C.compositeFeature, .code(mass), children: [
                        DICOMSRContentItem("HAS PROPERTIES", C.renderingIntent, .code(required)),
                        single(100), single(110),
                    ]),
                    DICOMSRContentItem("INFERRED FROM", C.singleImageFinding, .code(mass)),
                ]),
                DICOMSRContentItem("CONTAINS", DICOMCode("111064", scheme: "DCM", meaning: "Summary of Detections"), .code(DICOMCode("111222", scheme: "DCM", meaning: "Succeeded")), children: [
                    DICOMSRContentItem("INFERRED FROM", DICOMCode("111063", scheme: "DCM", meaning: "Successful Detections"), .container(continuity: "SEPARATE"), children: [
                        DICOMSRContentItem("CONTAINS", C.algorithmName, .text("SyntheticCAD")),
                        DICOMSRContentItem("HAS PROPERTIES", C.algorithmVersion, .text("1.0")),
                    ]),
                ]),
            ]))
        let report = try XCTUnwrap(DICOMCADReport(document: try roundTrip(document).0))
        XCTAssertEqual(report.kind, .mammography)
        XCTAssertEqual(report.summary?.value, "111242")
        XCTAssertEqual(report.findings.count, 2)
        XCTAssertTrue(report.findings[0].composite)
        XCTAssertEqual(report.findings[0].components.count, 2)
        XCTAssertEqual(report.findings[0].components[0].certainty, 87)
        XCTAssertEqual(report.findings[0].components[1].locations.first?.points, [110, 200])
        XCTAssertEqual(report.findings[0].components[0].locations.first?.image?.sopInstanceUID, image.sopInstanceUID)
        XCTAssertEqual(report.algorithms, [.init(name: "SyntheticCAD", version: "1.0")])
    }

    func testUltrasoundMeasurementsKeepTheirContext() throws {
        typealias C = DICOMUltrasoundReport.Codes
        let right = DICOMCode("24028007", scheme: "SCT", meaning: "Right")
        let left = DICOMCode("7771000", scheme: "SCT", meaning: "Left")
        let carotid = DICOMCode("69105007", scheme: "SCT", meaning: "Carotid Artery")
        let psv = DICOMCode("11726-7", scheme: "LN", meaning: "Peak Systolic Velocity")
        let cms = DICOMCode("cm/s", scheme: "UCUM", meaning: "cm/s")
        let section = DICOMCode("121070", scheme: "DCM", meaning: "Findings")
        let document = DICOMStructuredReport(template: ("DCMR", "5100"),
            root: DICOMSRContentItem(nil, C.vascularReport, .container(continuity: "SEPARATE"), children: [
                DICOMSRContentItem("CONTAINS", section, .container(continuity: "SEPARATE"), children: [
                    DICOMSRContentItem("HAS CONCEPT MOD", C.findingSite, .code(carotid)),
                    DICOMSRContentItem("HAS CONCEPT MOD", C.laterality, .code(right)),
                    DICOMSRContentItem("CONTAINS", psv, .number(85, units: cms, qualifier: nil)),
                    DICOMSRContentItem("CONTAINS", psv, .number(91, units: cms, qualifier: nil), children: [
                        DICOMSRContentItem("HAS CONCEPT MOD", C.laterality, .code(left)),
                    ]),
                ]),
            ]))
        let report = try XCTUnwrap(DICOMUltrasoundReport(document: try roundTrip(document).0))
        XCTAssertEqual(report.kind, .vascular)
        XCTAssertEqual(report.measurements.map(\.value), [85, 91])
        XCTAssertEqual(report.measurements[0].path.first?.value, "121070")
        XCTAssertEqual(report.measurements[0].modifier(C.laterality), right)
        XCTAssertEqual(report.measurements[1].modifier(C.laterality), left)
        XCTAssertEqual(report.measurements[1].modifier(C.findingSite), carotid)
    }

    /// Every code the templates write has the meaning PS3.16 gives it.
    func testTemplateCodesMatchTheTerminology() {
        typealias H = DICOMDiagnosticImagingReport.Headings
        typealias D = DICOMRadiationDoseReport.Codes
        typealias K = DICOMKeyObjectSelection.Titles
        let codes: [DICOMCode] = [
            DICOMSRCodes.language, DICOMSRCodes.observerType, DICOMSRCodes.person, DICOMSRCodes.device, DICOMSRCodes.personObserverName,
            DICOMSRCodes.personObserverOrganization, DICOMSRCodes.personObserverRoleInOrganization, DICOMSRCodes.personObserverRoleInProcedure,
            DICOMSRCodes.deviceObserverUID, DICOMSRCodes.deviceObserverName, DICOMSRCodes.deviceObserverManufacturer,
            DICOMSRCodes.deviceObserverModelName, DICOMSRCodes.deviceObserverSerialNumber, DICOMSRCodes.procedureReported,
            DICOMSRCodes.documentTitleModifier, DICOMSRCodes.keyObjectDescription,
            H.diagnosticImagingReport, H.radiologyReport, H.history, H.request, H.currentProcedureDescriptions, H.priorProcedureDescriptions,
            H.previousFindings, H.findings, H.impressions, H.recommendations, H.conclusions, H.addendum, H.indications,
            H.patientPresentation, H.complications, H.summary, H.keyImages, H.radiationExposure, H.clinicalInformation,
            H.medicationsAdministered, H.criticalResults, H.procedureDescription, H.previousFinding, H.finding, H.impression,
            H.recommendation, H.conclusion, H.complicationOfProcedure,
            K.ofInterest, K.rejectedForQualityReasons, K.forReferringProvider, K.forSurgery, K.forTeaching, K.qualityIssue,
            K.rejectedForPatientSafetyReasons, K.incorrectModalityWorklistEntry, K.dataRetentionPolicyExpired,
            D.xRayRadiationDoseReport, D.radiopharmaceuticalRadiationDoseReport, D.patientRadiationDoseReport, D.projectionXRay,
            D.scopeOfAccumulation, D.study, D.studyInstanceUID, D.deviceRoleInProcedure, D.irradiatingDevice,
            D.sourceOfDoseInformation, D.automatedDataCollection, D.startOfXRayIrradiation, D.endOfXRayIrradiation,
            D.ctAccumulatedDoseData, D.totalNumberOfIrradiationEvents, D.ctDoseLengthProductTotal, D.ctEffectiveDoseTotal,
            D.ctAcquisition, D.ctAcquisitionType, D.irradiationEventUID, D.ctAcquisitionParameters, D.exposureTime, D.scanningLength,
            D.nominalSingleCollimationWidth, D.nominalTotalCollimationWidth, D.pitchFactor, D.numberOfXRaySources,
            D.ctXRaySourceParameters, D.identificationOfTheXRaySource, D.kvp, D.maximumXRayTubeCurrent, D.xRayTubeCurrent,
            D.exposureTimePerRotation, D.ctDose, D.meanCTDIvol, D.ctdiwPhantomType, D.dlp, D.effectiveDose, D.headPhantom,
            D.bodyPhantom, D.spiralAcquisition, D.sequencedAcquisition, D.acquisitionProtocol, D.targetRegion,
            D.accumulatedXRayDoseData, D.irradiationEventXRayData, D.irradiationEventType, D.dateTimeStarted,
            D.doseAreaProductTotal, D.doseRPTotal, D.totalFluoroTime, D.doseAreaProduct, D.doseRP,
            D.radiopharmaceuticalAdministration, D.administrationEventUID, D.administeredActivity, D.radiopharmaceuticalStart,
            DICOMCADReport.Codes.mammographyCADReport, DICOMCADReport.Codes.chestCADReport, DICOMCADReport.Codes.summary,
            DICOMCADReport.Codes.singleImageFinding, DICOMCADReport.Codes.compositeFeature, DICOMCADReport.Codes.renderingIntent,
            DICOMCADReport.Codes.certaintyOfFinding, DICOMCADReport.Codes.algorithmName, DICOMCADReport.Codes.algorithmVersion,
            DICOMUltrasoundReport.Codes.obstetricGynecologicReport, DICOMUltrasoundReport.Codes.vascularReport,
            DICOMUltrasoundReport.Codes.echocardiographyReport, DICOMUltrasoundReport.Codes.derivation,
        ]
        let terminology = DICOMTerminology.shared
        for code in codes {
            XCTAssertEqual(terminology.meaning(of: code), code.meaning, "\(code)")
        }
        // The headings and elements belong to their Context Groups.
        for heading in [H.history, H.findings, H.impressions, H.conclusions, H.indications, H.addendum] {
            XCTAssertEqual(terminology.membership(of: heading, in: 7001), .member, "\(heading)")
        }
        for element in [H.finding, H.impression, H.conclusion, H.procedureDescription] {
            XCTAssertEqual(terminology.membership(of: element, in: 7002), .member, "\(element)")
        }
    }

    // MARK: Template validation

    private func errors(_ issues: [DICOMSRValidationIssue]) -> [DICOMSRValidationIssue] { issues.filter { $0.severity == .error } }

    func testDocumentsMadeByTheBuildersValidate() {
        typealias H = DICOMDiagnosticImagingReport.Headings
        let report = DICOMDiagnosticImagingReport(observers: [.person(name: "Martin^Claire")],
            sections: [.init(heading: H.findings, observations: [.text("RAS", concept: H.finding)], images: [.init(reference: image)])])
        XCTAssertEqual(DICOMSRTemplateValidator.validate(report.document()), [])
        XCTAssertEqual(DICOMSRTemplateValidator.validate(DICOMKeyObjectSelection(description: "Clé", references: [image]).document()), [])
        let dose = DICOMRadiationDoseReport.ct(device: .device(uid: "1.2.3.99"), studyInstanceUID: "1.2.3", start: "20261028100000",
            end: "20261028100100", acquisitions: [.init(protocolName: "Thorax", targetRegion: DICOMCode("43799004", scheme: "SCT", meaning: "Chest"),
            ctdiVol: 5, dlp: 200, exposureTime: 3, scanningLength: 300, singleCollimationWidth: 0.6, totalCollimationWidth: 38.4,
            pitchFactor: 1, kvp: 120, maximumTubeCurrent: 200, tubeCurrent: 150, exposureTimePerRotation: 0.5)])
        XCTAssertEqual(errors(DICOMSRTemplateValidator.validate(dose)), [], "\(DICOMSRTemplateValidator.validate(dose))")
    }

    func testValidationReportsTemplateAndIODErrors() {
        typealias H = DICOMDiagnosticImagingReport.Headings
        // TID 2000 without any section, VERIFIED without verifier, a NUM in Basic Text SR.
        var document = DICOMDiagnosticImagingReport(sections: []).document(verificationFlag: "VERIFIED")
        document.root.children.append(DICOMSRContentItem("CONTAINS", H.finding, .number(3, units: nil, qualifier: nil)))
        let issues = errors(DICOMSRTemplateValidator.validate(document))
        XCTAssertTrue(issues.contains { $0.message.contains("missing CONTAINS CONTAINER from CID 7001") }, "\(issues)")
        XCTAssertTrue(issues.contains { $0.message.contains("Verifying Observer") })
        XCTAssertTrue(issues.contains { $0.path == "1.1" && $0.message.contains("NUM is not allowed") })

        // Key Object Selection: non-extensible, needs a reference.
        var ko = DICOMKeyObjectSelection(references: []).document()
        ko.root.children.append(DICOMSRContentItem("CONTAINS", H.finding, .text("hors gabarit")))
        let koIssues = errors(DICOMSRTemplateValidator.validate(ko))
        XCTAssertTrue(koIssues.contains { $0.message.contains("missing CONTAINS IMAGE/WAVEFORM/COMPOSITE") }, "\(koIssues)")
        XCTAssertTrue(koIssues.contains { $0.message.contains("is not part of the template") })

        // CT dose: a coded value outside a non-extensible group, a missing total.
        typealias C = DICOMRadiationDoseReport.Codes
        var dose = DICOMRadiationDoseReport.ct(device: .device(uid: "1.2.3.99"), studyInstanceUID: "1.2.3", start: "20261028100000",
            end: "20261028100100", acquisitions: [.init(protocolName: "Thorax", targetRegion: DICOMCode("43799004", scheme: "SCT", meaning: "Chest"),
            ctdiVol: 5, dlp: 200, exposureTime: 3, scanningLength: 300, singleCollimationWidth: 0.6, totalCollimationWidth: 38.4,
            kvp: 120, maximumTubeCurrent: 200, tubeCurrent: 150)])
        let accumulated = dose.root.children.firstIndex { $0.conceptName?.sameConcept(as: C.ctAccumulatedDoseData) == true }!
        dose.root.children[accumulated].children.removeAll { $0.conceptName?.sameConcept(as: C.ctDoseLengthProductTotal) == true }
        dose.root.children[0] = DICOMSRContentItem("HAS OBS CONTEXT", DICOMSRCodes.observerType, .code(DICOMCode("999", scheme: "DCM", meaning: "Robot")))
        let doseIssues = errors(DICOMSRTemplateValidator.validate(dose))
        XCTAssertTrue(doseIssues.contains { $0.message.contains("missing CONTAINS NUM (113813") }, "\(doseIssues)")
        XCTAssertTrue(doseIssues.contains { $0.message.contains("missing HAS CONCEPT MOD CODE (121058") })
        XCTAssertTrue(doseIssues.contains { $0.message.contains("not in CID 270") })
    }

    /// The data sets of the builders also pass IOD validation (PS3.3).
    func testBuilderDataSetsPassIODValidation() throws {
        typealias H = DICOMDiagnosticImagingReport.Headings
        let context = DcmSwiftIODValidationTests.secondaryCaptureImage()
        let documents = [
            DICOMDiagnosticImagingReport(sections: [.init(heading: H.findings, observations: [.text("RAS", concept: H.finding)])]).document(),
            DICOMKeyObjectSelection(references: [image]).document(),
            DICOMRadiationDoseReport.ct(device: .device(uid: "1.2.3.99", manufacturer: "Synthetic", model: "CT-1", serialNumber: "42"),
                studyInstanceUID: "1.2.3", start: "20261028100000", end: "20261028100100", acquisitions: [], softwareVersions: "1.0"),
        ]
        for document in documents {
            let report = DICOMIODValidator().validate(document.dataSet(context: context))
            XCTAssertEqual(report.findings.map { "\($0.module) \($0.path) \($0.message)" }, [], document.sopClassUID)
        }
    }
}

