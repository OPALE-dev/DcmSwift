//
//  DicomClient.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 19/03/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
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
    

    
    
    
    public func connect(completion: (_ ok:Bool, _ error:String?) -> Void) {
        if self.socket == nil {
            self.socket = try! Socket.create()
        }
        
        do {
            try self.socket.connect(to: self.remoteEntity.hostname, port: Int32(self.remoteEntity.port))
            self.isConnected = self.socket.isConnected
            
            completion(self.isConnected, nil)
        } catch let error {
            self.isConnected = false
            
            if let socketError = error as? Socket.Error {
                completion(self.isConnected, socketError.description)
            } else {
                completion(self.isConnected, "Unexpected socket error")
            }
        }
    }
    
    public func disconnect() -> Bool {
        self.socket.close()
        self.isConnected = self.socket.isConnected
        
        return true
    }
    
    
    
    
    
    public func echo(completion: (_ accepted:Bool, _ error:String?) -> Void) {
        if !self.isConnected {
            completion(false, "Socket is not connected, please connect() first.")
        }
        
        let association = DicomAssociation(self.localEntity, calledAET: self.remoteEntity, socket: self.socket)
        
        association.request(sop: DicomConstants.verificationSOP) { (accepted) in
            if accepted {
                completion(accepted, nil)
                association.close()
            }
            else {
                completion(false, "Association failed")
                association.close()
            }
        }
    }
    
    
    public func store(_ files:Array<DicomFile>, completion: (_ accepted:Bool, _ error:String?) -> Void)  {
        if !self.isConnected {
            completion(false, "Socket is not connected, please connect() first.")
        }
        
        let association = DicomAssociation(self.localEntity, calledAET: self.remoteEntity, socket: self.socket)
        
        association.request(sop: DicomConstants.ultrasoundImageStorageSOP) { (accepted) in
            if accepted {
                for file in files {
                    // send C-STORE-RQ
                    let v = file.dataset.string(forTag: "MediaStorageSOPInstanceUID")
                    
                    let dataset = DataSet()
                    _ = dataset.set(value: DicomConstants.ultrasoundImageStorageSOP, forTagName: "AffectedSOPClassUID")
                    _ = dataset.set(value: "C-STORE-RQ", forTagName: "CommandField")
                    _ = dataset.set(value: "1", forTagName: "MessageID")
                    _ = dataset.set(value: "2", forTagName: "Priority")
                    _ = dataset.set(value: "2", forTagName: "CommandDataSetType")
                    _ = dataset.set(value: v as Any, forTagName: "AffectedSOPInstanceUID")
                    
                    let length = dataset.toData().count
                    _ = dataset.set(value: length, forTagName: "CommandGroupLength")
                    
                    print(dataset)
                    
                    //association.write(file.dataset.toData())
                }
                association.close()
            }
            else {
                completion(false, "Association failed")
                association.close()
            }
        }
    }
    
    
    public func find() -> Bool  {
        return false
    }
    
    
    public func get() -> Bool  {
        return false
    }
    
    
    

    

    private func write(data:Data) -> Int{
        return 0
    }
}
