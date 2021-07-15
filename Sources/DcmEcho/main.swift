//
//  DcmEcho.swift
//  
//
//  Created by Rafael Warnault, OPALE on 25/06/2021.
//

import Foundation
import DcmSwift
import ArgumentParser

struct DcmEcho: ParsableCommand {
    @Option(name: .shortAndLong, help: "DcmEcho local AET")
    var callingAET: String = "DCMCLIENT"
    
    @Argument(help: "Remote AE title")
    var calledAET: String = "DCMSERVER"
    
    @Argument(help: "Remote AE hostname")
    var calledHostname: String = "127.0.0.1"
    
    @Argument(help: "Remote AE port")
    var calledPort: Int = 11112
    
    mutating func run() throws {
        // create a calling AE, aka your local client (port is totally random and unused)
        let callingAE = DicomEntity(title: callingAET, hostname: "127.0.0.1", port: 11112)
        
        // create a called AE, aka the remote AE you want to connect to
        let calledAE = DicomEntity(title: calledAET, hostname: calledHostname, port: calledPort)

        // create a `DicomClient` instance
        let client = DicomClient(localEntity: callingAE, remoteEntity: calledAE)
        
        // connect the client
        client.connect {
            // send C-ECHO-RQ message
            client.echo {
            // receive C-ECHO-RSP message
            (request, message, assoc) in
                // if DIMSE status is Success
                if message.dimseStatus.status == .Success {
                    Logger.info("ECHO Succeeded: \(message.dimseStatus.status)")
                } else {
                    // else other status
                    Logger.error("ECHO Failed: \(message.dimseStatus.status)")
                }
            }
            
            // receive A-ABORT message or other processing error
            abortCompletion: { (message, error) in
                if let e = error?.description {
                    Logger.error("ECHO Failed: \(e)")
                }
            }
            
            // when association closed
            closeCompletion: { (association) in
                
            }
        // client connection error
        } errorCompletion: { (error) in
            if let e = error?.description {
                Logger.error("CONNECT Error: \(e)")
            }
        }
        
        _ = client.disconnect()
    }
}

DcmEcho.main()
