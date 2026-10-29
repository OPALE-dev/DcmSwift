# Structured Reports

Read the content tree of a Structured Report, write one, or work with the
PS3.16 templates: measurement reports (TID 1500), diagnostic imaging reports
(TID 2000), key object selections (TID 2010), radiation dose reports, CAD and
ultrasound reports; validate a document against its template; convert a
diagnostic imaging report to HL7 CDA.

## Reading

``DICOMStructuredReport`` reads the document and its content tree of
``DICOMSRContentItem`` values, one case per Value Type:

```swift
if let report = DICOMStructuredReport(dataSet: dataSet) {
    for (identifier, item) in report.root.flattened() {
        if case .number(let value?, let units?, _) = item.value {
            print(identifier, item.conceptName?.meaning ?? "", value, units.value)
        }
    }
}
```

## Measurement Reports

``DICOMMeasurementReport`` makes and reads TID 1500 reports with TID 1501
Measurement Groups:

```swift
let report = DICOMMeasurementReport(
    procedure: DICOMCode("77477000", scheme: "SCT", meaning: "CT"), observerName: "Doe^Jane",
    images: [DICOMSRReference(sopClassUID: ctClass, sopInstanceUID: ctInstance)],
    groups: [.init(trackingIdentifier: "lesion 1", measurements: [
        .init(concept: DICOMCode("118565006", scheme: "SCT", meaning: "Volume"), value: 12.5,
              units: DICOMCode("cm3", scheme: "UCUM", meaning: "cm3")),
    ])])
try report.document().dataSet(context: ctImage).writePart10(to: url)
```

## Diagnostic imaging reports

``DICOMDiagnosticImagingReport`` makes and reads TID 2000 reports. Sections
take a heading of CID 7001; ``DICOMDiagnosticImagingReport/element(for:)``
gives the usual CID 7002 element of a heading:

```swift
typealias H = DICOMDiagnosticImagingReport.Headings
let report = DICOMDiagnosticImagingReport(
    language: DICOMCode("fr-FR", scheme: "RFC5646", meaning: "French (France)"),
    observers: [.person(name: "Martin^Claire", organization: "Radiologie")],
    sections: [
        .init(heading: H.findings, observations: [.text("Nodule de 8 mm", concept: H.finding)]),
        .init(heading: H.conclusions, observations: [.text("Contrôle à 3 mois", concept: H.conclusion)]),
    ])
var document = report.document(verificationFlag: "VERIFIED")    // Basic Text SR, DCMR 2000
document.preliminaryFlag = "FINAL"
document.verifyingObservers = [.init(name: "Martin^Claire", dateTime: "20261028120000")]
document.predecessorDocuments = [previousVersion]                // the report this one corrects
let dataSet = document.dataSet(context: ctImage)
```

## Key objects

``DICOMKeyObjectSelection`` makes and reads TID 2010 documents; the evidence
groups the references by their study and series:

```swift
let selection = DICOMKeyObjectSelection(title: DICOMKeyObjectSelection.Titles.rejectedForQualityReasons,
                                        description: "Motion blur", references: references)
let dataSet = selection.document().dataSet(context: anyInstance)
```

## Radiation dose, CAD and ultrasound

``DICOMRadiationDoseReport`` reads CT, projection X-ray, radiopharmaceutical
and patient dose reports and makes CT ones. ``DICOMCADReport`` reads
Mammography and Chest CAD findings; ``DICOMUltrasoundReport`` reads the
measurements of OB-GYN, vascular and echocardiography reports with their
finding site, laterality and other modifiers:

```swift
if let dose = DICOMRadiationDoseReport(document: document) {
    print(dose.kind, dose.ctDoseLengthProductTotal ?? 0)
    for event in dose.events {
        print(event.protocolName ?? "", event.value(DICOMRadiationDoseReport.Codes.meanCTDIvol)?.value ?? 0)
    }
}
```

## Template validation

``DICOMSRTemplateValidator`` checks a document against the template it
declares, the Context Groups of its codes, and the constraints of its SOP
Class. Every template of PS3.16 Annex A is known: ``DICOMSRTemplateLibrary``
holds them, generated from the Standard by
`Scripts/generate-dicom-sr-templates.py`, and expands included templates
with their parameters:

```swift
for issue in DICOMSRTemplateValidator.validate(document) {
    print(issue)    // "error 1.4: missing CONTAINS NUM (113813, DCM, "CT Dose Length Product Total")"
}
DICOMSRTemplateLibrary.shared.name(of: "2006")   // "Imaging Report With Conditional Radiation Exposure…"
```

To regenerate the resource for a new edition of the Standard:

```sh
python3 Scripts/generate-dicom-sr-templates.py part16.xml \
    Sources/DcmSwift/Resources/dicom-sr-templates-2026d.json
```

## HL7 CDA

``DICOMReportCDA`` writes a TID 2000 report as a CDA R2 document with its
DICOM Object Catalog, and reads the sections of a CDA imaging report back:

```swift
let xml = DICOMReportCDA.document(report, header: .init(documentID: uid, effectiveTime: "20261028120000",
    patient: .init(id: "PAT-1", name: "DOE^Jane"), custodian: "Radiology"), references: images)
let read = DICOMReportCDA.report(cda: Data(xml.utf8))
```

## HTML

The older ``SRDocument`` prints a report or renders it as HTML:

```swift
if let file = DicomFile(forPath: srPath),
   let document = file.structuredReportDocument {
    print(document.html)
}
```

<doc:DcmSR> offers the same from the command line.
