//
//  File.swift
//  
//
//  Created by Rafael Warnault, OPALE on 20/07/2021.
//

import Foundation
import NIO



/**
 SCU and SCP services are derived from `DicomService`
 */
public class DicomService {
    var type:ServiceType
    
    enum ServiceType {
        case ServiceClassUser
        case ServiceClassProvider
    }
    
    
    public init() {
        type = .ServiceClassUser
    }
    
    
    public var commandField:CommandField {
        .NONE
    }
}




public class ServiceClassUser: DicomService {
    public override init() {
        super.init()
        
        type = .ServiceClassUser
    }
    
    
    public var abstractSyntaxes:[String] {
        []
    }
    
    
    public func request(association:DicomAssociation, channel:Channel) -> EventLoopFuture<Void> {
        if let message = PDUEncoder.createDIMSEMessage(
            pduType: .dataTF,
            commandField: self.commandField,
            association: association
        ) as? PDUMessage {
            let p:EventLoopPromise<Void> = channel.eventLoop.makePromise()
            
            return association.write(message: message, promise: p)
        }
        
        return channel.eventLoop.makeSucceededVoidFuture()
    }
    
    public func receive(association:DicomAssociation, dataTF message:DataTF) -> DIMSEStatus.Status {
        return .Success
    }
}




public class ServiceClassProvider: DicomService {
    public var requestMessage:PDUMessage?
    
    public override init() {
        super.init()
        
        type = .ServiceClassProvider
    }
    
    
    public func reply(request: PDUMessage?, association:DicomAssociation, channel:Channel) -> EventLoopFuture<Void> {
        if let message = PDUEncoder.createDIMSEMessage(pduType: .dataTF, commandField: self.commandField, association: association) as? PDUMessage {
            let p:EventLoopPromise<Void> = channel.eventLoop.makePromise()
            return association.write(message: message, promise: p)
        }
        return channel.eventLoop.makeSucceededVoidFuture()
    }
}
