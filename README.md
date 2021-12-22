# DcmSwift

DcmSwift is a (partial, work in progress) DICOM implementation written in Swift. It aims to provide minimal support for the DICOM standard, focusing primarily on the DICOM file format implementation. Other aspects of the standard like networking and imaging will certainly be addressed later. 

## Requirements

* MacOS 10.13
* Xcode 12.4
* Swift 5.3

## Dependencies

* `IBM-Swift/BlueSocket` (networking)
* `pointfreeco/swift-html` (HTML rendering of DICOM SR)

*Dependencies are managed by SPM.*

## Disclamer

DcmSwift is *not* a medical imaging nor diagnosis oriented library and is not intented to be used as such. It focuses on the computing aspects of the DICOM standard, and provide a powerful set of tools to deal with DICOM files at the atomic level. The authors of this source code cannot be held responsible for its misuses or malfunctions, as it is defined in the license below.

## Overview

DcmSwift is written in Swift 5.3 and mainly rely on the Foundation core library, in order to stay as compliant as possible with most of the common Swift toolchains.

A minimal DICOM specification is embed within the `DicomSpec` class itself. It provide a large set of tools to manipulate UIDs, SOP Classes, VRs, Tags and more DICOM specific identifiers.

With the `DicomFile` class you can read/write standard DICOM files (even some broken ones!). It provides an abstract layer through the `DataSet` class and several tools to manipulate inner data. Such objects can be exported to several formats (raw data, XML, JSON) and translated to several Transfer Syntaxes.

The library also comes with a set of helpers to ease the manipulation of DICOM specific data type like dates, times, endianness, etc. The whole API want to stay as minimal as it is possible (despite the whole DICOM standard wildness), and still giving you a decent set of features to deal with it in a standard and secure way.

DcmSwift is widely used in the **DicomiX** application for macOS, which is available *here*. The app is mainly developed as a showcase of concepts implemented by the DcmSwift library.

## Use DcmSwift in your project

DcmSwift relies on SPM so all you have to do is to declare it as a dependency of your target in your `Package.swift` file:

    dependencies: [
        .package(name: "DcmSwift", url: "http://gitlab.dev.opale.pro/rw/DcmSwift.git", from:"0.0.1"),
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

## Unit Tests

Before running the tests suite, you need to download test resources with this embedded script:

    ./test.sh

Run the command:
    
    swift test
    
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

Copyright (c) 2019 - OPALE <contact@opale.pro>

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
