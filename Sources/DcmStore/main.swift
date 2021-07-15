//
//  DcmStore.swift
//  
//
//  Created by Rafael Warnault, OPALE on 25/06/2021.
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
        
        let client      = DicomClient(localEntity: callingAE, remoteEntity: calledAE)
        let files       = [filePath]
        
        client.connect {
            client.store([filePath]) { (progress) in
                Logger.info("Progress: \(progress)/\(files.count)", "DcmStore")
                
            } pduCompletion: { (request, message, assoc) in

            } abortCompletion: { (message, error) in

            } closeCompletion: { (assoc) in

            }
        } errorCompletion: { (error) in
            if let e = error?.description {
                Logger.error("CONNECT Error: \(e)")
            }
        }
        
        _ = client.disconnect()
    }
}

DcmStore.main()
