import Cocoa
import DcmSwift

//let dicomFile1 = DicomFile(forPath: "/Users/nark/Downloads/US-RGB-8-epicard-explicit-big")
//print(dicomFile1?.dataset)
//
//let dicomFile2 = DicomFile(forPath: "/Users/nark/Downloads/CT-MONO2-16-ort-implicit-little")
//print(dicomFile2?.dataset)
//
//let dicomFile3 = DicomFile(forPath: "/Users/nark/Downloads/CT-MONO2-16-brain-explicit-little")
//print(dicomFile3?.dataset)


let dateString = "20021202"
let date = Date(dicomDate: dateString)
