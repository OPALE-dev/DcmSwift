import Cocoa
import DcmSwift

let dicomFile = DicomFile(forPath: "/Users/nark/Desktop/Test Files/US-RGB-8-epicard")

if let dicomImage = dicomFile?.dataset.dicomImage {
    let image = dicomImage.image()
}

let dicomFile2 = DicomFile(forPath: "/Users/nark/Desktop/Test Files/US-RGB-8-esopecho")

if let dicomImage2 = dicomFile2?.dataset.dicomImage {
    let image = dicomImage2.image()
}

let dicomFile3 = DicomFile(forPath: "/Users/nark/Desktop/Test Files/MR-MONO2-16-knee")

if let dicomImage3 = dicomFile3?.dataset.dicomImage {
    let image = dicomImage3.image()
}

let dicomFile4 = DicomFile(forPath: "/Users/nark/Desktop/Test Files/MR-MONO2-12-shoulder")

if let dicomImage4 = dicomFile4?.dataset.dicomImage {
    let image = dicomImage4.image()
}
