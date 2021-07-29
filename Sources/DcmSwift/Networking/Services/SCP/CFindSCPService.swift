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
public protocol CFindSCPDelegate {
    func query(level:QueryRetrieveLevel, dataset:DataSet) -> [DataSet]
}


public class CFindSCPService: ServiceClassProvider {
    private var delegate:CFindSCPDelegate?
    private var lastFindRQ:CFindRQ?
    
    public override var commandField:CommandField {
        .C_FIND_RSP
    }
    
    
    public init(_ delegate:CFindSCPDelegate?) {
        super.init()
        
        self.delegate = delegate
    }
    
    
    public override func reply(request: PDUMessage?, association:DicomAssociation, channel:Channel) -> EventLoopFuture<Void> {
        if let cFindRQ = request as? CFindRQ {
            print("receive primitive")
            print(cFindRQ.receivedData)
            
        } else if let dataTF = request as? DataTF {
            if dataTF.receivedData.count > 0 {
                print("receive data")
//                let dis = DicomInputStream(data: dataTF.receivedData)
//
//                dis.vrMethod    = transferSyntax!.vrMethod
//                dis.byteOrder   = transferSyntax!.byteOrder
//
//                if commandField == .C_FIND_RSP {
//                    if let resultDataset = try? dis.readDataset(enforceVR: false) {
//                        studiesDataset = resultDataset
//                    }
//                }
            }
        }
        
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
