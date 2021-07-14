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
        // create a calling AE, aka your local client (port is totally random and unused)
        let callingAE = DicomEntity(title: callingAET, hostname: "127.0.0.1", port: 11115)
        
        // create a called AE, aka the remote AE you want to connect to
        let calledAE = DicomEntity(title: calledAET, hostname: calledHostname, port: calledPort)
        
        // create a `DicomClient` instance
        let client = DicomClient(localEntity: callingAE, remoteEntity: calledAE)
        
        // connect client
        client.connect {
            // Create a query dataset
            let queryDataset = DataSet()
            _ = queryDataset.set(value:"", forTagName: "PatientID")
            _ = queryDataset.set(value:"", forTagName: "PatientName")
            _ = queryDataset.set(value:"", forTagName: "PatientBirthDate")
            _ = queryDataset.set(value:"", forTagName: "StudyDescription")
            _ = queryDataset.set(value:"", forTagName: "StudyDate")
            _ = queryDataset.set(value:"", forTagName: "StudyTime")
            _ = queryDataset.set(value:"", forTagName: "AccessionNumber")
            
            // perform a C-FIND-RQ query
            client.find(queryDataset) {
            // receive C-FIND-RQ message
            (request, message, assoc) in
                // when last message
                if message.dimseStatus.status == .Success {
                    // infer to CFindRQ subtype of PDUMessage
                    if let m = request as? CFindRQ {
                        Logger.info(m.queryResults.description, "DcmFind")
                    }
                }
            }
            // receive A-ABORT message or other processing error
            abortCompletion: { (message, error) in
                if let e = error?.description {
                    Logger.error("C-FIND Error: \(e)", "DcmFind")
                }
            }
            // when assoc close
            closeCompletion: { (assoc) in
                
            }
        // client connect error
        } errorCompletion: { (error) in
            if let e = error?.description {
                Logger.error("CONNECT Error: \(e)", "DcmFind")
            }
        }
        
        _ = client.disconnect()
    }
}

DcmFind.main()
