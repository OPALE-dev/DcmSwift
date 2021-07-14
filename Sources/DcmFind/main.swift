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
        let callingAE   = DicomEntity(title: callingAET, hostname: "127.0.0.1", port: 11115)
        let calledAE    = DicomEntity(title: calledAET, hostname: calledHostname, port: calledPort)
        
        let client = DicomClient(localEntity: callingAE, remoteEntity: calledAE)
        
        client.connect {
            let dataset = DataSet()
            _ = dataset.set(value:"", forTagName: "PatientID")
            _ = dataset.set(value:"", forTagName: "PatientName")
            _ = dataset.set(value:"", forTagName: "PatientBirthDate")
            _ = dataset.set(value:"", forTagName: "StudyDescription")
            _ = dataset.set(value:"", forTagName: "StudyDate")
            _ = dataset.set(value:"", forTagName: "StudyTime")
            
            client.find(dataset) { (request, message) in
                if message.dimseStatus.status == .Success {
                    if let m = request as? CFindRQ {
                       print(m.queryResults)
                    }
                }
                
            } errorCompletion: { (message, error) in

            } closeCompletion: { (assoc) in
                
            }
        } errorCompletion: { (error) in
            if let e = error?.description {
                Logger.error("CONNECT Error: \(e)")
            }
        }
    }
}

DcmFind.main()
