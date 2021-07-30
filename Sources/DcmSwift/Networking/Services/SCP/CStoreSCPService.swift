//
//  File.swift
//
//
//  Created by Rafael Warnault on 28/07/2021.
//

import Foundation
import NIO



/**
 This service delegate provides a way to implement specific behaviors in the end-program
 */
public protocol CStoreSCPDelegate {
    func store(fileMetaInfo:DataSet, dataset: DataSet, tempFile:String) -> Bool
}


public class CStoreSCPService: ServiceClassProvider {
    private var delegate:CStoreSCPDelegate?
    
    
    public override var commandField:CommandField {
        .C_STORE_RSP
    }
    
    
    public init(_ delegate:CStoreSCPDelegate?) {
        super.init()
        
        self.delegate = delegate
    }
    
    
    public override func reply(request: PDUMessage?, association:DicomAssociation, channel:Channel) -> EventLoopFuture<Void> {
        print("request \(request)")
        
//        if let message = PDUEncoder.createDIMSEMessage(pduType: .dataTF, commandField: self.commandField, association: association) as? PDUMessage {
//
//            message.requestMessage = self.requestMessage
//            message.dimseStatus = DIMSEStatus(status: .Success, command: self.commandField)
//
//            self.requestMessage = nil
//
//            if delegate != nil && association.callingAE != nil {
//                let status = delegate!.validateEcho(callingAE: association.callingAE!)
//
//                if status != .Success {
//                    return channel.eventLoop.makeFailedFuture(NetworkError.callingAETitleNotRecognized)
//                }
//            }
//
//            let p:EventLoopPromise<Void> = channel.eventLoop.makePromise()
//
//            return association.write(message: message, promise: p)
//        }
        
        return channel.eventLoop.makeFailedFuture(NetworkError.internalError)
    }
}
