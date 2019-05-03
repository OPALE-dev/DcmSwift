//
//  DicomAssociation.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 20/03/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation
import SwiftyBeaver
import Socket


public class DicomAssociation : NSObject {
    private static var lastContextID:UInt8 = 1
    
    public var callingAET:DicomEntity!
    public var calledAET:DicomEntity!
    
    public var maxPDULength:Int = 16384
    public var associationAccepted:Bool = false
    public var sop:String = "1.2.840.10008.1.1"
    
    public var applicationContext:ApplicationContext = ApplicationContext()
    public var presentatinContext:PresentationContext?
    public var userInfo:UserInfo?
    
    public var acceptedTransferSyntax:String?
    public var remoteMaxPDULength:Int = 0
    public var remoteImplementationUID:String?
    public var remoteImplementationVersion:String?
    
    private var socket:Socket!
    public var protocolVersion:Int = 1
    public var contextID:UInt8 = 1
    
    
    
    public init(_ callingAET:DicomEntity, calledAET:DicomEntity, socket:Socket) {
        self.calledAET = calledAET
        self.callingAET = callingAET
        self.socket = socket

        initLogger()
    }
    
    
    public func request(sop:String, completion: (_ accepted:Bool) -> Void) {
        self.sop = sop
        self.contextID = self.getNextContextID()
        self.presentatinContext = PresentationContext(serviceObjectProvider: sop, contextID: self.contextID)
        self.userInfo = UserInfo()
        
        let message = PDUMessage(pduType: .associationRQ, association: self)
        let data = message.associationRQ(association: self)
        
        SwiftyBeaver.info("==================== SEND A-ASSOCIATE-RQ ====================")
        SwiftyBeaver.debug("A-ASSOCIATE-RQ DATA : \(data.toHex().separate(every: 2, with: " "))")
        SwiftyBeaver.info("  -> Application Context Name: \(DicomConstants.applicationContextName)")
        SwiftyBeaver.info("  -> Called Application Entity: \(calledAET.fullname())")
        SwiftyBeaver.info("  -> Calling Application Entity: \(callingAET.fullname())")
        SwiftyBeaver.info("  -> Local Max PDU: \(self.maxPDULength)")
        
        SwiftyBeaver.info("  -> Presentation Contexts:")
        SwiftyBeaver.info("    -> Context ID: \(self.contextID)")
        SwiftyBeaver.info("      -> Abstract Syntax: \(self.sop)")
        SwiftyBeaver.info("      -> Proposed Transfer Syntax(es): \(DicomConstants.transfersSyntaxes)")
        
        SwiftyBeaver.info("  -> User Informations:")
        SwiftyBeaver.info("    -> Local Max PDU: \(self.maxPDULength)")
        
        do {
            try socket.write(from: data)
            
            var readData = Data()
            try _ = socket.read(into: &readData)
            
            self.readAssociationResponse(readData)
            
        } catch {
            completion(false)
        }
        
        return completion(true)
    }
    
    
    public func close() {
        if self.socket.isConnected && self.associationAccepted {
            do {
                // send A-Release-RQ message
                let data = PDUMessage(pduType: .releaseRQ, association: self).releaseRQ()
                
                SwiftyBeaver.info("==================== SEND A-RELEASE-RQ ====================")
                SwiftyBeaver.debug("A-RELEASE-RQ DATA : \(data.toHex().separate(every: 2, with: " "))")
                
                try socket.write(from: data)
                var readData = Data()
                try _ = socket.read(into: &readData)
            } catch let e {
                print(e)
            }
        }
    }
    
    
    public func abort() {
        do {
            // send A-Abort message
            let data = PDUMessage(pduType: .abort, association: self).abortRQ()
            
            SwiftyBeaver.info("==================== SEND A-ABORT ====================")
            SwiftyBeaver.debug("A-ABORT DATA : \(data.toHex().separate(every: 2, with: " "))")
            
            try socket.write(from: data)
            var readData = Data()
            try _ = socket.read(into: &readData)
        } catch let e {
            print(e)
        }
    }
    
    

    public func write(_ data:Data) {
       do {
           try socket.write(from: data)
       } catch let e {
           print(e)
        }
    }
    
    
    
    public func checkTransferSyntax(_ ts:String) -> Bool {
        var okSyntax = false
        
        for ts in DicomConstants.transfersSyntaxes {
            if ts == ts {
                okSyntax = true
                break
            }
        }
        
        return okSyntax
    }

    
    
    private func readAssociationResponse(_ data:Data) {
        if let command:UInt8 = data.first {
            if command == PDUType.associationAC.rawValue {
                guard PDUMessage(
                    data: data,
                    pduType: PDUType.associationAC,
                    association: self) != nil else
                {
                        self.associationAccepted = false
                        self.abort()
                        return
                }
                
                self.associationAccepted = true
            }
            else if command == PDUType.associationRJ.rawValue {
                SwiftyBeaver.error("Association rejected")
            }
        }
    }
    
    
    private func getNextContextID() -> UInt8 {
        if DicomAssociation.lastContextID == 255 {
            DicomAssociation.lastContextID = 1
        } else {
            DicomAssociation.lastContextID += 1
        }
        
        return DicomAssociation.lastContextID
    }
}
