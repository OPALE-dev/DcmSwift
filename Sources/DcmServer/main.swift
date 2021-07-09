//
//  File.swift
//  
//
//  Created by Rafael Warnault on 25/06/2021.
//

import Foundation
import DcmSwift
import ArgumentParser

struct DcmServer: ParsableCommand {
    mutating func run() throws {
        let server = DicomServer(port: 11112, localAET: "DCMSERVER")

        server.start()
    }
}

DcmServer.main()
