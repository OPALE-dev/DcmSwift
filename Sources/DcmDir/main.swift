//
//  main.swift
//  
//
//  Created by Rafael Warnault, OPALE on 29/06/2021.
//

import Foundation
import ArgumentParser
import DcmSwift

struct DcmDir: ParsableCommand {
    @Argument(help: "Path of DICOMDIR file to read")
    var dicomDirPath: String

    mutating func run() throws {
        if let dicomDir = DicomDir(forPath: dicomDirPath) {
           print(dicomDir.patients)
//            print(dicomDir.studies)
//            print(dicomDir.series)
//            print(dicomDir.images)
            
            // test all paths
//            for path in dicomDir.filePaths {
//                print(path)
//            }
            
            // test by type
//            for (patientID, patientName) in dicomDir.patients {
//                print("ID: \(patientID) -> \(patientName)")
//            }
//
//            print("\n")
//
//            for (stuid, pid) in dicomDir.studies {
//                print("ID: \(pid) -> \(stuid)")
//            }
//
//            print("\n")
//
//            for (stuid, seuid) in dicomDir.series {
//                print("STUID: \(stuid) -> \(seuid)")
//            }
//
//            print("\n")
//
//            for (sopuid, array) in dicomDir.images {
//                print("SOPUID: \(sopuid) -> \(array)")
//            }
            
            // test query by pid
            let paths = dicomDir.imagePaths(forPatientID: "21000003")
            
            print(paths)
        }
    }
}

DcmDir.main()
