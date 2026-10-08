# Files and Data Sets

Read, inspect, modify, and write DICOM Part 10 files and their data sets.

## Read and write a file

`DicomFile` reads a Part 10 file into a `DataSet`:

```swift
import DcmSwift

guard let file = DicomFile(forPath: "/path/to/image.dcm") else { return }

let patientName = file.dataset.string(forTag: "PatientName")
_ = file.dataset.set(value: "John^Doe", forTagName: "PatientName")

_ = file.write(atPath: "/path/to/copy.dcm")
```

`write(atPath:vrMethod:byteOrder:)` keeps the data set encoding unless a VR
method or byte order is given; `write(atPath:transferSyntax:)` writes another
Transfer Syntax. File Meta Information is always written as Explicit VR Little
Endian, and its group length is recalculated during serialization.

## Read a data set from a stream

`DicomInputStream` reads a data set from a path, a `URL`, or `Data`:

```swift
let stream = DicomInputStream(filePath: path)

do {
    if let dataset = try stream.readDataset() {
        print(dataset)
    }
} catch {
    print(error)
}
```

`readDataset(headerOnly:withoutPixelData:enforceVR:)` can stop after the File
Meta Information or skip Pixel Data.

## Create a data set

```swift
let dataset = DataSet()

_ = dataset.set(value: "John^Doe", forTagName: "PatientName")
_ = dataset.set(value: "12345678", forTagName: "PatientID")

print(dataset.toData().toHex())
```

## Values

| Value kind | API |
| --- | --- |
| Character strings | `textValues` on the element, `textValues(forTag:)` on the data set |
| Person Names | `personNames` and `personNames(forTag:)`: structured `DICOMPersonName` values with alphabetic, ideographic, and phonetic component groups |
| Fixed-width numbers | Typed multi-valued encoding and decoding of signed and unsigned 16, 32, and 64-bit integers, and 32 and 64-bit floating-point values |
| Historical API | The flat `value` accessor remains available |

Dictionary VM expressions, including bounded ranges and `2-2n` or `3-3n`
multiples, are validated independently from IOD requirements. Validation also
reports odd-length Value Fields.

## Parsing safeguards

| Safeguard | Behavior |
| --- | --- |
| Lengths | Malformed lengths are bounds-checked |
| Limits | `DicomInputStream.limits` bounds value sizes, element counts, sequence depth, sequence items, and encapsulated Pixel Data fragments |
| Sequences | Defined and undefined-length Sequences validate Item tags, exact boundaries, and zero-length Item and Sequence delimiters |
| Explicit VR | Unknown VR codes and non-zero reserved bytes in long-form headers are rejected |
| Private elements | Private Creator elements are read as `LO` in implicit VR data sets; private block reservations are resolved separately in the top-level data set and in every Sequence Item |
| Unknown values | Unknown private values stay byte-preserving `UN` values unless their explicit VR is present on the wire |

## Bulk data

For file-backed input, `DicomInputStream.bulkDataLoadingPolicy` can defer
defined-length `OB`, `OD`, `OF`, `OL`, `OV`, `OW`, and `UN` Value Fields above a
configurable threshold.

- `bulkDataReference` gives the source URL, byte offset, and length of a
  deferred value.
- `loadData()` reports I/O errors; the historical `data` accessor loads the
  value on first use.
- `loadData(range:)` reads a bounded subrange without loading the whole value.

The same policy applies to encapsulated Pixel Data fragments: the Basic Offset
Table and each fragment keep their own file ranges.

## Dictionary

The runtime tag and UID registry is generated reproducibly from PS3.6 2026d. It
contains 5,303 data-element entries and 1,990 UID entries. Command Set fields
are generated from PS3.7 2026d Table E.1-1. A UID in the registry does not mean
that the corresponding feature is implemented; see <doc:Conformance>.

## Coded concepts

``DICOMTerminology`` holds the PS3.16 Coding Schemes, DICOM codes, and
Context Groups:

```swift
let terminology = DICOMTerminology.shared
let regions = terminology.codes(in: 4031)            // Common Anatomic Region, with included groups
if let item = dataSet.sequence(forTagName: "AnatomicRegionSequence")?.items.first,
   let code = DICOMCode(item: item) {
    print(terminology.membership(of: code, in: 4031)) // member, allowedByExtension, ...
}
```

## Encapsulated documents

``DICOMEncapsulatedDocument`` reads and makes instances of the Encapsulated
PDF, CDA, STL, OBJ, and MTL IODs; `writePart10(to:)` writes any data set as a
Part 10 file:

```swift
let report = DICOMEncapsulatedDocument(kind: .pdf, document: pdfData, title: "Discharge letter")
try report.dataSet(context: imageOfTheStudy).writePart10(to: url)
let extracted = DICOMEncapsulatedDocument(dataSet: dataSet)?.document
```

## Waveforms

``DICOMWaveform`` reads the multiplex groups of the Waveform Sequence: channels
with their source, sensitivity, and units, samples, and values in the channel
units:

```swift
for group in try DICOMWaveform.groups(in: dataSet) {
    let leadII = group.values(channel: 1)   // microvolts for an ECG
}
```

## Radiotherapy

``DICOMRTStructureSet``, ``DICOMRTDose``, and ``DICOMRTPlan`` read RT objects:

```swift
let rois = DICOMRTStructureSet(dataSet: dataSet)?.rois          // names, colors, contours
let dose = try DICOMRTDose(dataSet: dataSet)?.dose(frame: 0)     // Gy, row by row
let beams = DICOMRTPlan(dataSet: dataSet)?.beams                // control points, metersets
```

## IOD validation

``DICOMIODValidator`` checks a data set against the IOD of its SOP Class, as
PS3.3 2026d defines it. It is separate from parsing: a file that does not
conform is still read.

```swift
let report = DICOMIODValidator().validate(dataSet)
for finding in report.findings {
    print(finding)  // Patient: (0010,0020) is missing (Type 2) [PS3.3 Table C.7-1]
}
```

Each ``DICOMIODFinding`` gives its kind, the path of tags from the top-level
attribute, the module, and the PS3.3 table. <doc:DcmValidate> does the same
from the command line; ``DICOMIODValidationPolicy`` applies it to received
instances.

## De-identification

``DICOMDeidentifier`` applies the Basic Application Level Confidentiality
Profile of PS3.15 Annex E, and its options, to a data set in place:

```swift
let deidentifier = try DICOMDeidentifier(options: [.retainLongitudinalModifiedDates], key: studyKey)
let report = deidentifier.deidentify(dataSet)
```

Instances de-identified with the same key get the same replacement UIDs and
date shift. With `encryptionRecipients`, the original values are kept
encrypted for them in the Encrypted Attributes Sequence;
``DICOMEncryptedAttributes`` decrypts or restores them. <doc:DcmAnonymize> does the same from the command line.

## Digital Signatures

``DICOMDigitalSigner`` signs a data set, or a Sequence Item, with the Base RSA
Digital Signature Profile of PS3.15; ``DICOMSignatureVerification`` verifies
every signature of a data set:

```swift
let signer = try DICOMDigitalSigner(privateKeyPEM: key, certificatePEM: certificate)
try signer.sign(dataSet)
for result in DICOMSignatureVerification.verify(dataSet) {
    print(result.status, result.signer ?? "")   // valid CN=...
}
```

## Other helpers

The library also provides helpers for DICOM dates, times, UIDs, tags, VRs,
endianness, pixel access, and radiotherapy objects. ``DICOMJSON`` and
``DICOMXML`` encode and decode the DICOM JSON Model (PS3.18 F) and the Native
DICOM Model XML (PS3.19 A.1).

## Logging

The legacy `Logger` writes to standard error by default. It writes to a file
only when asked with `Logger.addDestination(.File)`.
