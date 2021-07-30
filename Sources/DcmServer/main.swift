//
//  File.swift
//  
//
//  Created by Rafael Warnault, OPALE on 25/06/2021.
//

import Foundation
import DcmSwift
import ArgumentParser

struct DcmServer: ParsableCommand {
    mutating func run() throws {
        let server = DicomServer(
            port: 11112,
            localAET: "DCMSERVER",
            config: ServerConfig(
                enableCEchoSCP : true,
                enableCFindSCP : true,
                enableCStoreSCP: true
            )
        )

        if #available(OSX 10.12, *) {
            //Thread.detachNewThread {
                server.start()
            //}
        } else {
            Logger.error("MacOS 10.12 or newer is required")
        }
    }
}

DcmServer.main()
