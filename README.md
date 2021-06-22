# DcmSwift

DcmSwift is a (partial, work in progress) DICOM implementation written in Swift. It aims to provide minimal support for the DICOM standard, focusing primarily on the DICOM file format implementation. Other aspects of the standard like networking and imaging will certainly be addressed later. 

## Requirements

* MacOS 10.13
* Xcode 11.5

## Dependencies

* BiAtoms/Socket (networking)
* IBM-Swift/BlueSocket (networking)

*Dependencies of the Xcode project are managed with Carthage.*

## Overview

DcmSwift is written in Swift 4.2 and mainly rely on the Foundation core library, in order to stay as compliant as possible with most of the common Swift toolchains.

A minimal DICOM specification is embed within the `DicomSpec` class itself. It provide a large set of tools to manipulate UIDs, SOP Classes, VRs, Tags and more DICOM specific identifiers.

With the `DicomFile` class you can read/write standard DICOM files (even some broken ones!). It provides an abstract layer through the `DataSet` class and several tools to manipulate inner data. Such objects can be exported to several formats (raw data, XML, JSON) and translated to several Transfer Syntaxes.

The framework also comes with a set of helpers to ease the manipulation of DICOM specific data type like dates, times, endianness, etc. The whole API want to stay as minimal as it is possible (despite the whole DICOM standard wildness), and still giving you a decent set of features to deal with it in a standard and secure way.

DcmSwift is widely used in the **DicomiX** application for macOS, which is available *here*. The app is mainly developed as a showcase of concepts implemented by the DcmSwift framework.

## Install

Follow the instructions below to use DcmSwift framework into your Xcode project.

### Carthage

It is the easiest way to use DcmSwift into your Xcode project. Just add the following to your `Cartfile`:

	# TDB
	
If you do not use Carthage yet and want to give it a try, you will found some instructions here to getting started.

### Subproject

Otherwise, you can link the framework directly from a subproject. The only requirement is to use a Xcode workspace (`.xcworkspace`):

	# TDB

## Getting Started

### Import the framework



### Read a DICOM file

Read a file in memory:

	let dicomFile = DicomFile(forPath: filepath)

Get a DICOM dataset attribute:

	let patientName = dicomFile.dataset.string(forTag: "PatientName")

Set a DICOM dataset attribute:

	dicomFile.dataset.set(value:"John^Doe", forTagName: "PatientName")
	
For a lower memory footprint you can use the `DicomInputStream` class directly as below:

	let inputStream = DicomInputStream(filePath: filepath)
	
	do {
        if let dataset = try inputStream.readDataset(withoutPixelData: true) {
        	print(dataset)
        }
    } catch DicomInputStream.StreamError.notDicomFile {

    } catch DicomInputStream.StreamError.cannotOpenStream {

    } catch DicomInputStream.StreamError.cannotReadStream {

    } catch DicomInputStream.StreamError.datasetIsCorrupted {

    } catch _ {

    }

### Write a DICOM file

Once modified, you can write the data to a file again:

	dicomFile.write(atPath: newPath)

### Export a DICOM file

DcmSwift provides several export format options.

#### Data

#### DICOM

You can export …

#### XML

#### JSON

### More in depth with DataSet

You can load a `DataSet` object directly from data:

	let dataset = DataSet(withData: data)

Or you can create a totally genuine `DataSet` instance and start adding some element to it:

	var dataset = DataSet()
	dataset.set(value:"John^Doe", forTagName: "PatientName")
	dataset.set(value:"12345678", forTagName: "PatientID")
	print(dataset.toData().toHex())

## Unit Tests

## 

## Disclamer

DcmSwift is *not* a medical imaging nor diagnosis oriented library and is not intented to be used as such. It focuses on the computing aspects of the DICOM standard, and provide a powerful set of tools to deal with DICOM files at the atomic level. The authors of this source code cannot be held responsible for its misuses or malfunctions, as it is defined in the license below.

## License

MIT License

Copyright (c) 2019 - Rafaël Warnault <rw@opale.pro>

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