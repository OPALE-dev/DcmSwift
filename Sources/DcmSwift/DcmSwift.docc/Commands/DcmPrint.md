# DcmPrint

Inspect a DICOM file as readable text, Native DICOM Model XML, or DICOM JSON.

```sh
DcmPrint image.dcm
DcmPrint --format XML --pretty image.dcm
DcmPrint --format JSON --pretty image.dcm
```

Use `DcmPrint --help` for the exact options supported by the checked-out
revision. XML and JSON output follow the corresponding DICOM models; pretty
printing changes presentation only.
