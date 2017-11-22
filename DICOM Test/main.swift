//
//  main.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 17/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Foundation
import DcmSwift







var path = ""
var dicomFile:DicomFile!



path            = "/Users/nark/Desktop/MR-MONO2-16-knee (Little Endian Implicit VR).dcm"
dicomFile       = DicomFile(forPath: path)



// TEST PRINT DATASET
Swift.print("\(dicomFile?.dataset.description ?? "")")




// TEST WRITE FILE
if dicomFile.dataset.write(atPath: "/Users/nark/Desktop/MR-MONO2-16-knee (Little Endian Implicit VR)-saved.dcm") {
    Swift.print("Write file succeeded")
} 




// TEST IMAGE
//if let image = dicomFile.dataset.dicomImage?.cgImage() {
//    Swift.print(writeCGImage(image, to: URL(fileURLWithPath: "/Users/nark/Desktop/US-RGB-8-epicard.pngrr")))
//}
//
//// TEST READ TAG VALUES
//if let patientName = dicomFile.dataset.string(forTag: "PatientName") {
//    print(patientName)
//}
////
//if let patientBirthDate = dicomFile.dataset.date(forTag: "StudyDate") {
//    print(patientBirthDate)
//}
//
