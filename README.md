# DcmSwift

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
| Guides | <ul><li>[Files and Data Sets](Sources/DcmSwift/DcmSwift.docc/Guides/FilesAndDataSets.md)</li><li>[Rendering Images](Sources/DcmSwift/DcmSwift.docc/Guides/RenderingImages.md)</li><li>[DICOMDIR](Sources/DcmSwift/DcmSwift.docc/Guides/DICOMDIR.md)</li><li>[Structured Reports](Sources/DcmSwift/DcmSwift.docc/Guides/StructuredReports.md)</li><li>[Networking](Sources/DcmSwift/DcmSwift.docc/Guides/Networking.md)</li></ul> |
| Qualification | <ul><li>[Conformance Statement](Sources/DcmSwift/DcmSwift.docc/Qualification/Conformance.md) (working draft)</li><li>[Traceability matrix](Sources/DcmSwift/DcmSwift.docc/Qualification/Traceability.md): requirements and their tests</li><li>[Deferred limitations](Sources/DcmSwift/DcmSwift.docc/Qualification/DeferredLimitations.md)</li><li>[Implementation plan](Sources/DcmSwift/DcmSwift.docc/Qualification/ImplementationPlan.md)</li></ul> |
| Contributing | <ul><li>[Testing and Qualification](Sources/DcmSwift/DcmSwift.docc/Guides/TestingAndQualification.md): tests, corpus, CI, interoperability scripts</li><li>[Documentation Workflow](Sources/DcmSwift/DcmSwift.docc/Guides/DocumentationWorkflow.md)</li></ul> |

Preview the documentation, or build the static site:

    Scripts/documentation/preview.sh
    Scripts/documentation/build.sh .build/documentation

## Requirements

| Requirement | Details |
| --- | --- |
| Platforms | <ul><li>macOS 10.15 or later</li><li>iOS 13 or later</li><li>Linux</li></ul> |
| Swift | 5.9 or later; CI uses Swift 6.1 on Linux and the current Xcode on macOS and iOS |
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
| JPIP Referenced | .4.94, .4.95, .4.204, .4.205 | | | Preserved and negotiated; pixel retrieval through JPIP planned (Phase 4) |

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
| Robustness | <ul><li>Mutation fuzzing of the parser and pixel decoders, also run under AddressSanitizer</li><li>Reproducers kept as regression fixtures</li></ul> |

### Networking and security

| Area | Status |
| --- | --- |
| DICOM Upper Layer (PS3.8) | <ul><li>Every PDU and item, byte-exact with pynetdicom</li><li>State machine covering all 494 cells of Table 9-10</li><li>Negotiation: role selection, asynchronous operations window, user identity</li><li>Fragmentation and reassembly, large data sets spilled to disk</li><li>ARTIM, idle timeout, release, abort</li></ul> |
| DIMSE-C (PS3.7, PS3.4) | <ul><li>C-ECHO, C-STORE, C-FIND, C-MOVE, C-GET, C-CANCEL</li><li>SCU and SCP, checked against pynetdicom 3.0.4 in both directions</li></ul> |
| DIMSE-N (PS3.7 10) | <ul><li>N-EVENT-REPORT, N-GET, N-SET, N-ACTION, N-CREATE, N-DELETE, SCU and SCP</li><li>Services plugged in per SOP Class</li></ul> |
| Storage Commitment (PS3.4 J) | <ul><li>Push Model SCU and SCP</li><li>Results on the same association or a new one with role selection</li><li>Checked against pynetdicom in both roles</li></ul> |
| TLS (PS3.15 B.12, B.13) | <ul><li>TLS 1.2 and 1.3 with swift-nio-ssl (BoringSSL); ECDHE with AEAD suites only</li><li>Server verification with host name; mutual authentication; peer certificate given to services</li><li>Checked against Python <code>ssl</code> (OpenSSL) through pynetdicom</li></ul> |
| Audit and other security profiles | Not implemented |

## Command-line tools

Build them with `swift build -c release`; the binaries are in `.build/release`.
Every tool documents its options with `--help`.

| Tool | Purpose |
| --- | --- |
| [DcmPrint](Sources/DcmSwift/DcmSwift.docc/Commands/DcmPrint.md) | Print a data set as text, DICOM JSON, or Native DICOM Model XML |
| [DcmConvert](Sources/DcmSwift/DcmSwift.docc/Commands/DcmConvert.md) | Export frames as PNG, JPEG, TIFF, or PGM/PPM |
| [DcmAnonymize](Sources/DcmSwift/DcmSwift.docc/Commands/DcmAnonymize.md) | Write an anonymized copy of a file |
| [DcmIzer](Sources/DcmSwift/DcmSwift.docc/Commands/DcmIzer.md) | Wrap a JPEG, PNG, or TIFF image in a DICOM file |
| [DcmSR](Sources/DcmSwift/DcmSwift.docc/Commands/DcmSR.md) | Print a Structured Report tree or render it as HTML |
| [DcmEcho](Sources/DcmSwift/DcmSwift.docc/Commands/DcmEcho.md) | Verification SCU |
| [DcmStore](Sources/DcmSwift/DcmSwift.docc/Commands/DcmStore.md) | Storage SCU, with optional Storage Commitment |
| [DcmFind](Sources/DcmSwift/DcmSwift.docc/Commands/DcmFind.md) | Query SCU (C-FIND) |
| [DcmServer](Sources/DcmSwift/DcmSwift.docc/Commands/DcmServer.md) | Verification, storage, Query/Retrieve, and Storage Commitment SCP over a directory |

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
| [swift-log](https://github.com/apple/swift-log) | Network logging |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | Command-line tools |
| [swift-html](https://github.com/pointfreeco/swift-html) | HTML rendering of Structured Reports |
| [swift-docc-plugin](https://github.com/swiftlang/swift-docc-plugin) | Documentation |
| OpenJPEG 2.5.4, OpenJPH 0.32.0, libjxl 0.12.0 | JPEG 2000, HTJ2K, and JPEG XL codecs, vendored in `Sources` |
| System `zlib` | Deflate transfer syntaxes |

## Contributors

* Rafaël Warnault <rw@opale.pro>
* Paul Repain <pr@opale.pro>
* Colombe Blachère

## License

MIT License

Copyright (c) 2019 - OPALE, https://www.opale.fr

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
