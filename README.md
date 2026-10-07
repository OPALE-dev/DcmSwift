# DcmSwift

DcmSwift is a work-in-progress DICOM implementation written in Swift. The
DcmSwift 2.0 effort currently prioritizes a safe, measurable implementation of
the DICOM file format before expanding the networking stack.

The binary VR/VM, lazy Bulk Data, Deflated Explicit VR Little Endian, and Basic
DICOMDIR milestones are now implemented with structural regression tests. The
remaining binary-file work and media-profile qualification still precede the
PS3.18 JSON and XML representations.

The normative baseline is **DICOM 2026d**. Registry knowledge is kept separate
from actual structural, semantic, codec, and network support: the presence of a
UID in the bundled dictionary does not mean that the corresponding feature is
implemented.

## Requirements

* macOS 10.15 or later, or Linux with a supported Swift toolchain
* Swift 5.9 or later (GitLab CI currently qualifies the package with the
  official Swift 6.1 Linux image)
* system `zlib` development files (`zlib1g-dev` on Debian/Ubuntu, or `zlib`
  through Homebrew on macOS)

Linux is a required DcmSwift 2.0 platform, not a best-effort build target.
Library code, command-line tools, and the platform-independent test suite must
build and run on both Linux and Apple platforms. Image export APIs that require
CoreGraphics/AppKit/UIKit remain conditionally available and are not part of
the Linux API surface.

## Dependencies

* `Kitura/BlueSocket` (networking)
* `apple/swift-nio` (networking)
* `apple/swift-argument-parser` (command-line tools)
* `pointfreeco/swift-html` (HTML rendering of DICOM SR)
* system `zlib` (raw Deflate for DICOM Deflated Explicit VR Little Endian)

*Dependencies are managed by SPM.*

## Build and test

Run the same package-level checks on macOS or Linux:

    swift build -c release
    swift test

The mandatory unit suite uses only small, deterministic synthetic fixtures that
are versioned with the source. It executes identically in a clean checkout on
macOS and Linux and never depends on a private or downloaded corpus.

Large DICOM, DICOMDIR, SR, and RT collections are a separate, explicitly
optional interoperability qualification suite. To run it against a local
corpus:

    DCMSWIFT_INTEROP_CORPUS=/absolute/path/to/corpus \
      swift test --filter DcmSwiftTests/testExternalDICOMCorpus

The qualification suite recursively discovers `.dcm` and `.dicomdir` files.
Its absence does not reduce or skip mandatory unit coverage; it only leaves
this separate qualification run unavailable.

## Disclaimer

DcmSwift is not a medical diagnosis library and is not intended to be used as
one. It focuses on the computing aspects of DICOM and remains under active
qualification. Applications must not infer clinical or IOD conformance merely
because a file can be parsed.

## Overview

DcmSwift mainly relies on Foundation in order to remain usable across common
Swift toolchains.

The runtime tag and UID registry is generated reproducibly from PS3.6 2026d. It
currently contains 5,303 data-element entries and 1,990 UID entries. Command-set
tags are provided by a bootstrap registry until PS3.7 generation is added.

With `DicomFile`, DICOM Part 10 files can be read and written through the
`DataSet` model. Malformed lengths are bounds-checked, File Meta Information is
always written as Explicit VR Little Endian, and its group length is
recalculated during serialization. `DicomInputStream.limits` provides
configurable safeguards for value sizes, element counts, sequence depth,
sequence items, and encapsulated Pixel Data fragments.
Defined and undefined-length Sequences validate Item tags, exact boundaries,
and zero-length Item/Sequence delimiters.
Private Creator Data Elements are recognized as `LO` in implicit VR data sets,
and private block reservations are resolved independently in the top-level data
set and in every Sequence Item. Unknown private values remain byte-preserving
`UN` values unless their explicit VR is present on the wire.
Fixed-width numeric VRs support typed multi-valued encoding and decoding for
signed and unsigned 16/32/64-bit integers and 32/64-bit floating-point values.
Dictionary VM expressions, including bounded ranges and `2-2n`/`3-3n`
multiples, are validated independently from IOD requirements.
Explicit VR parsing rejects unknown VR codes and non-zero reserved bytes in
long-form headers; validation also reports odd-length Value Fields.

For file-backed input, `DicomInputStream.bulkDataLoadingPolicy` can defer
defined-length `OB`, `OD`, `OF`, `OL`, `OV`, `OW`, and `UN` Value Fields above a
configurable threshold. Deferred values expose their source URL, byte offset,
and length through `bulkDataReference`; `loadData()` reports I/O errors, while
the historical `.data` accessor materializes on first use. `loadData(range:)`
can read a bounded subrange without materializing the whole value. The same
policy applies independently to encapsulated Pixel Data fragments; the Basic
Offset Table and each fragment retain their own file ranges.

The library also provides helpers for DICOM dates, times, UIDs, tags, VRs,
endianness, pixel access, Structured Reports, and radiotherapy objects.

## Current DICOM coverage

| Area | Status |
| --- | --- |
| PS3.6 tag and UID registry | Generated from DICOM 2026d |
| Implicit VR Little Endian | Structural read and write |
| Explicit VR Little Endian | Structural read and write |
| Explicit VR Big Endian | Structural read and write for interoperability; retired by DICOM |
| Encapsulated JPEG/RLE transfer syntaxes | Fragment preservation only; no codec claim |
| Deflated Explicit VR Little Endian | Part 10 read/write with raw RFC 1951 streams and bounded inflation; not negotiated for DIMSE |
| Character sets | Default repertoire, ISO_IR 100, and ISO_IR 192, with nested Data Set inheritance/override |
| ISO 2022 code extensions | Not implemented; rejected rather than decoded as UTF-8 |
| DICOM JSON and Native DICOM Model XML | Existing convenience output is not yet PS3.18 conformant |
| DICOMDIR | Legacy Basic hierarchy plus generic record-tree read/write; all current F.4-1 types have a lossless view; computed offsets, graph, selected F.5 keys, File-set IDs, and referenced Part 10 identities are validated |
| PS3.12 media profiles | Not yet qualified; Basic DICOMDIR support is not a media-profile conformance claim |
| DICOM Upper Layer/DIMSE | Experimental; C-ECHO is the most complete path |
| C-STORE and C-FIND | Partial building blocks |
| C-MOVE, C-GET, C-CANCEL and DIMSE-N | Not implemented or not qualified |
| TLS, audit and DICOM security profiles | Not implemented |

See the [DcmSwift 2.0 implementation plan](Documentation/DICOM_2_0_IMPLEMENTATION_PLAN.md)
the [working Conformance Statement](Documentation/DICOM_CONFORMANCE.md), and
the [DICOM traceability matrix](Documentation/DICOM_TRACEABILITY.md) for the
detailed scope, automated evidence, and release gates.
Intentionally deferred gaps are retained in the
[limitations register](Documentation/DICOM_DEFERRED_LIMITATIONS.md) until their
implementation and qualification evidence are complete.

## Use DcmSwift in your project

DcmSwift relies on SPM so all you have to do is to declare it as a dependency of your target in your `Package.swift` file:

    dependencies: [
        .package(url: "https://github.com/OPALE-dev/DcmSwift.git", branch: "master"),
    ]
    
    ...
    
    .target(
        name: "YourTarget",
        dependencies: [
            "DcmSwift"
        ]
        
If you are using Xcode, you can add this package by repository address.

## DICOM files

### Read a DICOM file

Read a file:

    let dicomFile = DicomFile(forPath: filepath)

Get a DICOM dataset attribute:

    let patientName = dicomFile.dataset.string(forTag: "PatientName")

### Write a DICOM file

Set a DICOM dataset attribute:

    dicomFile.dataset.set(value:"John^Doe", forTagName: "PatientName")
    
Once modified, write the dataset to a file again:

    dicomFile.write(atPath: newPath)

## DataSet

### Read dataset 

You can load a `DataSet` object manually using `DicomInputStream`:

    let inputStream = DicomInputStream(filePath: filepath)

    do {
        if let dataset = try inputStream.readDataset() {
            // ...
        }
    } catch {
        Logger.error("Error")
    }
    
`DicomInputStream` can also be initialized with `URL` or `Data` object.

### Create DataSet from scratch

Or you can create a totally genuine `DataSet` instance and start adding some element to it:

    let dataset = DataSet()
    
    dataset.set(value:"John^Doe", forTagName: "PatientName")
    dataset.set(value:"12345678", forTagName: "PatientID")
    
    print(dataset.toData().toHex())
    
Add an element, here a sequence, to a dataset:

    dataset.add(element: DataSequence(withTag: tag, parent: nil))
    
## DICOMDIR

`DicomDir` preserves its legacy Basic Directory PATIENT → STUDY → SERIES →
IMAGE construction API. The `directoryRecordRoots` API additionally writes
arbitrary current PS3.3 record trees from typed `DICOMDirectoryValue` values,
including nested Sequences. The writer calculates record offsets from the final
Explicit VR Little Endian byte layout, validates the hierarchy and required
keys before writing, and rejects invalid PS3.10 Referenced File IDs.
The reader rejects dangling record pointers and resolves referenced files
relative to the DICOMDIR. A generic public record view exposes every current
2026d F.4-1 type without discarding unknown or private attributes. The
`directoryRecordTree` view reconstructs the reachable typed hierarchy from the
serialized sibling and lower-level offsets and refuses malformed or incomplete
graphs.
Unconditional top-level Type 1 and Type 2 keys are represented for every
current F.5 record type, including the Content Identification Macro and the
top-level Scope of Inventory Sequence. Common Type 1C rules validate PRIVATE record UIDs,
complete referenced-SOP identity tuples, and Specific Character Set when a
record key uses an extended repertoire. Present Type 1C keys cannot be empty;
self-contained conditions are enforced for verified SR documents and Hanging
Protocol Definition Items. File-set integrity validation also checks selected
Type 1C keys whose condition is determined by the referenced SOP Instance.
Deeper IOD/module conditions, complete per-type writer qualification,
conditional and nested included-macro validation, and PS3.12 media application
profiles remain outside the currently qualified scope.

Synthetic round-trip coverage exercises all 35 current F.4-1 record types with
their unconditional top-level Type 1/2 keys, including unconditional keys
introduced by included macros. This verifies generic construction, hierarchy
offsets, serialization, and re-reading; it does not yet qualify conditional or
nested semantics of every included macro or referenced-IOD condition.

Included Basic/Enhanced Coded Entry attributes are validated recursively for
code sequences: exactly one code-value form, Code Meaning, Coding Scheme
Designator when applicable, Context Group provenance, and private-extension
provenance. SOP Instance Reference Items in Referenced Image, Instance, and
Waveform Sequences require both referenced UIDs and non-empty Sequences.
Scope of Inventory validates its zero-or-one Item constraint,
extended-matching dependencies, and matching Sequence cardinalities. Other
included-macro conditions and nested semantics remain incremental work.

Optional Icon Image Keys are validated against PS3.3 F.7: exactly one Item,
mandatory Image Pixel attributes, permitted monochrome/palette encodings,
1- or 8-bit unsigned samples, geometry and high-bit consistency, native Pixel
Data length, and required palette descriptors/data. Palette LUT value semantics
and independent display interoperability remain unqualified.

For example, an RT Dose record definition can be added to a Series record's
`children` array with:

```swift
let dose = DICOMDirectoryRecordDefinition(
    type: .rtDose,
    elements: [
        "InstanceNumber": .string("1"),
        "DoseSummationType": .string("PLAN")
    ]
)
```

`validateDirectoryStructure()` checks the Basic Directory container, File-set
ID, required pointer elements, consistency flag, cycles, root chain, and orphan
records. It also checks current Directory Record types and parent/child
relationships against PS3.3 Table F.4-1, requires a UID for PRIVATE records,
and reports retired record types. `validateReferencedFiles()` additionally
checks Referenced File ID
uniqueness and containment, target existence, and agreement of the referenced
SOP Class, SOP Instance, and Transfer Syntax UIDs. These checks do not imply
conformance with a PS3.11 media storage application profile.

The optional non-DICOM File-set Descriptor is represented by
`fileSetDescriptorFileID` and `fileSetDescriptorCharacterSet`; its File ID,
containment, and existence are included in validation. DcmSwift does not yet
decode the descriptor content according to the declared character set.

Get all files indexed by a DICOMDIR file:

    if let dicomDir = DicomDir(forPath: dicomDirPath) {
        print(dicomDir.index)
    }
    
List patients indexed in the DICOMDIR:

    if let dicomDir = DicomDir(forPath: dicomDirPath) {
        print(dicomDir.patients)
    }

Get files indexed by a DICOMDIR file for a specific `PatientID`:

    if let dicomDir = DicomDir(forPath: dicomDirPath) {
        print(dicomDir.index(forPatientID: "198726783"))
    }

## DICOM SR

Load and print SR Tree:

    if let dicomFile = DicomFile(forPath: dicomSRPath) {
        if let doc = dicomFile.structuredReportDocument {
            print(doc)
        }
    }

Load and print SR as HTML:

    if let dicomFile = DicomFile(forPath: dicomSRPath) {
        if let doc = dicomFile.structuredReportDocument {
            print(doc.html)
        }
    }
    
## Networking

### DICOM ECHO

Create a calling AE, aka your local client (port is totally random and unused):
    
    let callingAE = DicomEntity(
        title: callingAET,
        hostname: "127.0.0.1",
        port: 11112)

Create a called AE, aka the remote AE you want to connect to:
   
    let calledAE = DicomEntity(
        title: calledAET,
        hostname: calledHostname,
        port: calledPort)

Create a DICOM client:
    
    let client = DicomClient(
        callingAE: callingAE,
        calledAE: calledAE)

Run C-ECHO SCU service:
    
    if client.echo() {
        print("ECHO \(calledAE) SUCCEEDED")
    } else {
        print("ECHO \(callingAE) FAILED")
    }
    
See source code of embbeded binaries for more network related examples (`DcmFind`, `DcmStore`).

## Using binaries

The DcmSwift package embbed some binaries known as `DcmPrint`, `DcmAnonymize`, `DcmEcho`, etc. which you can build as follow:

    swift build
    
To build release binaries:
    
    swift build -c release
    
Binaries can be found in `.build/release` directory. For example:

    .build/release/DcmPrint /my/dicom/file.dcm

## Unit tests

Run the mandatory synthetic suite with:
    
    swift test

Generated files are written to isolated temporary directories and removed by
the tests. The DcmSwift 2.0 branch currently includes dedicated regression tests
for malformed input, byte order, transfer syntax preservation, character sets,
File Meta Information, modern VRs, pixel offsets, UID handling, and DIMSE
command encoding.

The external interoperability corpus is intentionally not distributed with the
package. Set `DCMSWIFT_INTEROP_CORPUS` and use the qualification command from
the Build and test section when such a corpus is available. A successful unit
run does not claim interoperability with files that were not qualified.
    
## Documentation

Documentation can be generated using `jazzy`:

    jazzy \
      --module DcmSwift \
      --swift-build-tool spm \
      --build-tool-arguments -Xswiftc,-swift-version,-Xswiftc,5
      
Or with swift doc:

    swift doc generate \
        --module-name DcmSwift Sources/DcmSwift/Data \
        --minimum-access-level private \
        --output docs --format html
    
## Side notes

### For testing/debuging networking

Very useful DCMTK arguments for `storescp` program that show a lot of logs: 

    storescp 11112 --log-level trace

Another alternative is `storescp` program from dcm4chee (5.x), but without the precision DCMTK offers.

    storescp -b STORESCP@127.0.0.1:11112
    
DCMTK proposes also a server, for testing `cfind` program:

    dcmqrscp 11112 --log-level trace -c /path/to/config/dcmqrscp.cfg

All the executables from both `DCMTK` and `dcm4chee` are very good reference for testing DICOM features.

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
