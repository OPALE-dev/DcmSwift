//
//  DicomClient.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 19/03/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation
import NIO




public class DicomClient : DicomService, StreamDelegate {
    public var localEntity:DicomEntity
    public var remoteEntity:DicomEntity
    
    //private var socket:Socket!
    private var isConnected:Bool = false
    
    private let group:MultiThreadedEventLoopGroup!
    private var bootstrap:ClientBootstrap!
    private var channel:Channel!
    
    public init(localEntity: DicomEntity, remoteEntity: DicomEntity) {
        self.localEntity    = localEntity
        self.remoteEntity   = remoteEntity
        
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        super.init(localAET: localEntity.title)
    }
    

    deinit {
        if group != nil {
            try! group.syncShutdownGracefully()
        }
    }
    
    
    
    public func connect(completion: ConnectCompletion) {
        bootstrap  = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        
        do {
            channel = try bootstrap.connect(host: self.remoteEntity.hostname, port: self.remoteEntity.port).wait()
            
            self.isConnected = true
            
            completion(self.isConnected, nil)
            
            try channel.closeFuture.wait()
            
            return
        } catch {
            self.isConnected = false
        }
        
        completion(self.isConnected, DicomError(description:  "Cannot connect", level: .error, realm: .custom))
    }
    
    public func disconnect() -> Bool {
        try! channel.close().wait()
        
        self.isConnected = false
        
        return true
    }
    
    
    
    
    public func echo(pduCompletion: @escaping PDUCompletion, errorCompletion: @escaping ErrorCompletion, closeCompletion: @escaping CloseCompletion) {
        if !self.checkConnected(errorCompletion) { return }

        let association = DicomAssociation(channel: self.channel, callingAET: self.localEntity, calledAET: self.remoteEntity)
        
        association.addPresentationContext(abstractSyntax: DicomConstants.verificationSOP)
        
        association.request { (message) in
            if let response = PDUEncoder.shared.createDIMSEMessage(pduType: PDUType.dataTF, commandField: .C_ECHO_RQ, association: association) as? PDUMessage {
                association.write(
                    message: response,
                    readResponse: true,
                    pduCompletion: pduCompletion,
                    errorCompletion: errorCompletion,
                    closeCompletion: closeCompletion)
            }
        } errorCompletion: { (error) in
            errorCompletion(error)
            
            return
        } closeCompletion: { (association) in
            closeCompletion(association)
            
            association?.close()
        }
    }
    
    
    public func find(_ queryDataset:DataSet, completion: PDUCompletion?)  {
//        if !self.checkConnected(completion) { return }
//
//        // create assoc between local and remote
//        let association = DicomAssociation(socket: self.socket, callingAET: self.localEntity, calledAET: self.remoteEntity)
//
//        // add C-FIND Study Root Query Level
//        //association.addPresentationContext(abstractSyntax: DicomConstants.StudyRootQueryRetrieveInformationModelFIND)
//        // Add all know storage SOP classes (maybe not the best approach on client side?)
//        for abstractSyntax in DicomConstants.storageSOPClasses {
//            association.addPresentationContext(abstractSyntax: abstractSyntax)
//        }
//
//        // request assoc
//        association.request() { (accepted, receivedMessage, error) in
//            if accepted {
//                // create C-FIND-RQ message
//                if let message = PDUEncoder.shared.createDIMSEMessage(pduType: PDUType.dataTF, commandField: .C_FIND_RQ, association: association) as? CFindRQ {
//                    // add query dataset to the message
//                    message.queryDataset = queryDataset
//                    // send message
//                    association.write(message: message, readResponse: true, completion: completion)
//                    //
//                    association.close()
//                }
//            }
//            else {
//                completion?(false, receivedMessage, error)
//                association.close()
//            }
//        }
    }
    
    
    
    public func store(_ files:[String], progression: @escaping (_ index:Int) -> Void, completion: PDUCompletion?)  {
//        if !self.checkConnected(completion) { return }
//
//        let association = DicomAssociation(socket: self.socket, callingAET: self.localEntity, calledAET: self.remoteEntity)
//
//        // Add all know storage SOP classes (maybe not the best approach on client side?)
//        for abstractSyntax in DicomConstants.storageSOPClasses {
//            association.addPresentationContext(abstractSyntax: abstractSyntax)
//        }
//
//        // request assoc
//        association.request() { (accepted, receivedMessage, error) in
//            if accepted {
//                var index = 0
//                for f in files {
//                    if let message = PDUEncoder.shared.createDIMSEMessage(pduType: PDUType.dataTF, commandField: .C_STORE_RQ, association: association) as? CStoreRQ {
//                        message.dicomFile = DicomFile(forPath: f)
//
//                        association.write(message: message, readResponse: false, completion: completion)
//
//                        progression(index)
//                        index += 1
//                    }
//                }
//
//                association.close()
//            }
//            else {
//                completion?(false, receivedMessage, error)
//                association.close()
//            }
//        }
    }
    
    
    
    
    public func move() -> Bool  {
        return false
    }
    
    
    public func get() -> Bool  {
        return false
    }
    
    
    
    private func checkConnected(_ errorCompletion: ErrorCompletion) -> Bool {
        if !self.isConnected {
            errorCompletion(DicomError(description: "Socket is not connected, please connect first.",
                                               level: .error,
                                               realm: .custom))
            return false
        }
        return self.isConnected
    }
    

    private func write(data:Data) -> Int{
        return 0
    }
}
