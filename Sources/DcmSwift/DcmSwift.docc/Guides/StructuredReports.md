# Structured Reports

Print a DICOM Structured Report tree or render it as HTML.

```swift
if let file = DicomFile(forPath: srPath),
   let document = file.structuredReportDocument {
    print(document)        // content tree
    print(document.html)   // HTML page
}
```

``SRDocument`` is built from the data set of an SR instance. <doc:DcmSR> offers
the same output from the command line.
