//
//  File.swift
//  
//
//  Created by Rafael Warnault on 31/01/2022.
//

import AppKit
import DcmSwift
import ArgumentParser


extension Data {
    var bytes: [UInt8] {
        return [UInt8](self)
    }
}


struct DcmIzer: ParsableCommand {
    @Argument(help: "Path of JPEG/PNG/TIFF image to dicomize")
    var inputPath: String

    @Argument(help: "Path of the DICOM output file")
    var outputPath: String
    
    mutating func run() throws {
        if let image = NSImage(contentsOfFile: inputPath) {
            
            if let tiffRepresentation = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiffRepresentation) {
                if let data = rep.representation(using: .jpeg2000, properties: [:]) {
                    print(data)
                    
                    let dataset = DataSet()
                    
                    _ = dataset.set(value: 200, forTagName: "FileMetaInformationGroupLength")
                    _ = dataset.set(value: 0x0001, forTagName: "FileMetaInformationVersion")
                    _ = dataset.set(value: "1.2.840.10008.5.1.4.1.1.2", forTagName: "MediaStorageSOPClassUID")
                    _ = dataset.set(value: "1.2.300000.400000000.500000000000.6", forTagName: "MediaStorageSOPInstanceUID")
                    _ = dataset.set(value: "1.2.840.10008.1.2.1", forTagName: "TransferSyntaxUID")
                    
                    _ = dataset.set(value:"John^Doe", forTagName: "PatientName")
                    _ = dataset.set(value:"12345678", forTagName: "PatientID")
                    _ = dataset.set(value: data, forTagName: "PixelData")
                    
                    dataset.hasPreamble = true
                    
                    let file = DicomFile(withDataset: dataset, hasPreamble: true)
                    
                    file?.write(atPath: outputPath)
                }
            }
            
//            for r in image.representations {
//                if let rep = r as? NSBitmapImageRep {
//                    if !rep.isPlanar {
//                        var bpp = rep.bitsPerPixel / rep.samplesPerPixel
//                        var spp = rep.samplesPerPixel
//                        let width = rep.pixelsWide
//                        let height = rep.pixelsHigh
//
//                        if rep.bitsPerPixel == 32 && spp == 3  {
//                            bpp = 8
//                            spp = 4
//                        }
//
//                        rep.bitmapData
//                    }
//                }
//            }
            
            
            
//            if let rep = image.bestRepresentation(for: image.alignmentRect, context: NSGraphicsContext.current, hints: nil) {
//                print(rep)
//            }
        }
    }
}

DcmIzer.main()
