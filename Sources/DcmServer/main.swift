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
        let server = DicomServer(port: 11114, localAET: "DCMSERVER")

        if #available(OSX 10.12, *) {
            server.run()
        } else {
            Logger.error("MacOS 10.12 minimum required")
        }
    }
}

DcmServer.main()
