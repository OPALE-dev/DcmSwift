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


public typealias ConnectCompletion = (_ ok:Bool, _ error:DicomError?) -> Void
public typealias PDUCompletion = (_ ok:Bool, _ response:PDUMessage?, _ error:DicomError?) -> Void


public class DicomAssociation : NSObject {
    private static var lastContextID:UInt8 = 1
    
    public var callingAET:DicomEntity!
    public var calledAET:DicomEntity!
    
    public var maxPDULength:Int = 16384
    public var associationAccepted:Bool = false
    public var abstractSyntax:String = "1.2.840.10008.1.1"
    
    public var applicationContext:ApplicationContext = ApplicationContext()
    public var presentatinContexts:[PresentationContext] = []
    public var userInfo:UserInfo?
    
    public var acceptedTransferSyntax:String?
    public var remoteMaxPDULength:Int = 0
    public var remoteImplementationUID:String?
    public var remoteImplementationVersion:String?
    
    private var socket:Socket!
    public var protocolVersion:Int = 1
    public var contextID:UInt8 = 1
    var isPending:Bool = false
    
    
    public init(_ callingAET:DicomEntity, calledAET:DicomEntity, socket:Socket) {
        self.calledAET = calledAET
        self.callingAET = callingAET
        self.socket = socket

        initLogger()
    }
    
    
    public func addPresentationContext(abstractSyntax: String) {
        let pc = PresentationContext(abstractSyntax: abstractSyntax, contextID: self.getNextContextID())
        self.presentatinContexts.append(pc)
    }
    
    
    public func request(completion: PDUCompletion) {
        self.addPresentationContext(abstractSyntax: DicomConstants.verificationSOP)
        
        if let message = PDUEncoder.shared.createAssocMessage(pduType: .associationRQ, association: self) as? PDUMessage {
            SwiftyBeaver.info("==================== SEND A-ASSOCIATE-RQ ====================")
            SwiftyBeaver.debug("A-ASSOCIATE-RQ DATA")
            SwiftyBeaver.info("  -> Application Context Name: \(DicomConstants.applicationContextName)")
            SwiftyBeaver.info("  -> Called Application Entity: \(calledAET.fullname())")
            SwiftyBeaver.info("  -> Calling Application Entity: \(callingAET.fullname())")
            SwiftyBeaver.info("  -> Local Max PDU: \(self.maxPDULength)")
            
            SwiftyBeaver.info("  -> Presentation Contexts:")
            SwiftyBeaver.info("    -> Context ID: \(self.contextID)")
            SwiftyBeaver.info("      -> Abstract Syntax: \(self.abstractSyntax)")
            SwiftyBeaver.info("      -> Proposed Transfer Syntax(es): \(DicomConstants.transfersSyntaxes)")
            
            SwiftyBeaver.info("  -> User Informations:")
            SwiftyBeaver.info("    -> Local Max PDU: \(self.maxPDULength)")
            
            self.write(message: message, readResponse: true, completion: completion)
            
            return
        }
    
        completion(false, nil, nil)
    }
    
    
    public func close() {
        if self.socket.isConnected && self.associationAccepted {
            do {
                // send A-Release-RQ message
                if let message = PDUEncoder.shared.createAssocMessage(pduType: .releaseRQ, association: self) {
                    let data = message.data()
                    
                    SwiftyBeaver.info("==================== SEND A-RELEASE-RQ ====================")
                    SwiftyBeaver.debug("A-RELEASE-RQ DATA : \(data.toHex().separate(every: 2, with: " "))")
                    
                    try socket.write(from: data)
                    var readData = Data()
                    try _ = socket.read(into: &readData)
                }

            } catch let e {
                print(e)
            }
        }
    }
    
    
    public func abort() {
        do {
            // send A-Abort message
            if let message = PDUEncoder.shared.createAssocMessage(pduType: .abort, association: self) {
                let data = message.data()
                
                SwiftyBeaver.info("==================== SEND A-ABORT ====================")
                SwiftyBeaver.debug("A-ABORT DATA : \(data.toHex().separate(every: 2, with: " "))")
                
                try socket.write(from: data)
                var readData = Data()
                try _ = socket.read(into: &readData)
            }
        } catch let e {
            print(e)
        }
    }
    
    
    public func write(message:PDUMessage, readResponse:Bool = false, completion: PDUCompletion) {
        do {
            //_ = try self.socket.isReadableOrWritable(waitForever: true)
            
            let data = message.data()
            try socket.write(from: data)
            
            if let messageData = message.messageData() {
                try socket.write(from: messageData)
            }
            
            if !readResponse {
                completion(true, nil, nil)
                return
            }
            
            let response = self.readResponse(forMessage: message, completion: completion)
            
            completion(true, response, nil)
            
            
        } catch let e {
            print(e)
            completion(false, nil, nil)
        }
    }
    
    
    
    
    public func readResponse(forMessage message:PDUMessage, completion: PDUCompletion) -> PDUMessage? {
        var response:PDUMessage? = nil
        var readData = Data()
        
        isPending = true
        
        do {
            repeat {
                //let (r, _) = try self.socket.isReadableOrWritable()
                // we read only if the buffer is empty
                if readData.count == 0 {
                    let _ = try socket.read(into: &readData)
                }
                
                // Check for PDU data
                if let f = readData.first, PDUType.isSupported(f) {
                    let pduLength = readData.subdata(in: 2..<6).toInt32().bigEndian
                    var dataLength = readData.count
                    
                    // Reassemble data fragments if needed for DATA-TF messages
                    while pduLength > 4 && dataLength < pduLength {
                        // read more if PDU is incomplete
                        let _ = try socket.read(into: &readData)
                        dataLength = readData.count
                    }
                    
                    var messageData = Data()
                    let messageLength = Int(pduLength + 6)
                    
                    // now if we have to much data, we handle this first message
                    if dataLength > pduLength {
                        messageData = readData.subdata(in: 0..<messageLength)
                        // put rest back into buffer
                        readData = readData.subdata(in: messageLength..<dataLength)
                    } else {
                        messageData = readData
                        // clean buffer
                        readData = Data()
                    }
                    
                    // read message and check pending status
                    if let r = message.handleResponse(data: messageData, completion: completion) {
                        response = r
                        
                        if let cFinRQ = message as? CFindRQ {
                            if let cFinRSP = response as? CFindRSP {
                                cFinRSP.queryResults = cFinRQ.queryResults
                            }
                        }
                        
                        if let s = r.dimseStatus {
                            if s.status == DIMSEStatus.Status.Pending {
                                isPending = true
                            }
                            else if s.status == DIMSEStatus.Status.Success {
                                isPending = false
                                break
                            }
                        }
                    }
                }
            } while (isPending == true)
            
        } catch let e {
            print(e)
            completion(false, response, nil)
        }
        
        return response
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

    
    
    private func getNextContextID() -> UInt8 {
        if DicomAssociation.lastContextID == 127 {
            DicomAssociation.lastContextID = 1
        } else {
            DicomAssociation.lastContextID += 1
        }
        
        return DicomAssociation.lastContextID
    }
}
