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
                
                let message = PDUMessage(pduType: PDUType.dataTF, association: association)
                let data = message.echoRQ(association: association)
                
                print(data.toHex().separate(every: 2, with: " "))
                
                association.write(data)
                
                // read response
                
                // close association
                
                completion(accepted, nil)
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

                association.close()
            }
            else {
                completion(false, "Association failed")
                association.close()
            }
        }
    }
    
    
    public func find(_ queryDataset:DataSet, completion: (_ accepted:Bool, _ error:String?) -> Void)  {
        if !self.isConnected {
            completion(false, "Socket is not connected, please connect() first.")
        }
        
        let association = DicomAssociation(self.localEntity, calledAET: self.remoteEntity, socket: self.socket)
        
        association.request(sop: "1.2.840.10008.5.1.4.1.2.2.1") { (accepted) in
            if accepted {
                print("accepted")
                
                let cFindRQMessage = PDUMessage(pduType: PDUType.dataTF, association: association)
                let data = cFindRQMessage.cfindRQ(queryDataset: queryDataset)
                
                print(data.toHex().separate(every: 2, with: " "))
                
                association.write(data)
            }
            else {
                completion(false, "Association failed")
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
    
    
    

    

    private func write(data:Data) -> Int{
        return 0
    }
}
