//
//  DcmSwiftTestsDicomdir.swift
//  
//
//  Created by Colombe on 09/07/2021.
//

import XCTest
@testable import DcmSwift

/**
 */
class DcmSwiftTestsDicomdir: XCTestCase {
    //MARK: TESTS DICOMDIR

    func testParseDicomDir() {
        
    }
    
    func testIsDicomDir() {
        let dicomDirPaths       = Bundle.module.paths(forResourcesOfType: "dicomdir", inDirectory: nil)
        let notDicomDirPaths    = Bundle.module.paths(forResourcesOfType: "notdicomdir", inDirectory: nil)
        
        
        if let pathTrue = dicomDirPaths.first {
            let b:Bool = DicomDir.isDicomDir(forPath:pathTrue)
            XCTAssertTrue(b)
        }
        
        if let pathFalse = notDicomDirPaths.first {
            let p:Bool = DicomDir.isDicomDir(forPath:pathFalse)
            XCTAssertFalse(p)
        }
    }
    
    func testIndex() {
        let pathFolder = "/Users/home/Documents/2_skull_ct/DICOM"
        if let dir = DicomDir.parse(atPath: pathFolder) {
            for(a,b) in dir.studies {
                Logger.info("a : \(a) b : \(b)")
            }
        }
    }
    
    func testIndexForStudy() {
        
    }
    
    func testAmputation() {
        let path = "/Users/home/Desktop/DICOM Example/TEST_DICOMDIR/DICOMDIR"
        let path_2 = "/Users/home/Desktop/DICOM Example/TEST_DICOMDIR"
        XCTAssertEqual(DicomDir.amputation(forPath: path),path_2)
    }
    
    func testCreateDirectoryRecordSequence() {
        let directory = makeDirectory()
        let sequence = directory.createDirectoryRecordSequence()

        XCTAssertEqual(sequence?.items.count, 5)
        XCTAssertEqual(
            (sequence?.items.first?.element(withName: "DirectoryRecordType")?.value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "PATIENT"
        )
    }

    func testDirectoryRecordTypeRegistryAndLosslessGenericView() throws {
        XCTAssertTrue(DICOMDirectoryRecordType.standard2026d.contains(.rtDose))
        XCTAssertTrue(DICOMDirectoryRecordType.standard2026d.contains(.waveformPresentation))
        XCTAssertTrue(DICOMDirectoryRecordType.standard2026d.contains(.private))
        XCTAssertEqual(
            DICOMDirectoryRecordType.unconditionalKeyValidation2026d,
            DICOMDirectoryRecordType.standard2026d
        )
        for requirements in DICOMDirectoryRecordSchemas.requirements.values {
            for key in requirements.keys {
                XCTAssertNotNil(DicomSpec.shared.dataTag(forName: key), key)
            }
        }
        for keys in DICOMDirectoryRecordSchemas.conditionalType1Keys.values {
            for key in keys {
                XCTAssertNotNil(DicomSpec.shared.dataTag(forName: key), key)
            }
        }
        for keys in DICOMDirectoryRecordSchemas.referencedInstanceConditionalKeys.values {
            for key in keys {
                XCTAssertNotNil(DicomSpec.shared.dataTag(forName: key), key)
            }
        }
        XCTAssertEqual(
            DICOMDirectoryRecordSchemas.specificCharacterSetTypes,
            DICOMDirectoryRecordType.standard2026d.subtracting([
                .implant, .implantAssembly, .implantGroup, .private
            ])
        )

        let directory = makeDirectory()
        let sequence = try XCTUnwrap(directory.createDirectoryRecordSequence())
        let imageItem = try XCTUnwrap(sequence.items.first {
            ($0.element(withName: "DirectoryRecordType")?.value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) == "IMAGE"
        })
        XCTAssertTrue(imageItem.element(withName: "DirectoryRecordType")?.setValue("VENDOR RECORD") == true)
        let privateTag = DataTag(withGroup: "0011", element: "1010")
        let privateElement = DataElement(withTag: privateTag, dataset: directory.dataset, parent: imageItem)
        privateElement.vr = .UN
        XCTAssertTrue(privateElement.setValue(Data([0xde, 0xad, 0xbe, 0xef])))
        imageItem.elements.append(privateElement)
        let dataSet = DataSet()
        dataSet.add(element: sequence)
        directory.dataset = dataSet

        let record = try XCTUnwrap(directory.directoryRecords.first { $0.type?.rawValue == "VENDOR RECORD" })
        XCTAssertFalse(DICOMDirectoryRecordType.standard2026d.contains(try XCTUnwrap(record.type)))
        XCTAssertTrue(record.elements.contains { $0 === privateElement })
        XCTAssertEqual(privateElement.data, Data([0xde, 0xad, 0xbe, 0xef]))
    }

    func testDirectoryRecordKeyValidationCoversBasicAndRTRecords() throws {
        let directory = makeDirectory()
        let dataSet = DataSet()
        let sequence = try XCTUnwrap(directory.createDirectoryRecordSequence())
        dataSet.add(element: sequence)
        directory.dataset = dataSet
        XCTAssertTrue(directory.validateDirectoryRecordKeys().isEmpty)

        let study = try XCTUnwrap(sequence.items.first {
            ($0.element(withName: "DirectoryRecordType")?.value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) == "STUDY"
        })
        XCTAssertTrue(study.element(withName: "StudyID")?.setValue("") == true)
        study.elements.removeAll { $0.name == "AccessionNumber" }
        var messages = directory.validateDirectoryRecordKeys().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("empty Type 1 key StudyID") })
        XCTAssertTrue(messages.contains { $0.contains("missing Type 2 key AccessionNumber") })

        XCTAssertTrue(study.element(withName: "StudyID")?.setValue("STUDY1") == true)
        append(value: "", name: "AccessionNumber", to: study, dataSet: dataSet)
        let image = try XCTUnwrap(sequence.items.first {
            ($0.element(withName: "DirectoryRecordType")?.value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) == "IMAGE"
        })
        XCTAssertTrue(image.element(withName: "DirectoryRecordType")?.setValue("RT DOSE") == true)
        messages = directory.validateDirectoryRecordKeys().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("missing Type 1 key DoseSummationType") })

        append(value: "PLAN", name: "DoseSummationType", to: image, dataSet: dataSet)
        XCTAssertTrue(directory.validateDirectoryRecordKeys().isEmpty)

        XCTAssertTrue(image.element(withName: "DirectoryRecordType")?.setValue("WAVEFORM") == true)
        messages = directory.validateDirectoryRecordKeys().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("missing Type 1 key ContentDate") })
        XCTAssertTrue(messages.contains { $0.contains("missing Type 1 key ContentTime") })
    }

    func testDirectoryRecordConditionalKeyValidation() throws {
        let directory = makeDirectory()
        let dataSet = DataSet()
        let sequence = try XCTUnwrap(directory.createDirectoryRecordSequence())
        dataSet.add(element: sequence)
        directory.dataset = dataSet

        let image = try XCTUnwrap(sequence.items.first {
            ($0.element(withName: "DirectoryRecordType")?.value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) == "IMAGE"
        })
        image.elements.removeAll { $0.name == "ReferencedSOPInstanceUIDInFile" }
        var messages = directory.validateDirectoryRecordKeys().map(\.message)
        XCTAssertTrue(messages.contains {
            $0.contains("requires Type 1C key ReferencedSOPInstanceUIDInFile")
        })

        append(value: "1.2.3.4", name: "ReferencedSOPInstanceUIDInFile", to: image, dataSet: dataSet)
        XCTAssertTrue(image.element(withName: "DirectoryRecordType")?.setValue("PRIVATE") == true)
        messages = directory.validateDirectoryRecordKeys().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("requires Type 1C key PrivateRecordUID") })
        append(value: "1.2.826.0.1.3680043.10.999", name: "PrivateRecordUID", to: image, dataSet: dataSet)

        let patient = try XCTUnwrap(sequence.items.first {
            ($0.element(withName: "DirectoryRecordType")?.value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) == "PATIENT"
        })
        let patientName = try XCTUnwrap(patient.element(withName: "PatientName"))
        patientName.characterSet = .latin1
        XCTAssertTrue(patientName.setValue("DUPONT^ÉLODIE"))
        messages = directory.validateDirectoryRecordKeys().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("requires Type 1C key SpecificCharacterSet") })

        append(value: "ISO_IR 100", name: "SpecificCharacterSet", to: patient, dataSet: dataSet)
        XCTAssertTrue(directory.validateDirectoryRecordKeys().isEmpty)
    }

    func testDirectoryRecordSelfContainedConditionalRules() throws {
        let directory = makeDirectory()
        let dataSet = DataSet()
        let sequence = try XCTUnwrap(directory.createDirectoryRecordSequence())
        dataSet.add(element: sequence)
        directory.dataset = dataSet
        let record = try XCTUnwrap(sequence.items.first {
            ($0.element(withName: "DirectoryRecordType")?.value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) == "IMAGE"
        })

        XCTAssertTrue(record.element(withName: "DirectoryRecordType")?.setValue("SR DOCUMENT") == true)
        append(value: "VERIFIED", name: "VerificationFlag", to: record, dataSet: dataSet)
        let emptyContent = appendSequence(named: "ContentSequence", to: record, dataSet: dataSet)
        var messages = directory.validateDirectoryRecordKeys().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("requires Type 1C key VerificationDateTime") })
        XCTAssertTrue(messages.contains { $0.contains("empty Type 1C key ContentSequence") })

        append(value: "20261006120000", name: "VerificationDateTime", to: record, dataSet: dataSet)
        emptyContent.items.append(DataItem(
            withTag: DataTag(withGroup: "fffe", element: "e000"),
            parent: emptyContent
        ))
        messages = directory.validateDirectoryRecordKeys().map(\.message)
        XCTAssertFalse(messages.contains { $0.contains("VerificationDateTime") })
        XCTAssertFalse(messages.contains { $0.contains("empty Type 1C key ContentSequence") })

        XCTAssertTrue(record.element(withName: "DirectoryRecordType")?.setValue("HANGING PROTOCOL") == true)
        record.elements.removeAll { ["VerificationFlag", "VerificationDateTime", "ContentSequence"].contains($0.name) }
        let definitions = appendSequence(
            named: "HangingProtocolDefinitionSequence",
            to: record,
            dataSet: dataSet
        )
        let definition = DataItem(
            withTag: DataTag(withGroup: "fffe", element: "e000"),
            parent: definitions
        )
        definitions.items.append(definition)
        messages = directory.validateDirectoryRecordKeys().map(\.message)
        XCTAssertTrue(messages.contains {
            $0.contains("requires Modality or AnatomicRegionSequence")
        })

        let anatomicRegions = appendSequence(
            named: "AnatomicRegionSequence",
            to: definition,
            dataSet: dataSet
        )
        anatomicRegions.items.append(DataItem(
            withTag: DataTag(withGroup: "fffe", element: "e000"),
            parent: anatomicRegions
        ))
        messages = directory.validateDirectoryRecordKeys().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("requires Type 2C key Laterality") })
        append(value: "", name: "Laterality", to: definition, dataSet: dataSet)
        messages = directory.validateDirectoryRecordKeys().map(\.message)
        XCTAssertFalse(messages.contains { $0.contains("requires Type 2C key Laterality") })
    }

    func testReferencedInstanceConditionalDirectoryKeys() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let referencedURL = temporaryDirectory
            .appendingPathComponent("PAT00001", isDirectory: true)
            .appendingPathComponent("IMG00001")
        try writeReferencedFile(
            to: referencedURL,
            sopInstanceUID: "1.2.3.4",
            additionalValues: [
                "RelatedGeneralSOPClassUID": "1.2.840.10008.5.1.4.1.1.481.23",
                "UserContentLabel": "ADAPTIVE PLAN"
            ]
        )
        let source = makeDirectory()
        XCTAssertTrue(source.writeDicomDir(atPath: temporaryDirectory.path))
        let directory = try XCTUnwrap(DicomDir(
            forPath: temporaryDirectory.appendingPathComponent("DICOMDIR").path
        ))
        let dataSet = try XCTUnwrap(directory.dataset)
        let record = try XCTUnwrap(directory.directoryRecords.first { $0.type == .image })
        XCTAssertTrue(record.item.element(withName: "DirectoryRecordType")?.setValue("RADIOTHERAPY") == true)

        var messages = directory.validateReferencedFiles().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("requires ReferencedRelatedGeneralSOPClassUIDInFile") })
        XCTAssertTrue(messages.contains { $0.contains("contains UserContentLabel") })

        append(
            value: "1.2.840.10008.5.1.4.1.1.481.23",
            name: "ReferencedRelatedGeneralSOPClassUIDInFile",
            to: record.item,
            dataSet: dataSet
        )
        append(value: "ADAPTIVE PLAN", name: "UserContentLabel", to: record.item, dataSet: dataSet)
        messages = directory.validateReferencedFiles().map(\.message)
        XCTAssertFalse(messages.contains { $0.contains("ReferencedRelatedGeneralSOPClassUIDInFile") })
        XCTAssertFalse(messages.contains { $0.contains("UserContentLabel") })

        XCTAssertTrue(record.item.element(withName: "UserContentLabel")?.setValue("WRONG") == true)
        messages = directory.validateReferencedFiles().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("UserContentLabel does not match") })
    }

    func testReferencedSRConceptModifierRequiresDirectoryContentSequence() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let referencedURL = temporaryDirectory
            .appendingPathComponent("PAT00001", isDirectory: true)
            .appendingPathComponent("IMG00001")
        try writeReferencedFile(
            to: referencedURL,
            sopInstanceUID: "1.2.3.4",
            hasRootConceptModifier: true
        )
        let source = makeDirectory()
        XCTAssertTrue(source.writeDicomDir(atPath: temporaryDirectory.path))
        let directory = try XCTUnwrap(DicomDir(
            forPath: temporaryDirectory.appendingPathComponent("DICOMDIR").path
        ))
        let dataSet = try XCTUnwrap(directory.dataset)
        let record = try XCTUnwrap(directory.directoryRecords.first { $0.type == .image })
        XCTAssertTrue(record.item.element(withName: "DirectoryRecordType")?.setValue("SR DOCUMENT") == true)

        var messages = directory.validateReferencedFiles().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("HAS CONCEPT MOD") })
        let content = appendSequence(named: "ContentSequence", to: record.item, dataSet: dataSet)
        content.items.append(DataItem(
            withTag: DataTag(withGroup: "fffe", element: "e000"),
            parent: content
        ))
        messages = directory.validateReferencedFiles().map(\.message)
        XCTAssertFalse(messages.contains { $0.contains("HAS CONCEPT MOD") })
    }

    func testGenericDirectoryRecordTreeWritesAdditionalRecordTypes() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let conceptName:DICOMDirectoryValue = .sequence([[
            "CodeValue": .string("113012"),
            "CodingSchemeDesignator": .string("DCM"),
            "CodeMeaning": .string("Key Object Description")
        ]])
        let rtDose = DICOMDirectoryRecordDefinition(
            type: .rtDose,
            elements: [
                "InstanceNumber": .string("1"),
                "DoseSummationType": .string("PLAN")
            ]
        )
        let structuredReport = DICOMDirectoryRecordDefinition(
            type: .structuredReport,
            elements: [
                "InstanceNumber": .string("2"),
                "CompletionFlag": .string("COMPLETE"),
                "VerificationFlag": .string("UNVERIFIED"),
                "ContentDate": .string("20261006"),
                "ContentTime": .string("120000"),
                "ConceptNameCodeSequence": conceptName
            ]
        )
        let series = DICOMDirectoryRecordDefinition(
            type: .series,
            elements: [
                "Modality": .string("RTDOSE"),
                "SeriesInstanceUID": .string("1.2.3.1"),
                "SeriesNumber": .string("1")
            ],
            children: [rtDose, structuredReport]
        )
        let study = DICOMDirectoryRecordDefinition(
            type: .study,
            elements: [
                "StudyDate": .string("20261006"),
                "StudyTime": .string("120000"),
                "StudyDescription": .string("Generic tree"),
                "StudyInstanceUID": .string("1.2.3"),
                "StudyID": .string("STUDY1"),
                "AccessionNumber": .string("")
            ],
            children: [series]
        )
        let patient = DICOMDirectoryRecordDefinition(
            type: .patient,
            elements: [
                "PatientName": .string("DOE^JANE"),
                "PatientID": .string("P1")
            ],
            children: [study]
        )

        let directory = DicomDir()
        directory.fileSetID = "GENERIC"
        directory.directoryRecordRoots = [patient]
        XCTAssertTrue(directory.writeDicomDir(atPath: temporaryDirectory.path))

        let reloaded = try XCTUnwrap(DicomDir(
            forPath: temporaryDirectory.appendingPathComponent("DICOMDIR").path
        ))
        XCTAssertTrue(reloaded.validateDirectoryStructure().isEmpty)
        XCTAssertTrue(reloaded.validateDirectoryRecordKeys().isEmpty)
        XCTAssertEqual(
            reloaded.directoryRecords.compactMap(\.type),
            [.patient, .study, .series, .rtDose, .structuredReport]
        )
        let sr = try XCTUnwrap(reloaded.directoryRecords.first { $0.type == .structuredReport })
        let sequence = try XCTUnwrap(
            sr.item.element(withName: "ConceptNameCodeSequence") as? DataSequence
        )
        XCTAssertEqual(sequence.items.count, 1)
        XCTAssertEqual(
            (sequence.items[0].element(withName: "CodeMeaning")?.value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "Key Object Description"
        )
    }

    func testGenericDirectoryRecordTreeRejectsInvalidDefinitions() {
        let missingPatientID = DicomDir()
        missingPatientID.directoryRecordRoots = [DICOMDirectoryRecordDefinition(
            type: .patient,
            elements: ["PatientName": .string("DOE^JANE")]
        )]
        XCTAssertFalse(missingPatientID.writeDicomDir(
            atPath: FileManager.default.temporaryDirectory.path
        ))

        let invalidRootType = DicomDir()
        invalidRootType.directoryRecordRoots = [DICOMDirectoryRecordDefinition(
            type: .rtDose,
            elements: [
                "InstanceNumber": .string("1"),
                "DoseSummationType": .string("PLAN")
            ]
        )]
        XCTAssertFalse(invalidRootType.writeDicomDir(
            atPath: FileManager.default.temporaryDirectory.path
        ))

        let invalidFileID = DicomDir()
        invalidFileID.directoryRecordRoots = [DICOMDirectoryRecordDefinition(
            type: .private,
            elements: [
                "PrivateRecordUID": .string("1.2.826.0.1.3680043.10.999"),
                "ReferencedFileID": .string("bad-name")
            ]
        )]
        XCTAssertFalse(invalidFileID.writeDicomDir(
            atPath: FileManager.default.temporaryDirectory.path
        ))
    }

    func testGenericWriterRoundTripsEveryCurrentDirectoryRecordType() throws {
        let seriesChildTypes:[DICOMDirectoryRecordType] = [
            .image, .rtDose, .rtStructureSet, .rtPlan, .rtTreatmentRecord,
            .presentation, .waveform, .structuredReport, .keyObjectDocument,
            .spectroscopy, .rawData, .registration, .fiducial,
            .encapsulatedDocument, .valueMap, .stereometric, .plan,
            .measurement, .surface, .surfaceScan, .tract, .assessment,
            .radiotherapy, .annotation, .waveformPresentation
        ]
        let series = makeMinimalRecordDefinition(
            type: .series,
            children: seriesChildTypes.map { makeMinimalRecordDefinition(type: $0) }
        )
        let study = makeMinimalRecordDefinition(type: .study, children: [series])
        let patient = makeMinimalRecordDefinition(type: .patient, children: [study])
        let otherRoots:[DICOMDirectoryRecordType] = [
            .hangingProtocol, .palette, .implant, .implantAssembly,
            .implantGroup, .inventory, .private
        ]

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let directory = DicomDir()
        directory.fileSetID = "ALL_TYPES"
        directory.directoryRecordRoots = [patient] + otherRoots.map {
            makeMinimalRecordDefinition(type: $0)
        }
        XCTAssertTrue(directory.writeDicomDir(atPath: temporaryDirectory.path))

        let reloaded = try XCTUnwrap(DicomDir(
            forPath: temporaryDirectory.appendingPathComponent("DICOMDIR").path
        ))
        XCTAssertTrue(reloaded.validateDirectoryStructure().isEmpty)
        XCTAssertTrue(reloaded.validateDirectoryRecordKeys().isEmpty)
        XCTAssertEqual(
            Set(reloaded.directoryRecords.compactMap(\.type)),
            DICOMDirectoryRecordType.standard2026d
        )
    }

    func testDirectoryRecordCodeSequenceMacroValidation() throws {
        let directory = makeDirectory()
        let dataSet = DataSet()
        let sequence = try XCTUnwrap(directory.createDirectoryRecordSequence())
        dataSet.add(element: sequence)
        directory.dataset = dataSet
        let image = try XCTUnwrap(sequence.items.first {
            ($0.element(withName: "DirectoryRecordType")?.value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) == "IMAGE"
        })
        XCTAssertTrue(image.element(withName: "DirectoryRecordType")?.setValue("SR DOCUMENT") == true)
        append(value: "COMPLETE", name: "CompletionFlag", to: image, dataSet: dataSet)
        append(value: "UNVERIFIED", name: "VerificationFlag", to: image, dataSet: dataSet)
        append(value: "20261006", name: "ContentDate", to: image, dataSet: dataSet)
        append(value: "120000", name: "ContentTime", to: image, dataSet: dataSet)
        let concept = appendSequence(named: "ConceptNameCodeSequence", to: image, dataSet: dataSet)
        let codedEntry = DataItem(
            withTag: DataTag(withGroup: "fffe", element: "e000"),
            parent: concept
        )
        concept.items.append(codedEntry)
        append(value: "113012", name: "CodeValue", to: codedEntry, dataSet: dataSet)
        append(value: "urn:oid:1.2.3", name: "URNCodeValue", to: codedEntry, dataSet: dataSet)

        var messages = directory.validateDirectoryRecordKeys().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("requires exactly one") })
        XCTAssertTrue(messages.contains { $0.contains("requires CodeMeaning") })
        XCTAssertTrue(messages.contains { $0.contains("requires CodingSchemeDesignator") })

        codedEntry.elements.removeAll { $0.name == "URNCodeValue" }
        append(value: "DCM", name: "CodingSchemeDesignator", to: codedEntry, dataSet: dataSet)
        append(value: "Key Object Description", name: "CodeMeaning", to: codedEntry, dataSet: dataSet)
        messages = directory.validateDirectoryRecordKeys().map(\.message)
        XCTAssertFalse(messages.contains { $0.contains("coded entry") })

        append(value: "DCMR", name: "ContextIdentifier", to: codedEntry, dataSet: dataSet)
        messages = directory.validateDirectoryRecordKeys().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("requires MappingResource") })
        XCTAssertTrue(messages.contains { $0.contains("requires ContextGroupVersion") })
    }
    
    func testWriteDicomDir() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let directory = makeDirectory()
        directory.fileSetID = "MEDIA_01"
        directory.fileSetDescriptorFileID = "README"
        directory.fileSetDescriptorCharacterSet = "ISO_IR 192"
        try Data("DICOM file-set description".utf8).write(
            to: temporaryDirectory.appendingPathComponent("README")
        )
        let referencedURL = temporaryDirectory
            .appendingPathComponent("PAT00001", isDirectory: true)
            .appendingPathComponent("IMG00001")
        try writeReferencedFile(to: referencedURL, sopInstanceUID: "1.2.3.4")
        XCTAssertTrue(directory.writeDicomDir(atPath: temporaryDirectory.path))

        let outputURL = temporaryDirectory.appendingPathComponent("DICOMDIR")
        let input = DicomInputStream(filePath: outputURL.path)
        let decoded = try XCTUnwrap(try input.readDataset())
        let sequence = decoded.element(forTagName: "DirectoryRecordSequence") as? DataSequence
        let items = try XCTUnwrap(sequence?.items)
        XCTAssertEqual(items.count, 5)
        guard items.count == 5 else { return }

        XCTAssertEqual(
            decoded.unsignedInteger32(forTag: "OffsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity"),
            UInt32(items[0].startOffset)
        )
        XCTAssertEqual(
            decoded.unsignedInteger32(forTag: "OffsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity"),
            UInt32(items[4].startOffset)
        )
        XCTAssertEqual(offset(named: "OffsetOfTheNextDirectoryRecord", in: items[0]), UInt32(items[4].startOffset))
        XCTAssertEqual(offset(named: "OffsetOfReferencedLowerLevelDirectoryEntity", in: items[0]), UInt32(items[1].startOffset))
        XCTAssertEqual(offset(named: "OffsetOfReferencedLowerLevelDirectoryEntity", in: items[1]), UInt32(items[2].startOffset))
        XCTAssertEqual(offset(named: "OffsetOfReferencedLowerLevelDirectoryEntity", in: items[2]), UInt32(items[3].startOffset))
        XCTAssertEqual(offset(named: "OffsetOfTheNextDirectoryRecord", in: items[4]), 0)
        XCTAssertEqual(offset(named: "OffsetOfReferencedLowerLevelDirectoryEntity", in: items[4]), 0)
        XCTAssertEqual(
            (items[3].element(withName: "ReferencedFileID")?.value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "PAT00001\\IMG00001"
        )
        XCTAssertTrue(items.allSatisfy { $0.length >= 0 })
        XCTAssertNotEqual(sequence?.length, -1)

        let bytes = try Data(contentsOf: outputURL)
        for item in items {
            XCTAssertEqual(bytes.subdata(in: item.startOffset..<(item.startOffset + 4)), Data([0xfe, 0xff, 0x00, 0xe0]))
            XCTAssertEqual(item.element(withName: "RecordInUseFlag")?.value as? UInt16, UInt16.max)
        }

        let reloaded = try XCTUnwrap(DicomDir(forPath: outputURL.path))
        XCTAssertEqual(reloaded.fileSetID, "MEDIA_01")
        XCTAssertEqual(reloaded.fileSetDescriptorFileID, "README")
        XCTAssertEqual(reloaded.fileSetDescriptorCharacterSet, "ISO_IR 192")
        XCTAssertTrue(reloaded.validateDirectoryStructure().isEmpty)
        XCTAssertTrue(reloaded.validateReferencedFiles().isEmpty)
        XCTAssertEqual(reloaded.patientsKeys, ["P1", "P2"])
        XCTAssertEqual(reloaded.studies["1.2.3"]?["PatientID"] as? String, "P1")
        XCTAssertEqual(reloaded.series["1.2.3.1"]?["StudyInstanceUID"], "1.2.3")
        XCTAssertEqual(reloaded.images["1.2.3.4"]?["SeriesInstanceUID"] as? String, "1.2.3.1")
        XCTAssertEqual(reloaded.index, [temporaryDirectory
            .appendingPathComponent("PAT00001")
            .appendingPathComponent("IMG00001").path])

        let nextOffsetElement = try XCTUnwrap(items[0].element(withName: "OffsetOfTheNextDirectoryRecord"))
        var malformedBytes = bytes
        malformedBytes.replaceSubrange(
            nextOffsetElement.dataOffset..<(nextOffsetElement.dataOffset + 4),
            with: Data([0x01, 0x00, 0x00, 0x00])
        )
        let malformedURL = temporaryDirectory.appendingPathComponent("BROKEN")
        try malformedBytes.write(to: malformedURL)
        XCTAssertNil(DicomDir(forPath: malformedURL.path))

        try writeReferencedFile(to: referencedURL, sopInstanceUID: "1.2.3.999")
        XCTAssertTrue(reloaded.validateReferencedFiles().contains {
            $0.message.contains("ReferencedSOPInstanceUIDInFile does not match")
        })
    }

    func testWriteDicomDirRejectsInvalidFileIDs() {
        let invalid = [
            "lowercase",
            "TOO_LONG_9",
            "BAD.NAME",
            "A\\B\\C\\D\\E\\F\\G\\H\\I",
            "A\\\\B"
        ]
        for value in invalid {
            XCTAssertFalse(DicomDir.isValidFileID(value), value)
        }
        XCTAssertTrue(DicomDir.isValidFileID("PAT00001/IMG00001"))
        XCTAssertTrue(DicomDir.isValidFileSetID("MEDIA_01"))
        XCTAssertTrue(DicomDir.isValidFileSetID(""))
        XCTAssertFalse(DicomDir.isValidFileSetID("lowercase"))
        XCTAssertFalse(DicomDir.isValidFileSetID("12345678901234567"))

        let directory = makeDirectory()
        directory.images["1.2.3.4"]?["ReferencedFileID"] = "bad-name"
        XCTAssertFalse(directory.writeDicomDir(atPath: FileManager.default.temporaryDirectory.path))
        directory.images["1.2.3.4"]?["ReferencedFileID"] = "PAT00001\\IMG00001"
        directory.fileSetID = "INVALID-LABEL"
        XCTAssertFalse(directory.writeDicomDir(atPath: FileManager.default.temporaryDirectory.path))
        directory.fileSetID = ""
        directory.fileSetDescriptorCharacterSet = "ISO_IR 192"
        XCTAssertFalse(directory.writeDicomDir(atPath: FileManager.default.temporaryDirectory.path))
    }

    func testDirectoryStructureValidationRejectsSemanticGraphErrors() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let directory = makeDirectory()
        XCTAssertTrue(directory.writeDicomDir(atPath: temporaryDirectory.path))
        let outputURL = temporaryDirectory.appendingPathComponent("DICOMDIR")
        let decoded = try XCTUnwrap(try DicomInputStream(filePath: outputURL.path).readDataset())
        let sequence = try XCTUnwrap(decoded.element(forTagName: "DirectoryRecordSequence") as? DataSequence)
        XCTAssertGreaterThan(sequence.items.count, 1)

        XCTAssertTrue(decoded.element(forTagName: "OffsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity")?
            .setValue(UInt32(sequence.items[1].startOffset)) == true)
        XCTAssertTrue(decoded.element(forTagName: "FileSetConsistencyFlag")?.setValue(UInt16.max) == true)
        XCTAssertTrue(sequence.items[3].element(withName: "OffsetOfTheNextDirectoryRecord")?
            .setValue(UInt32(sequence.items[3].startOffset)) == true)
        XCTAssertTrue(sequence.items[1].element(withName: "DirectoryRecordType")?.setValue("IMAGE") == true)
        XCTAssertTrue(sequence.items[4].element(withName: "DirectoryRecordType")?.setValue("PRIVATE") == true)
        let invalid = DicomDir()
        invalid.dataset = decoded
        invalid.filepath = outputURL.path
        let messages = invalid.validateDirectoryStructure().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("Last root Directory Record offset") })
        XCTAssertTrue(messages.contains { $0.contains("FileSetConsistencyFlag must be 0000H") })
        XCTAssertTrue(messages.contains { $0.contains("cycle or duplicate reference") })
        XCTAssertTrue(messages.contains { $0.contains("IMAGE is not permitted below PATIENT") })
        XCTAssertTrue(messages.contains { $0.contains("PRIVATE Directory Record requires PrivateRecordUID") })
    }

    func testPrimitiveDICOMDIRWithoutDirectoryInformationIsAccepted() throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let dataSet = DataSet()
        dataSet.hasPreamble = true
        dataSet.transferSyntax = TransferSyntax(TransferSyntax.explicitVRLittleEndian)
        _ = dataSet.set(value: Data([0x00, 0x01]), forTagName: "FileMetaInformationVersion")
        _ = dataSet.set(value: "1.2.840.10008.1.3.10", forTagName: "MediaStorageSOPClassUID")
        _ = dataSet.set(value: "2.25.123", forTagName: "MediaStorageSOPInstanceUID")
        _ = dataSet.set(value: TransferSyntax.explicitVRLittleEndian, forTagName: "TransferSyntaxUID")
        _ = dataSet.set(value: "2.25.22010055", forTagName: "ImplementationClassUID")
        _ = dataSet.set(value: "PRIMITIVE", forTagName: "FileSetID")
        let file = try XCTUnwrap(DicomFile(withDataset: dataSet, hasPreamble: true))
        XCTAssertTrue(file.write(atPath: temporaryURL.path))
        XCTAssertTrue(DicomDir.isDicomDir(forPath: temporaryURL.path))
        let directory = try XCTUnwrap(DicomDir(forPath: temporaryURL.path))
        XCTAssertEqual(directory.fileSetID, "PRIMITIVE")
        XCTAssertTrue(directory.validateDirectoryStructure().isEmpty)
    }

    private func makeDirectory() -> DicomDir {
        let directory = DicomDir()
        directory.patientsKeys = ["P1", "P2"]
        directory.patients = ["P1": "DOE^JANE", "P2": "DOE^JOHN"]
        directory.studiesKeys = ["1.2.3"]
        directory.studies = [
            "1.2.3": [
                "PatientID": "P1",
                "StudyDate": "20261006",
                "StudyTime": "120000",
                "StudyDescription": "Synthetic study",
                "StudyID": "STUDY1",
                "AccessionNumber": ""
            ]
        ]
        directory.seriesKeys = ["1.2.3.1"]
        directory.series = [
            "1.2.3.1": [
                "StudyInstanceUID": "1.2.3",
                "Modality": "CT",
                "SeriesNumber": "1"
            ]
        ]
        directory.imagesKeys = ["1.2.3.4"]
        directory.images = [
            "1.2.3.4": [
                "SeriesInstanceUID": "1.2.3.1",
                "ReferencedFileID": "PAT00001/IMG00001",
                "ReferencedSOPClassUIDInFile": "1.2.840.10008.5.1.4.1.1.2",
                "ReferencedTransferSyntaxUIDInFile": TransferSyntax.explicitVRLittleEndian,
                "InstanceNumber": "1"
            ]
        ]
        return directory
    }

    private func offset(named name:String, in item:DataItem) -> UInt32? {
        return item.element(withName: name)?.value as? UInt32
    }

    private func append(value:Any, name:String, to item:DataItem, dataSet:DataSet) {
        guard let element = DataElement(withTagName: name, dataset: dataSet, parent: item) else {
            return XCTFail("Missing dictionary tag \(name)")
        }
        XCTAssertTrue(element.setValue(value))
        item.elements.append(element)
    }

    private func makeMinimalRecordDefinition(
        type:DICOMDirectoryRecordType,
        children:[DICOMDirectoryRecordDefinition] = []
    ) -> DICOMDirectoryRecordDefinition {
        var elements:[String:DICOMDirectoryValue] = [:]
        for (name, requirement) in DICOMDirectoryRecordSchemas.requirements[type] ?? [:] {
            guard let tag = DicomSpec.shared.dataTag(forName: name),
                  let vr = DicomSpec.shared.vrForTag(withCode: tag.code) else {
                XCTFail("Missing dictionary metadata for \(name)")
                continue
            }
            if vr == .SQ, requirement == .type1,
               name.hasSuffix("CodeSequence") || name == "AnatomicRegionSequence" {
                elements[name] = minimalCodedEntrySequence()
            } else {
                elements[name] = minimalDirectoryValue(vr: vr, mayBeEmpty: requirement == .type2)
            }
        }
        if type == .private {
            elements["PrivateRecordUID"] = .string("1.2.826.0.1.3680043.10.999")
        }
        if type == .hangingProtocol {
            elements["HangingProtocolDefinitionSequence"] = .sequence([[
                "Modality": .string("CT")
            ]])
        }
        return DICOMDirectoryRecordDefinition(
            type: type,
            elements: elements,
            children: children
        )
    }

    private func minimalDirectoryValue(vr:VR.VR, mayBeEmpty:Bool) -> DICOMDirectoryValue {
        if mayBeEmpty {
            return vr == .SQ ? .sequence([]) : .string("")
        }
        switch vr {
        case .SQ: return .sequence([[:]])
        case .SS: return .int16(1)
        case .SL: return .int32(1)
        case .SV: return .int64(1)
        case .US: return .uint16(1)
        case .UL: return .uint32(1)
        case .UV: return .uint64(1)
        case .FL: return .float32(1)
        case .FD: return .float64(1)
        case .DA: return .string("20261006")
        case .TM: return .string("120000")
        case .DT: return .string("20261006120000")
        case .UI: return .string("1.2.826.0.1.3680043.10.999.1")
        case .IS, .DS: return .string("1")
        default: return .string("VALUE")
        }
    }

    private func minimalCodedEntrySequence() -> DICOMDirectoryValue {
        return .sequence([[
            "CodeValue": .string("113012"),
            "CodingSchemeDesignator": .string("DCM"),
            "CodeMeaning": .string("Synthetic coded entry")
        ]])
    }

    @discardableResult
    private func appendSequence(
        named name:String,
        to item:DataItem,
        dataSet:DataSet
    ) -> DataSequence {
        guard let tag = DicomSpec.shared.dataTag(forName: name) else {
            XCTFail("Missing dictionary tag \(name)")
            return DataSequence(withTag: DataTag(withGroup: "ffff", element: "ffff"), parent: item)
        }
        let sequence = DataSequence(withTag: tag, parent: item)
        sequence.dataset = dataSet
        sequence.vr = .SQ
        sequence.length = -1
        item.elements.append(sequence)
        return sequence
    }

    private func writeReferencedFile(
        to url:URL,
        sopInstanceUID:String,
        additionalValues:[String:Any] = [:],
        hasRootConceptModifier:Bool = false
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let dataSet = DataSet()
        dataSet.hasPreamble = true
        dataSet.transferSyntax = TransferSyntax(TransferSyntax.explicitVRLittleEndian)
        let sopClassUID = "1.2.840.10008.5.1.4.1.1.2"
        _ = dataSet.set(value: Data([0x00, 0x01]), forTagName: "FileMetaInformationVersion")
        _ = dataSet.set(value: sopClassUID, forTagName: "MediaStorageSOPClassUID")
        _ = dataSet.set(value: sopInstanceUID, forTagName: "MediaStorageSOPInstanceUID")
        _ = dataSet.set(value: TransferSyntax.explicitVRLittleEndian, forTagName: "TransferSyntaxUID")
        _ = dataSet.set(value: "2.25.22010055", forTagName: "ImplementationClassUID")
        _ = dataSet.set(value: sopClassUID, forTagName: "SOPClassUID")
        _ = dataSet.set(value: sopInstanceUID, forTagName: "SOPInstanceUID")
        for (name, value) in additionalValues {
            XCTAssertNotNil(dataSet.set(value: value, forTagName: name), name)
        }
        if hasRootConceptModifier {
            guard let contentTag = DicomSpec.shared.dataTag(forName: "ContentSequence") else {
                return XCTFail("Missing ContentSequence dictionary tag")
            }
            let content = DataSequence(withTag: contentTag)
            content.dataset = dataSet
            content.vr = .SQ
            content.length = -1
            let item = DataItem(
                withTag: DataTag(withGroup: "fffe", element: "e000"),
                parent: content
            )
            item.length = -1
            append(value: "HAS CONCEPT MOD", name: "RelationshipType", to: item, dataSet: dataSet)
            item.length = -1
            content.items.append(item)
            content.length = -1
            dataSet.add(element: content)
        }
        let file = try XCTUnwrap(DicomFile(withDataset: dataSet, hasPreamble: true))
        XCTAssertTrue(file.write(atPath: url.path))
    }

}
