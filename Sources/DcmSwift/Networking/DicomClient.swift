//
//  DicomClient.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 19/03/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation
import Socket

public class DicomClient : DicomService, StreamDelegate {
    public var localEntity:DicomEntity
    public var remoteEntity:DicomEntity
    
    private var socket:Socket!
    private var isConnected:Bool = false
    
    
    public init(localEntity: DicomEntity, remoteEntity: DicomEntity) {
        self.localEntity = localEntity
        self.remoteEntity = remoteEntity
        super.init(localAET: localEntity.title)
    }
    

    
    
    
    public func connect(completion: ConnectCompletion) {
        do {
            if self.socket == nil {
                self.socket = try Socket.create()
            }
            
        
            try self.socket.setBlocking(mode: true)
            
            try self.socket.connect(to: self.remoteEntity.hostname, port: Int32(self.remoteEntity.port))
            self.isConnected = self.socket.isConnected
            
            completion(self.isConnected, nil)
        } catch let error {
            self.isConnected = false
            
            if let socketError = error as? Socket.Error {
                completion(self.isConnected, DicomError(socketError: socketError))
            } else {
                completion(self.isConnected, DicomError(description:  "Unexpected Socket Error", level: .error, realm: .custom))
            }
        }
    }
    
    public func disconnect() -> Bool {
        self.socket.close()
        self.isConnected = self.socket.isConnected
        
        return true
    }
    
    
    
    
    public func echo(completion: PDUCompletion?) {
        if !self.checkConnected(completion) { return }
        
        let association = DicomAssociation(socket: self.socket, callingAET: self.localEntity, calledAET: self.remoteEntity)
        
        association.addPresentationContext(abstractSyntax: DicomConstants.verificationSOP)
        
        association.request() { (accepted, receivedMessage, error) in
            if accepted {
                if let message = PDUEncoder.shared.createDIMSEMessage(pduType: PDUType.dataTF, commandField: .C_ECHO_RQ, association: association) as? PDUMessage {
                    association.write(message: message, readResponse: true, completion: completion)
                    
                    association.close()
                }
            }
            else {
                completion?(false, receivedMessage, error)
                association.close()
            }
        }
    }
    
    
    public func find(_ queryDataset:DataSet, completion: PDUCompletion?)  {
        if !self.checkConnected(completion) { return }
        
        // create assoc between local and remote
        let association = DicomAssociation(socket: self.socket, callingAET: self.localEntity, calledAET: self.remoteEntity)
        
        // add C-FIND Study Root Query Level
        association.addPresentationContext(abstractSyntax: DicomConstants.StudyRootQueryRetrieveInformationModelFIND)
        
        // request assoc
        association.request() { (accepted, receivedMessage, error) in
            if accepted {
                // create C-FIND-RQ message
                if let message = PDUEncoder.shared.createDIMSEMessage(pduType: PDUType.dataTF, commandField: .C_FIND_RQ, association: association) as? CFindRQ {
                    // add query dataset to the message
                    message.queryDataset = queryDataset
                    // send message
                    association.write(message: message, readResponse: true, completion: completion)
                    //
                    association.close()
                }
            }
            else {
                completion?(false, receivedMessage, error)
                association.close()
            }
        }
    }
    
    
    
    public func store(_ files:[String], progression: @escaping (_ index:Int) -> Void, completion: PDUCompletion?)  {
        if !self.checkConnected(completion) { return }
        
        let association = DicomAssociation(socket: self.socket, callingAET: self.localEntity, calledAET: self.remoteEntity)
        
        // Add all know SOP classes
        for abstractSyntax in DicomConstants.storageSOPClasses {
            association.addPresentationContext(abstractSyntax: abstractSyntax)
        }
        
        association.request() { (accepted, receivedMessage, error) in
            if accepted {
                var index = 0
                for f in files {
                    if let message = PDUEncoder.shared.createDIMSEMessage(pduType: PDUType.dataTF, commandField: .C_STORE_RQ, association: association) as? CStoreRQ {
                        message.dicomFile = DicomFile(forPath: f)
                        
                        association.write(message: message, readResponse: true, completion: completion)
                        
                        progression(index)
                        index += 1
                    }
                }
                
                association.close()
            }
            else {
                completion?(false, receivedMessage, error)
                association.close()
            }
        }
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
