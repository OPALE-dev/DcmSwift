# Command-Line Tools

DcmSwift ships focused executables for file inspection, transformation,
structured reports, and DIMSE networking.

Build every product in release mode:

```sh
swift build -c release
```

The resulting binaries are under `.build/release`. Every command supports
`--help`; that output is the authoritative option reference for the checked-out
revision.

## Files and images

- <doc:DcmPrint> prints data sets as text, Native DICOM Model XML, or DICOM JSON.
- <doc:DcmConvert> renders DICOM frames as PNG, JPEG, TIFF, PGM, or PPM.
- <doc:DcmAnonymize> writes an anonymized copy of an instance.
- <doc:DcmIzer> demonstrates wrapping an ordinary image in a DICOM file.
- <doc:DcmSR> prints structured-report trees or renders them as HTML.

## Networking

- <doc:DcmEcho> verifies a remote Application Entity.
- <doc:DcmStore> sends instances and can request Storage Commitment.
- <doc:DcmFind> performs Query/Retrieve C-FIND requests.
- <doc:DcmServer> provides verification, storage, query/retrieve, and Storage
  Commitment services over a directory.

The networking programs return a nonzero status when association or DIMSE
operations fail, making them suitable for scripts and demonstrations.
