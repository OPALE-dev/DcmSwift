//
//  File.swift
//  
//
//  Created by Paul on 30/06/2021.
//

import Foundation
import DcmSwift
import ArgumentParser

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
        // disable internal logging with .ERROR
        Logger.setMaxLevel(.VERBOSE)
        
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
        
        // run C-ECHO SCU service
        if client.find().count > 0 {
            print("FIND \(calledAE) SUCCEEDED")
        } else {
            print("FIND \(callingAE) FAILED")
        }
    }
}

DcmFind.main()
