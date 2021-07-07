//
//  DicomClient.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 19/03/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation
import NIO
//import Socket





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
        print("deinit")
        if group != nil {
            try! group.syncShutdownGracefully()
        }
    }
    
    
    
    public func connect(completion: ConnectCompletion) {
        bootstrap  = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
//            .channelInitializer { channel in
//                let assoc = DicomAssociation(channel: channel, callingAET: self.localEntity, calledAET: self.remoteEntity)
//
//                return channel.pipeline.addHandler(assoc)
//            }
        
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
        
//        do {
//            if self.socket == nil {
//                self.socket = try Socket.create()
//            }
//
//
//            try self.socket.setBlocking(mode: true)
//
//            try self.socket.connect(to: self.remoteEntity.hostname, port: Int32(self.remoteEntity.port))
//            self.isConnected = self.socket.isConnected
//
//            completion(self.isConnected, nil)
//        } catch let error {
//            self.isConnected = false
//
//            if let socketError = error as? Socket.Error {
//                completion(self.isConnected, DicomError(socketError: socketError))
//            } else {
//                completion(self.isConnected, DicomError(description:  "Unexpected Socket Error", level: .error, realm: .custom))
//            }
//        }
    }
    
    public func disconnect() -> Bool {
        try! channel.close().wait()
        
        self.isConnected = false
        
        return true
    }
    
    
    
    
    public func echo(completion: PDUCompletion?) {
        if !self.checkConnected(completion) { return }

        let association = DicomAssociation(channel: self.channel, callingAET: self.localEntity, calledAET: self.remoteEntity)

        _ = channel.pipeline.addHandler(association)
        
        association.addPresentationContext(abstractSyntax: DicomConstants.verificationSOP)

        association.request() { (accepted, receivedMessage, error) in
            if accepted {
                if let message = receivedMessage {
                    if let message2 = PDUEncoder.shared.createDIMSEMessage(pduType: PDUType.dataTF, commandField: .C_ECHO_RQ, association: association) as? PDUMessage {
                        association.write(message: message2, readResponse: true, completion: completion)
                    
                        //association.close()
                        

                    }
                }
            }
        }
        
        completion?(false, nil, DicomError(description: "ECHO Error", level: .error, realm: .network))
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
    
    
    
    private func checkConnected(_ completion: PDUCompletion?) -> Bool {
        if !self.isConnected {
            completion?(false, nil, DicomError(description: "Socket is not connected, please connect first.",
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
