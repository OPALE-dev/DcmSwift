# DcmSwift

DcmSwift is a DICOM implementation written in the Swift programming language. It aims to provide minimal support for the DICOM standard, focusing primarily on the DICOM file format implementation. Other aspects of the standard like networking and imaging will certainly be addressed later. 

## Requirements

* MacOS 10.12
* Xcode 10

## Dependencies

* BlueSocket
* SwiftyBeaver

*Dependencies are managed using the Carthage package manager.*

## Overview

DcmSwift is written in Swift 4.2 and mainly rely on the Foundation core library, in order to be compliant with most of the common Swift toolchains (Linux).

## Getting Started

### Read a DICOM file

Identify if a given file is readable as a DICOM file by the framework:

		if DicomFile.isDicomFile(filepath) {
			print("Yes !")
		}

Read the file in memory:

		let dicomFile = DicomFile(forPath: filepath)

Read the DICOM dataset:

		let patientName = dicomFile.dataset.string(forTag: "PatientName")

Modify the DICOM dataset:

		dicomFile.dataset.set(value:"John^Doe", forTagName: "PatientName")

### Write a DICOM file

Once modified, you can write the data to a file again:

		dicomFile.write(atPath: newPath)

### Export a DICOM file

DcmSwift provides several export format options.

#### To DICOM

You can export …

#### To XML

#### To JSON