# DcmPrint

Inspect a DICOM file as readable text, Native DICOM Model XML, or DICOM JSON.

```sh
DcmPrint image.dcm
DcmPrint --format XML --pretty image.dcm
DcmPrint --format JSON --pretty image.dcm
```

A malformed or truncated file is rejected, unless `--tolerant` is given: the
elements read before the failure are printed, the failure goes to standard
error, and the exit status is 2.

```sh
DcmPrint --tolerant truncated.dcm
```

Use `DcmPrint --help` for the exact options supported by the checked-out
revision. XML and JSON output follow the corresponding DICOM models; pretty
printing changes presentation only.
