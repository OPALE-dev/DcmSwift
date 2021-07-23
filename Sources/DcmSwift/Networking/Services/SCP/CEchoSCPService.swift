//
//  File.swift
//  
//
//  Created by Rafael Warnault on 23/07/2021.
//

import Foundation
import NIO


public protocol CEchoSCPDelegate {
    /**
     This method is called by C-ECHO-SCP service for a delegate to validatethe request
     and reply the appropriate DIMSE status.
     
     If no delegate has been set, C-ECHO-SCP service replies Success status by default,
     except if called AE title is not recongnize.
     */
    func validateEcho(callingAE: DicomEntity) -> DIMSEStatus.Status
}


public class CEchoSCPService: ServiceClassProvider {
    private var delegate:CEchoSCPDelegate?
    
    public override var commandField:CommandField {
        .C_ECHO_RSP
    }
    
    
    public init(_ delegate:CEchoSCPDelegate?) {
        super.init()
        
        self.delegate = delegate
    }
    
    public override func run(association:DicomAssociation, channel:Channel) -> EventLoopFuture<Void> {
        if let message = PDUEncoder.createDIMSEMessage(pduType: .dataTF, commandField: self.commandField, association: association) as? PDUMessage {
            
            message.requestMessage = self.requestMessage
            message.dimseStatus = DIMSEStatus(status: .Success, command: self.commandField)
            
            self.requestMessage = nil
            
            if delegate != nil && association.callingAE != nil {
                let status = delegate!.validateEcho(callingAE: association.callingAE!)
                
                if status != .Success {
                    return channel.eventLoop.makeFailedFuture(NetworkError.callingAETitleNotRecognized)
                }
            }
                        
            let p:EventLoopPromise<Void> = channel.eventLoop.makePromise()
            
            return association.write(message: message, promise: p)
        }
        
        return channel.eventLoop.makeFailedFuture(NetworkError.internalError)
    }
}
