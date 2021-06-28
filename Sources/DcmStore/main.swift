//
//  DcmStore.swift
//  
//
//  Created by Rafael Warnault on 25/06/2021.
//

import Foundation
import DcmSwift
import ArgumentParser

struct DcmStore: ParsableCommand {
    @Option(name: .shortAndLong, help: "DcmStore local AET")
    var callingAET: String = "DCMCLIENT"
    
    @Argument(help: "Remote AE title")
    var calledAET: String = "DCMSERVER"
    
    @Argument(help: "Remote AE hostname")
    var calledHostname: String = "127.0.0.1"
    
    @Argument(help: "Remote AE port")
    var calledPort: Int = 11112
    
    @Argument(help: "File to store on remote AE")
    var filePath: String
    
    mutating func run() throws {
        let callingAE   = DicomEntity(title: callingAET, hostname: "127.0.0.1", port: 11115)
        let calledAE    = DicomEntity(title: calledAET, hostname: calledHostname, port: calledPort)
        
        let client = DicomClient(localEntity: callingAE, remoteEntity: calledAE)
        
        client.connect { (connected, error) in
            if connected {
                client.store([filePath]) { (progress) in
                    
                } completion: { (ok, message, error) in
                    
                }
            } else {
                if let e = error?.description {
                    Logger.error("CONNECT Error: \(e)")
                }
            }
        }
    }
}

DcmStore.main()
