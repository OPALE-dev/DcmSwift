//
//  File.swift
//  
//
//  Created by Paul on 30/06/2021.
//

import Foundation
import DcmSwift
import ArgumentParser

/**
 TODO: Add parameters for C-FIND Query Retrieve Levels (PATIENT, STUDY, SERIES, IMAGE)
 */
struct DcmFind: ParsableCommand {
    @Option(name: .shortAndLong, help: "DcmStore local AET")
    var callingAET: String = "DCMCLIENT"
    
    @Argument(help: "Remote AE title")
    var calledAET: String = "DCMQRSCP"
    
    @Argument(help: "Remote AE hostname")
    var calledHostname: String = "127.0.0.1"
    
    @Argument(help: "Remote AE port")
    var calledPort: Int = 11112
    
    mutating func run() throws {
        // regulate internal logging
        // Logger.setMaxLevel(.INFO)
        
        // create a calling AE, aka your local client (port is totally random and unused)
        let callingAE = DicomEntity(
            title: callingAET,
            hostname: "127.0.0.1",
            port: 11112)
        
        // create a called AE, aka the remote AE you want to connect to
        let calledAE = DicomEntity(
            title: calledAET,
            hostname: calledHostname,
            port: calledPort)

        // create a DICOM client
        let client = DicomClient(
            callingAE: callingAE,
            calledAE: calledAE)
        
        // run C-FIND SCU service
        do {
            // FIND at STUDY-level (by default)
            let results:[DataSet] = try client.find()
            
            // To FIND at SERIES-level, use the following example:
            // let results:[DataSet] = try client.find(queryLevel: .SERIES, instanceUID: "2.16.840.1.113662.5.8796818449476.121423489.1")
            
            if results.count > 0 {
                print("\nC-FIND \(calledAE) SUCCEEDED, \(results.count) found.\n")
                print(results)
            } else {
                print("\nC-FIND \(callingAE) FAILED, no studies found.\n")
            }
        } catch let e {
            Logger.error(e.localizedDescription)
        }
    }
}

DcmFind.main()
