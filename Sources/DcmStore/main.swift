//
//  DcmStore.swift
//  
//
//  Created by Rafael Warnault, OPALE on 25/06/2021.
//

import Foundation
import DcmSwift
import ArgumentParser

/**
 `DcmStore` (aka `dcm-store`) is a very simple C-STORE-SCU program
 able to send files to a remote C-STORE-SCP peer.
 */
struct DcmStore: ParsableCommand {
    @Option(name: .shortAndLong, help: "DcmStore local AET")
    var callingAET: String = "DCMCLIENT"
    
    @Argument(help: "Remote AE title")
    var calledAET: String = "DCMSERVER"
    
    @Argument(help: "Remote AE hostname")
    var calledHostname: String = "127.0.0.1"
    
    @Argument(help: "Remote AE port")
    var calledPort: Int = 11112
    
    @Argument(help: "Files to store on remote AE")
    var filePaths: [String]
    
    
    mutating func run() throws {
        let callingAE   = DicomEntity(title: callingAET, hostname: "127.0.0.1", port: 11115)
        let calledAE    = DicomEntity(title: calledAET, hostname: calledHostname, port: calledPort)
        
        // create a DICOM client
        let client = DicomClient(
            callingAE: callingAE,
            calledAE:  calledAE)
        
        // run C-STORE SCU service to send files given as arguements
        do {
            if try client.store(filePaths: flattenPaths(filePaths)) {
                print("\nC-STORE \(calledAE) SUCCEEDED.\n")
            } else {
                print("\nC-STORE \(calledAE) FAILED.\n")
            }
        } catch let e {
            Logger.error(e.localizedDescription)
        }
    }
    
    
    /**
     Recursively flatten paths given by arguments, browsing directories and subdirectories for DICOM files
     */
    private func flattenPaths(_ paths:[String]) -> [String] {
        var outputs:[String] = []
        
        for path in paths {
            var isDir:ObjCBool = false
            
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                if isDir.boolValue {
                    if let subnames = try? FileManager.default.contentsOfDirectory(atPath: path) {
                        var subPaths:[String] = []
                    
                        for sn in subnames {
                            subPaths.append("\(path)/\(sn)")
                        }
                        
                        outputs.append(contentsOf: flattenPaths(subPaths))
                    }
                    
                } else {
                    if DicomFile.isDicomFile(path) {
                        outputs.append(path)
                    }
                }
            }
        }
        
        return outputs
    }
}

DcmStore.main()
