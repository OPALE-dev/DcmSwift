//
//  main.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 17/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Foundation
import DcmSwift
//
//
//

var client = DicomClient(localAET: "TEST", remoteAET: "OSIRIXRW", remoteHost: "localhost", remotePort: 4097)



//var path = ""
//var dicomFile:DicomFile!
//
//
//
//path            = "/Users/nark/Desktop/test2.dcm"
//dicomFile       = DicomFile(forPath: path)
//
//
//
//// TEST PRINT DATASET
//Swift.print("\(dicomFile?.dataset.description ?? "")")
//
//
//// TEST PRINT JSON
//Swift.print("\(dicomFile?.dataset.toJSON() ?? "")")




// TEST WRITE FILE
//if dicomFile.dataset.write(atPath: "/Users/nark/Desktop/MG-MONO2-16 (Little Endian Explicit VR)-saved.dcm") {
//    Swift.print("Write file succeeded")
//} 




// TEST IMAGE
//if let image = dicomFile.dataset.dicomImage?.cgImage() {
//    Swift.print(writeCGImage(image, to: URL(fileURLWithPath: "/Users/nark/Desktop/test3.png")))
//}


//// TEST READ TAG VALUES
//if let patientName = dicomFile.dataset.string(forTag: "PatientName") {
//    print(patientName)
//}
////
//if let patientBirthDate = dicomFile.dataset.date(forTag: "StudyDate") {
//    print(patientBirthDate)
//}
//
