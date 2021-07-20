//
//  File.swift
//  
//
//  Created by Rafael Warnault on 20/07/2021.
//

import Foundation
import NIO

public class DicomService {
    public init() {
        
    }
    
    
    public func run(association:DicomAssociation, channel:Channel) -> EventLoopFuture<Void> {
        if let message = PDUEncoder.createDIMSEMessage(pduType: .dataTF, commandField: .C_ECHO_RQ, association: association) as? PDUMessage {
            let p:EventLoopPromise<Void> = channel.eventLoop.makePromise()
            return association.write(message: message, promise: p)
        }
        return channel.eventLoop.makeSucceededVoidFuture()
    }
}


public class CEchoSCUService: DicomService {
    
}

public class CFindSCUService: DicomService {
    
}

public class CSoreSCUService: DicomService {
    
}
