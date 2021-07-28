//
//  File.swift
//  
//
//  Created by Rafael Warnault, OPALE on 23/07/2021.
//

import Foundation
import NIO

public class CStoreSCUService: ServiceClassUser {
    var filePaths:[String] = []
    
    
    public init(_ filePaths:[String]) {
        self.filePaths = filePaths
    }
    
    
    public override var commandField:CommandField {
        .C_STORE_RQ
    }
    
    
    public override var abstractSyntaxes:[String] {
        DicomConstants.storageSOPClasses
    }
    
    
    public override func request(association:DicomAssociation, channel:Channel) -> EventLoopFuture<Void> {
        for fp in filePaths {
            if let message = PDUEncoder.createDIMSEMessage(pduType: .dataTF, commandField: self.commandField, association: association) as? CStoreRQ {
                let p:EventLoopPromise<Void> = channel.eventLoop.makePromise()
                                
                message.dicomFile = DicomFile(forPath: fp)
                
                if fp != filePaths.last {
                    _ = association.write(message: message, promise: p)
                } else {
                    return association.write(message: message, promise: p)
                }
            }
        }
        
        return channel.eventLoop.makeSucceededVoidFuture()
    }
}
