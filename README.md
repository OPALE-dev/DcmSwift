# DcmSwift

[![CI](https://github.com/OPALE-dev/DcmSwift/actions/workflows/ci.yml/badge.svg)](https://github.com/OPALE-dev/DcmSwift/actions/workflows/ci.yml)
[![Documentation](https://github.com/OPALE-dev/DcmSwift/actions/workflows/documentation.yml/badge.svg)](https://opale-dev.github.io/DcmSwift/documentation/dcmswift/)
[![Swift 6.2+](https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20Linux-lightgrey)](#requirements)
[![DICOM 2026d](https://img.shields.io/badge/DICOM-2026d-blue)](https://www.dicomstandard.org/current)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](#license)

DcmSwift is a DICOM library and a set of command-line tools written in Swift.
It reads, writes, validates, renders, and exchanges DICOM data on macOS, iOS,
and Linux, and relies mainly on Foundation.

The normative baseline is **DICOM 2026d**. DcmSwift 2.0 is a work in progress:
the binary file format, the codecs, the DICOM Upper Layer and DIMSE services
with TLS, and the DICOM JSON and Native DICOM Model XML representations are
implemented with regression tests, fuzzing, and comparisons with independent
toolkits; rendering and presentation come next.

> **Disclaimer.** DcmSwift is not a medical diagnosis library and must not be
> used as one. Parsing a file does not mean that it conforms to its IOD, and a
> UID in the bundled dictionary does not mean that the corresponding feature is
> implemented.

## Documentation

The documentation is a [DocC catalog](Sources/DcmSwift/DcmSwift.docc), built
from the articles below and the `///` comments of the public API.

| Topic | Documents |
| --- | --- |
| Start here | <ul><li>[Getting Started](Sources/DcmSwift/DcmSwift.docc/Guides/GettingStarted.md)</li><li>[Command-Line Tools](Sources/DcmSwift/DcmSwift.docc/Guides/CommandLineTools.md)</li></ul> |
| Guides | <ul><li>[Files and Data Sets](Sources/DcmSwift/DcmSwift.docc/Guides/FilesAndDataSets.md)</li><li>[Rendering Images](Sources/DcmSwift/DcmSwift.docc/Guides/RenderingImages.md)</li><li>[DICOMDIR](Sources/DcmSwift/DcmSwift.docc/Guides/DICOMDIR.md)</li><li>[Structured Reports](Sources/DcmSwift/DcmSwift.docc/Guides/StructuredReports.md)</li><li>[Networking](Sources/DcmSwift/DcmSwift.docc/Guides/Networking.md)</li><li>[DICOMweb](Sources/DcmSwift/DcmSwift.docc/Guides/DICOMweb.md)</li></ul> |
| Qualification | <ul><li>[Conformance Statement](Sources/DcmSwift/DcmSwift.docc/Qualification/Conformance.md) (working draft)</li><li>[Traceability matrix](Sources/DcmSwift/DcmSwift.docc/Qualification/Traceability.md): requirements and their tests</li><li>[Deferred limitations](Sources/DcmSwift/DcmSwift.docc/Qualification/DeferredLimitations.md)</li><li>[Implementation plan](Sources/DcmSwift/DcmSwift.docc/Qualification/ImplementationPlan.md)</li></ul> |
| Contributing | <ul><li>[Testing and Qualification](Sources/DcmSwift/DcmSwift.docc/Guides/TestingAndQualification.md): tests, corpus, CI, interoperability scripts</li><li>[Documentation Workflow](Sources/DcmSwift/DcmSwift.docc/Guides/DocumentationWorkflow.md)</li></ul> |

Preview the documentation, or build the static site:

    Scripts/documentation/preview.sh
    Scripts/documentation/build.sh .build/documentation

## Requirements

| Requirement | Details |
| --- | --- |
| Platforms | <ul><li>macOS 10.15 or later</li><li>iOS 13 or later</li><li>Linux</li></ul> |
| Swift | 6.2 or later (Swift 5 language mode), which the AsyncHTTPClient dependencies require; CI uses Swift 6.2 on Linux and the current Xcode on macOS and iOS |
| System library | `zlib` development files (`zlib1g-dev` on Debian and Ubuntu) |

Linux is a release platform, not a best-effort target: the library, the tools,
and the tests build and run on Linux and Apple platforms, and the library and
its tests also on iOS. Only the `CGImage`, `NSImage`, and `UIImage`
conveniences are Apple-specific.

## Installation

Add DcmSwift to the dependencies of your `Package.swift`, or in Xcode by its
repository address:

```swift
dependencies: [
    .package(url: "https://github.com/OPALE-dev/DcmSwift.git", branch: "master")
],
targets: [
    .target(name: "YourTarget", dependencies: ["DcmSwift"])
]
```

## Quick start

```swift
import DcmSwift

// Read, edit, and write a file
let file = DicomFile(forPath: "/path/to/image.dcm")!
print(file.dataset.string(forTag: "PatientName") ?? "")
_ = file.dataset.set(value: "John^Doe", forTagName: "PatientName")
_ = file.write(atPath: "/path/to/copy.dcm")

// Render the first frame as PNG
let image = try DICOMImageRenderer(dataset: file.dataset).render(frame: 0)
try image.pngData().write(to: URL(fileURLWithPath: "/path/to/image.png"))

// Verify a remote node
let client = try DICOMClient(configuration: DICOMClientConfiguration(aeTitle: "DCMCLIENT"))
let remote = DICOMRemoteNode(aeTitle: "PACS", host: "pacs.example.org", port: 11112)
try await client.withAssociation(
    to: remote, presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.verification])
) { association in
    try await association.echo()
}
```

The guides cover each area in detail.

## DICOM coverage

This is a summary; the [Conformance Statement](Sources/DcmSwift/DcmSwift.docc/Qualification/Conformance.md)
and the [traceability matrix](Sources/DcmSwift/DcmSwift.docc/Qualification/Traceability.md)
give the detailed scope and evidence. The tag and UID registry is generated
from PS3.6 2026d.

### Data Set encodings

| Transfer Syntax | Read | Write | Notes |
| --- | :-: | :-: | --- |
| Implicit VR Little Endian | ✓ | ✓ | Structural |
| Explicit VR Little Endian | ✓ | ✓ | Structural |
| Explicit VR Big Endian | ✓ | ✓ | Retired by DICOM; kept for interoperability |
| Deflated Explicit VR Little Endian | ✓ | ✓ | Part 10 only; bounded inflation; not negotiated for DIMSE |

### Pixel Data codecs

Built-in codecs are written in Swift, except JPEG 2000, HTJ2K, and JPEG XL,
which use the vendored OpenJPEG 2.5.4, OpenJPH 0.32.0, and libjxl 0.12.0.
Other codecs can be registered through `DICOMCodecRegistry`. UIDs starting with
a dot abbreviate `1.2.840.10008.1.2`.

| Transfer Syntax | UID | Decode | Encode | Qualified against |
| --- | --- | :-: | :-: | --- |
| RLE Lossless | .5 | ✓ | ✓ | PS3.5 Annex G |
| Deflated Image Frame Compression | .8.1 | ✓ | ✓ | Round trips |
| JPEG Baseline and Extended | .4.50, .4.51 | ✓ | ✓ | libjpeg-turbo, bit-exact |
| JPEG retired DCT processes | .4.52 to .4.56 | ✓ | | libjpeg-turbo, bit-exact |
| JPEG Lossless | .4.57, .4.70 | ✓ | ✓ | libjpeg-turbo |
| JPEG Lossless, arithmetic (retired) | .4.58 | ✓ | | ISO reference software |
| JPEG hierarchical (retired) | .4.59 to .4.66 | ✓ | | ISO reference software, with tolerance |
| JPEG-LS Lossless and Near-Lossless | .4.80, .4.81 | ✓ | ✓ | T.87 conformance suite; CharLS, byte-identical |
| JPEG 2000 (Part 1) | .4.90, .4.91 | ✓ | ✓ | OpenJPEG; lossless pairs identical to uncompressed originals |
| HTJ2K | .4.201, .4.202, .4.203 | ✓ | ✓ | Decoded by OpenJPEG, encoded by OpenJPH; cross-checked in both directions |
| JPEG XL | .4.110, .4.111, .4.112 | ✓ | ✓ | libjxl and imagecodecs; recompressed JPEG rebuilt bit for bit |
| JPEG 2000 Part 2 multi-component | .4.92, .4.93 | ✓ | ✓ | Kakadu 8.4.1 in both directions; lossless cases bit-exact, lossy within 1 |
| JPIP Referenced | .4.94, .4.95, .4.204, .4.205 | ✓ | | Frames retrieved from the Pixel Data Provider URL over JPIP and rebuilt as codestreams; kdu_server, every codestream identical through kdu_expand |

Encapsulated frames are located through the Extended or Basic Offset Table, or
from the Fragment layout; under JPEG 2000 Part 2, the frames of a multi-frame
image are decoded by component collection.

### Rendering

| Feature | Support |
| --- | --- |
| Grayscale pipeline | Modality LUT or rescale, then VOI LUT or LINEAR, LINEAR_EXACT, or SIGMOID window; MONOCHROME1 |
| Color | RGB, YBR_FULL, YBR_FULL_422, Palette Color (including segmented) |
| Samples | 1 to 32 bits, float and double, Big Endian |
| Frames | Multi-frame images and functional groups |
| Export | 8-bit PNG, quality-controlled JPEG, uncompressed TIFF, and PGM/PPM on every platform |

### Character sets

Every PS3.3 2026d Specific Character Set Defined Term is read and written, with
nested Data Set inheritance and override. Bundled tables give identical results
on every platform.

| Repertoires | Support |
| --- | --- |
| Single-byte | 13 repertoires |
| ISO 2022 Code Extensions | JIS X 0208 and 0212, KS X 1001, GB 2312, single-byte G1 sets |
| Unicode and Chinese national sets | UTF-8, GB18030-2022, GBK |
| Unknown or invalid declarations | Rejected rather than decoded as UTF-8 |

### Media and other formats

| Area | Status |
| --- | --- |
| DICOMDIR | <ul><li>Legacy Basic hierarchy</li><li>Generic record-tree read and write, with a lossless view of every current F.4-1 type</li><li>Validation of offsets, the record graph, selected F.5 keys, File-set IDs, and referenced Part 10 identities</li></ul> |
| PS3.12 media profiles | Not yet qualified; Basic DICOMDIR support is not a media-profile claim |
| DICOM JSON Model (PS3.18 F) | <ul><li><code>DICOMJSON</code> encode and decode, <code>DcmPrint -f JSON</code></li><li>Matches pydicom on 144 of its 147 readable test files and on the local corpus</li></ul> |
| Native DICOM Model XML (PS3.19 A.1) | <ul><li><code>DICOMXML</code> encode and decode, <code>DcmPrint -f XML</code></li><li>Every output of the pydicom test files and local corpus validates against the normative schema and matches pydicom through the PS3.18 F.3 mapping</li></ul> |
| IOD validation (PS3.3) | <ul><li><code>DICOMIODValidator</code>, <code>DcmValidate</code>, and <code>DcmServer --validate</code></li><li>Reports nothing dicom-validator does not, on the pydicom test files and the local corpus</li></ul> |
| Encapsulated documents (PS3.3 A.45, A.85) | <ul><li><code>DICOMEncapsulatedDocument</code> and <code>DcmDocument</code>: PDF, CDA, STL, OBJ, MTL</li><li>Exchanged with DCMTK both ways; the instances made pass DcmValidate and dicom-validator</li></ul> |
| Waveforms (PS3.3 C.10.9) | <ul><li><code>DICOMWaveform</code> and <code>DcmWaveform</code>: multiplex groups, channels, every sample interpretation including G.711 mu-law and A-law</li><li>Samples and values equal to those of pydicom on its ECG and on files of every interpretation</li></ul> |
| Radiotherapy (PS3.3 A.18 to A.20) | <ul><li><code>DICOMRTStructureSet</code>, <code>DICOMRTDose</code>, <code>DICOMRTPlan</code>, and <code>DcmRT</code>: ROIs and contours, dose grids and DVHs, prescriptions and beams</li><li>Equal to dicompyler-core on the pydicom test files and the local corpus</li></ul> |
| Segmentations and Parametric Maps (PS3.3 A.51, A.75) | <ul><li><code>DICOMSegmentation</code> (BINARY, FRACTIONAL, LABELMAP; making BINARY), <code>DICOMParametricMap</code>, and <code>DcmSeg</code></li><li>Read like pydicom on highdicom instances; DcmSwift Segmentations read back by highdicom</li></ul> |
| Structured Reports (PS3.3 C.17, PS3.16 TID 1500) | <ul><li><code>DICOMStructuredReport</code>: every Value Type read and written; <code>DICOMMeasurementReport</code> and <code>DcmSR measure</code>: TID 1500</li><li>Trees equal to pydicom on 24 reports; DcmSwift reports read by highdicom, dsrdump, and dicom-validator</li></ul> |
| Terminology (PS3.16) | <ul><li>Coding Schemes, DCM codes, and the 1,467 Context Groups of 2026d, with versions and included groups</li><li>Identical to the FHIR value sets NEMA publishes for the edition</li></ul> |
| Robustness | <ul><li>Mutation fuzzing of the parser and pixel decoders, also run under AddressSanitizer</li><li>Reproducers kept as regression fixtures</li></ul> |

### Networking and security

| Area | Status |
| --- | --- |
| DICOM Upper Layer (PS3.8) | <ul><li>Every PDU and item, byte-exact with pynetdicom</li><li>State machine covering all 494 cells of Table 9-10</li><li>Negotiation: role selection, asynchronous operations window, user identity</li><li>Fragmentation and reassembly, large data sets spilled to disk</li><li>ARTIM, idle timeout, release, abort</li></ul> |
| DIMSE-C (PS3.7, PS3.4) | <ul><li>C-ECHO, C-STORE, C-FIND, C-MOVE, C-GET, C-CANCEL</li><li>SCU and SCP, checked against pynetdicom 3.0.4 in both directions</li></ul> |
| DIMSE-N (PS3.7 10) | <ul><li>N-EVENT-REPORT, N-GET, N-SET, N-ACTION, N-CREATE, N-DELETE, SCU and SCP</li><li>Services plugged in per SOP Class</li></ul> |
| Archive storage | <ul><li>Index and instance store behind protocols; memory and JSON-file indexes, Part 10 files</li><li>Database adapters as separate packages, checked by <code>DcmSwiftArchiveConformance</code></li></ul> |
| Modality Worklist (PS3.4 K) | <ul><li>C-FIND SCU and SCP with sequence and combined date-time matching</li><li>Worklist items from memory or a directory</li><li>Responses identical to DCMTK <code>wlmscpfs</code></li></ul> |
| Modality Performed Procedure Step (PS3.4 F) | <ul><li>N-CREATE and N-SET with the IN PROGRESS, COMPLETED, and DISCONTINUED rules of Table F.7.2-1</li><li>Retrieve (N-GET) and Notification (N-EVENT-REPORT)</li><li>Checked against pynetdicom</li></ul> |
| Storage Commitment (PS3.4 J) | <ul><li>Push Model SCU and SCP</li><li>Results on the same association or a new one with role selection</li><li>Checked against pynetdicom in both roles</li></ul> |
| TLS (PS3.15 B.12, B.13) | <ul><li>TLS 1.2 and 1.3 with swift-nio-ssl (BoringSSL); ECDHE with AEAD suites only</li><li>Server verification with host name; mutual authentication; peer certificate given to services</li><li>Checked against Python <code>ssl</code> (OpenSSL) through pynetdicom</li></ul> |
| DICOMweb Studies Service (PS3.18 10) | <ul><li>QIDO-RS, WADO-RS (instances, metadata, frames, Pixel Data, rendered, thumbnails), STOW-RS, Retrieve Capabilities</li><li>User agent on AsyncHTTPClient, origin server on SwiftNIO over HTTP/1.1 or HTTPS</li><li>Server checked with dicomweb-client, client with Orthanc and its DICOMweb plugin</li></ul> |
| De-identification (PS3.15 E) | <ul><li><code>DICOMDeidentifier</code> and <code>DcmAnonymize</code>: Basic Application Level Confidentiality Profile with the Retain and Clean options</li><li>Same table as the 2026c one of dicom-anonymizer but one row added in 2026d; same outcomes on the pydicom test files and the local corpus</li></ul> |
| Audit trail (PS3.15 A.5 to A.7) | <ul><li><code>DICOMAuditMessage</code> for the fifteen messages of A.5.3; <code>DcmServer --audit</code> over syslog TLS or UDP</li><li>Messages validated against the A.5.1 schema and parsed by an independent RFC 5424 parser</li></ul> |
| Digital Signatures (PS3.15 C) | <ul><li><code>DICOMDigitalSigner</code>, <code>DICOMSignatureVerification</code>, and <code>DcmSign</code>: Base RSA profile, at the top level and in Sequence Items</li><li>Signatures checked by DCMTK dcmsign, and dcmsign signatures checked by DcmSwift, on the pydicom test files and the local corpus</li></ul> |
| Encrypted attributes (PS3.3 C.12.1.1.4) | <ul><li><code>DICOMEncryptedAttributes</code>; <code>DcmAnonymize --encrypt-for</code> and <code>--restore-with</code></li><li>CMS envelopes exchanged with <code>openssl cms</code> both ways</li></ul> |

## Command-line tools

Build them with `swift build -c release`; the binaries are in `.build/release`.
Every tool documents its options with `--help`.

| Tool | Purpose |
| --- | --- |
| [DcmPrint](Sources/DcmSwift/DcmSwift.docc/Commands/DcmPrint.md) | Print a data set as text, DICOM JSON, or Native DICOM Model XML |
| [DcmConvert](Sources/DcmSwift/DcmSwift.docc/Commands/DcmConvert.md) | Export frames as PNG, JPEG, TIFF, or PGM/PPM |
| [DcmValidate](Sources/DcmSwift/DcmSwift.docc/Commands/DcmValidate.md) | Validate files against the IODs of PS3.3 |
| [DcmSign](Sources/DcmSwift/DcmSwift.docc/Commands/DcmSign.md) | Sign files and verify their Digital Signatures |
| [DcmDocument](Sources/DcmSwift/DcmSwift.docc/Commands/DcmDocument.md) | Wrap PDF, CDA, STL, OBJ, and MTL documents in DICOM, or extract them |
| [DcmWaveform](Sources/DcmSwift/DcmSwift.docc/Commands/DcmWaveform.md) | Print the channels of a waveform instance or export their samples |
| [DcmRT](Sources/DcmSwift/DcmSwift.docc/Commands/DcmRT.md) | Print RT Structure Sets, Doses, and Plans |
| [DcmSeg](Sources/DcmSwift/DcmSwift.docc/Commands/DcmSeg.md) | Print Segmentations and Parametric Maps, or make binary Segmentations |
| [DcmAnonymize](Sources/DcmSwift/DcmSwift.docc/Commands/DcmAnonymize.md) | De-identify files with the PS3.15 Basic Profile and its options |
| [DcmIzer](Sources/DcmSwift/DcmSwift.docc/Commands/DcmIzer.md) | Wrap a JPEG, PNG, or TIFF image in a DICOM file |
| [DcmSR](Sources/DcmSwift/DcmSwift.docc/Commands/DcmSR.md) | Print a Structured Report tree as text, HTML, or JSON, or make a TID 1500 Measurement Report |
| [DcmEcho](Sources/DcmSwift/DcmSwift.docc/Commands/DcmEcho.md) | Verification SCU |
| [DcmStore](Sources/DcmSwift/DcmSwift.docc/Commands/DcmStore.md) | Storage SCU, with optional Storage Commitment |
| [DcmFind](Sources/DcmSwift/DcmSwift.docc/Commands/DcmFind.md) | Query SCU (C-FIND), including Modality Worklist |
| [DcmServer](Sources/DcmSwift/DcmSwift.docc/Commands/DcmServer.md) | Verification, storage, Query/Retrieve, Storage Commitment, Modality Worklist, and MPPS SCP over directories, also served over DICOMweb |

The network options and TLS settings shared by the network tools are listed in
[Command-Line Tools](Sources/DcmSwift/DcmSwift.docc/Guides/CommandLineTools.md).

## Development

    swift build -c release
    swift test --parallel

The unit suite uses only synthetic fixtures versioned with the source. iOS
builds, the optional interoperability corpus, CI, and the pynetdicom, pydicom,
and DCMTK cross-checks are described in
[Testing and Qualification](Sources/DcmSwift/DcmSwift.docc/Guides/TestingAndQualification.md).

## Dependencies

All dependencies are resolved by Swift Package Manager, except the system
`zlib`.

| Dependency | Use |
| --- | --- |
| [swift-nio](https://github.com/apple/swift-nio), [swift-nio-ssl](https://github.com/apple/swift-nio-ssl) | Networking and TLS |
| [async-http-client](https://github.com/swift-server/async-http-client) | DICOMweb user agent |
| [swift-log](https://github.com/apple/swift-log) | Network logging |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | Command-line tools |
| [swift-html](https://github.com/pointfreeco/swift-html) | HTML rendering of Structured Reports |
| [swift-docc-plugin](https://github.com/swiftlang/swift-docc-plugin) | Documentation |
| OpenJPEG 2.5.4, OpenJPH 0.32.0, libjxl 0.12.0 | JPEG 2000, HTJ2K, and JPEG XL codecs, vendored in `Sources` |
| System `zlib` | Deflate transfer syntaxes |

## Contributing

Contributions are welcome: read [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md). Report vulnerabilities privately, as
described in [SECURITY.md](SECURITY.md). Changes are listed in
[CHANGELOG.md](CHANGELOG.md).

Contributors:

* Rafaël Warnault <rw@opale.pro>
* Paul Repain <pr@opale.pro>
* Colombe Blachère

## License

DcmSwift is released under the [MIT License](LICENSE). The vendored OpenJPEG,
OpenJPH, and libjxl libraries keep their own licenses, reproduced in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
