# Structured Reports

Read the content tree of a Structured Report, write one, or make a TID 1500
Measurement Report.

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

## HTML

The older ``SRDocument`` prints a report or renders it as HTML:

```swift
if let file = DicomFile(forPath: srPath),
   let document = file.structuredReportDocument {
    print(document.html)
}
```

<doc:DcmSR> offers the same from the command line.
