# DcmSwift

DcmSwift is a work-in-progress DICOM implementation written in Swift. The
DcmSwift 2.0 effort currently prioritizes a safe, measurable implementation of
the DICOM file format before expanding the networking stack.

The remaining file roadmap prioritizes binary VR/VM completeness, lazy Bulk
Data, Deflated Explicit VR Little Endian, and DICOMDIR before the PS3.18 JSON
and XML representations.

The normative baseline is **DICOM 2026d**. Registry knowledge is kept separate
from actual structural, semantic, codec, and network support: the presence of a
UID in the bundled dictionary does not mean that the corresponding feature is
implemented.

## Requirements

* macOS 10.15 or later
* Swift 5.9 or later

## Dependencies

* `Kitura/BlueSocket` (networking)
* `apple/swift-nio` (networking)
* `apple/swift-argument-parser` (command-line tools)
* `pointfreeco/swift-html` (HTML rendering of DICOM SR)

*Dependencies are managed by SPM.*

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
| Deflated Explicit VR Little Endian | Known, not implemented |
| Character sets | Default repertoire, ISO_IR 100, and ISO_IR 192, with nested Data Set inheritance/override |
| ISO 2022 code extensions | Not implemented; rejected rather than decoded as UTF-8 |
| DICOM JSON and Native DICOM Model XML | Existing convenience output is not yet PS3.18 conformant |
| DICOMDIR/media profiles | Partial and not yet claimed conformant |
| DICOM Upper Layer/DIMSE | Experimental; C-ECHO is the most complete path |
| C-STORE and C-FIND | Partial building blocks |
| C-MOVE, C-GET, C-CANCEL and DIMSE-N | Not implemented or not qualified |
| TLS, audit and DICOM security profiles | Not implemented |

See the [DcmSwift 2.0 implementation plan](Documentation/DICOM_2_0_IMPLEMENTATION_PLAN.md)
the [working Conformance Statement](Documentation/DICOM_CONFORMANCE.md), and
the [DICOM traceability matrix](Documentation/DICOM_TRACEABILITY.md) for the
detailed scope, automated evidence, and release gates.

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
        if let files = dicomDir.index(forPatientID: "198726783") {
            print(files)
        }
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

The repository includes DICOM fixtures. If those resources are absent from a
source archive, retrieve them with:

    ./test.sh

Run the complete suite with:
    
    swift test

Generated files are written to isolated temporary directories and removed by
the tests. The DcmSwift 2.0 branch currently includes dedicated regression tests
for malformed input, byte order, transfer syntax preservation, character sets,
File Meta Information, modern VRs, pixel offsets, UID handling, and DIMSE
command encoding.
    
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
