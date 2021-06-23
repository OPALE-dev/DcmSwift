//
//  DicomAssociation.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 20/03/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

import Socket


public typealias ConnectCompletion = (_ ok:Bool, _ error:DicomError?) -> Void
public typealias PDUCompletion = (_ ok:Bool, _ response:PDUMessage?, _ error:DicomError?) -> Void


public class DicomAssociation : NSObject {
    public enum Origin {
        case Local
        case Remote
    }
    
    // http://dicom.nema.org/medical/dicom/2017e/output/chtml/part08/sect_9.3.4.html
    // http://dicom.nema.org/medical/dicom/2014c/output/chtml/part02/sect_F.4.2.2.4.html#table_F.4.2-14
    //
    // rejection result
    public enum RejectResult: UInt8 {
        case RejectedPermanent = 0x1
        case RejectedTransient = 0x2
    }
    
    // source of the rejection
    public enum RejectSource: UInt8 {
        case DICOMULServiceUser                 = 0x1
        case DICOMULServiceProviderACSE         = 0x2
        case DICOMULServiceProviderPresentation = 0x3
    }
    
    // Reasons
    
    public enum UserReason: UInt8 {
        case NoReasonGiven                      = 0x1
        case ApplicationContextNameNotSupported = 0x2
        case CallingAETitleNotRecognized        = 0x3
        case Reserved4                          = 0x4
        case Reserved5                          = 0x5
        case Reserved6                          = 0x6
        case CalledAETitleNotRecognized         = 0x7
        case Reserved8                          = 0x8
        case Reserved9                          = 0x9
        case Reserved10                         = 0xf
    }
    
    public enum ACSEReason: UInt8 {
        case NoReasonGiven                      = 0x1
        case ProtocolVersionNotSupported        = 0x2
    }
    
    public enum PresentationReason: UInt8 {
        case Reserved1                          = 0x1
        case TemporaryCongestion                = 0x2
        case LocalLimitExceeded                 = 0x3
        case Reserved4                          = 0x4
        case Reserved5                          = 0x5
        case Reserved6                          = 0x6
        case Reserved7                          = 0x7
        case Reserved8                          = 0x8
    }
    
    
//    enum Either<A,B> {
//        case Left(A)
//        case Right(B)
//    }

    
    private static var lastContextID:UInt8 = 1
    
    public var callingAET:DicomEntity?
    public var calledAET:DicomEntity!
    
    public var maxPDULength:Int = DicomConstants.maxPDULength
    public var associationAccepted:Bool = false
    public var abstractSyntax:String = "1.2.840.10008.1.1"
    
    public var applicationContext:ApplicationContext = ApplicationContext()
    public var remoteApplicationContext:ApplicationContext?
    
    public var presentationContexts:[UInt8 : PresentationContext] = [:]
    public var acceptedPresentationContexts:[UInt8 : PresentationContext] = [:]
    public var userInfo:UserInfo = UserInfo()
    
    public var acceptedTransferSyntax:String?
    public var remoteMaxPDULength:Int = 0
    public var remoteImplementationUID:String?
    public var remoteImplementationVersion:String?
    
    private var socket:Socket!
    public var protocolVersion:Int = 1
    public var contextID:UInt8 = 1
    var isPending:Bool = false
    
    
    /*
     Initialize an Association for a Local to Remote connection, i.e. send to a remote DICOM entity
     */
    public init(socket:Socket, callingAET:DicomEntity, calledAET:DicomEntity, origin: Origin = .Local) {
        self.calledAET  = calledAET
        self.callingAET = callingAET
        self.socket     = socket
    }
    
    
    /*
     Initialize an Association for a Remote to Local connection, i.e. received from a remote DICOM entity
     */
    public init(socket:Socket, calledAET:DicomEntity, origin: Origin = .Remote) {
        self.calledAET  = calledAET
        self.socket     = socket
    }
    
    
    public func addPresentationContext(abstractSyntax: String, result:UInt8? = nil) {
        let ctID = self.getNextContextID()
        let pc = PresentationContext(abstractSyntax: abstractSyntax, contextID: ctID, result: result)
        self.presentationContexts[ctID] = pc
    }
    
    
    public func request(completion: @escaping PDUCompletion) {
        if let message = PDUEncoder.shared.createAssocMessage(pduType: .associationRQ, association: self) as? PDUMessage {
            message.debugDescription = "\n  -> Application Context Name: \(DicomConstants.applicationContextName)\n"
            message.debugDescription.append("  -> Called Application Entity: \(calledAET.fullname())\n")
            if let caet = callingAET {
                message.debugDescription.append("  -> Calling Application Entity: \(caet.fullname())\n")
            }
            message.debugDescription.append("  -> Local Max PDU: \(self.maxPDULength)\n")
            message.debugDescription.append("  -> Presentation Contexts:\n")
            for (_, pc) in self.presentationContexts {
                message.debugDescription.append("    -> Context ID: \(pc.contextID ?? 0xff)\n")
                message.debugDescription.append("      -> Abstract Syntax: \(pc.abstractSyntax ?? "Unset?")\n")
                message.debugDescription.append("      -> Proposed Transfer Syntax(es): \(pc.transferSyntaxes)\n")
            }
            message.debugDescription.append("  -> User Informations:\n")
            message.debugDescription.append("    -> Local Max PDU: \(self.maxPDULength)\n")
            
            self.write(message: message, readResponse: true, completion: completion)
            
            return
        }
    
        completion(false, nil, nil)
    }
    
    
    public func acknowledge() -> Bool {
        // read ASSOCIATION-RQ
        if let associationRQ = self.readMessage() as? AssociationRQ {
            // check AETs are properly defined
            if associationRQ.remoteCallingAETitle == nil || self.calledAET.title != associationRQ.remoteCalledAETitle {
                Logger.error("Called AE title not recognized")
                
                // send ASSOCIATION-RJ
                self.reject(withResult: .RejectedPermanent,
                            source: .DICOMULServiceUser,
                            reason: DicomAssociation.UserReason.CalledAETitleNotRecognized.rawValue)
                
                return false
            }
            
            // Build calling AET Dicom Entity
            self.callingAET = DicomEntity(title: associationRQ.remoteCallingAETitle!, hostname: self.socket!.remoteHostname, port: Int(self.socket!.remotePort))
            
            // check presentation contexts ?
            
            // send ASSOCIATION-AC
            if let associationAC = PDUEncoder.shared.createAssocMessage(pduType: .associationAC, association: self) as? AssociationAC {
                self.write(message: associationAC, readResponse: false, completion: nil)
            }
            
            self.associationAccepted = true
            
            return true
        }
        
        return false
    }
    
    
    
    public func listen(withCompletion completion:((_ socket:Socket) -> Void)?) {
        //var listen = true
        var message = self.readMessage()

        while message != nil {
            if let response = message?.handleRequest() {
                self.write(message: response)
            }
            
            message = self.readMessage()
            
//            if !listen {
//                break
//            }
        }
        
        Logger.debug("Association ended")
        completion?(self.socket)
    }
    
    
    
    public func reject(withResult result: RejectResult, source: RejectSource, reason: UInt8) {
        if self.socket.isConnected {
            do {
                // send A-Association-RJ message
                if let message = PDUEncoder.shared.createAssocMessage(pduType: .associationRJ, association: self) as? AssociationRJ {
                    message.result = result
                    message.source = source
                    message.reason = reason
                    
                    let data = message.data()
                    
                    Logger.info("SEND A-ASSOCIATION-RJ")
                    
                    try socket.write(from: data)
                }
                
            } catch let e {
                print(e)
            }
        }
    }
    
    
    public func close() {
        if self.socket.isConnected && self.associationAccepted {
            do {
                // send A-Release-RQ message
                if let message = PDUEncoder.shared.createAssocMessage(pduType: .releaseRQ, association: self) {
                    let data = message.data()
                    
                    Logger.info("SEND A-RELEASE-RQ", "Association")
                    
                    try socket.write(from: data)
                    
                    self.socket.close()
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
                
                Logger.info("SEND A-ABORT", "Association")
                
                try socket.write(from: data)
            }
        } catch let e {
            print(e)
        }
    }
    
    
    public func write(message:PDUMessage, readResponse:Bool = false, completion: PDUCompletion? = nil) {
        do {
            let data = message.data()
            try socket.write(from: data)
            
            Logger.info("SEND \(message.messageName() )")
            Logger.debug(message.debugDescription)
            
            for messageData in message.messagesData() {
                Logger.info("SEND \(message.messageName())-DATA")
                if messageData.count > 0 {
                    try socket.write(from: messageData)
                }
            }
            
            if !readResponse {
                completion?(true, nil, nil)
                return
            }
            
            let response = self.readResponse(forMessage: message, completion: completion)
            
            Logger.info("RECEIVE \(response?.messageName() ?? "UNKNOW-DIMSE")")
            Logger.debug(message.debugDescription)
            
            // Special case: Only one « Unsupported Abstract Syntaxes (Result: 0x3) » in returned accepted presentation contexts
            if self.acceptedPresentationContexts.count == 1 {
                for (_,v) in self.acceptedPresentationContexts {
                    if v.result == 0x3 {
                        completion?(false, response, DicomError(description: "Unsupported Abstract Syntaxes",
                                                                      level: .error,
                                                                      realm: .custom))
                        self.close()
                    }
                }
            }
            
            completion?(true, response, nil)
        } catch let e {
            print(e)
            completion?(false, nil, nil)
        }
    }
    
    
    
    private func readMessage() -> PDUMessage? {
        var message:PDUMessage? = nil
        var readData = Data()
        
        do {
            let bytesRead = try socket.read(into: &readData)
            
            if bytesRead > 0 {
                if let f = readData.first, PDUType.isSupported(f) {
                    if let pt = PDUType(rawValue: f) {
                        if PDUType(rawValue: f) == PDUType.dataTF {
                            let commandData = readData.subdata(in: 12..<readData.count)
                            if commandData.count > 0 {
                                let inputStream = DicomInputStream(data: commandData)
                                
                                if let dataset = try? inputStream.readDataset() {
                                    if let command = dataset.element(forTagName: "CommandField") {
                                        let c = command.data.toUInt16(byteOrder: .LittleEndian)
                                        if let cf = CommandField(rawValue: c) {
                                            message = PDUDecoder.shared.receiveDIMSEMessage(data: readData, pduType: pt, commandField: cf, association: self) as? PDUMessage
                                        }
                                    }
                                }
                            }
                        } else {
                            message = PDUDecoder.shared.receiveAssocMessage(data: readData, pduType: pt, association: self) as? PDUMessage
                        }
                    }
                }
            }
        }
        catch let error {
            print(error)
        }
        
        return message
    }
    
    
    private func readResponse(forMessage message:PDUMessage, completion: PDUCompletion?) -> PDUMessage? {
        var response:PDUMessage? = nil
        var readData = Data()
        
        isPending = true
        
        do {
            repeat {
                //let (r, _) = try self.socket.isReadableOrWritable(waitForever: false, timeout: DicomConstants.dicomTimeOut)
                // we read only if the buffer is empty
                if readData.count == 0 {
                    let readSize = try socket.read(into: &readData)
                    
                    if readSize == 0 {
                        isPending = false
                        break
                    }
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
                    if let r = message.handleResponse(data: messageData) {
                        response = r
                        
                        if response?.pduType == PDUType.associationAC {
                            return response
                        }
                        
                        // get results from last RSP message
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
                    } else {
                        isPending = false
                    }
                }
            } while (isPending == true)
            
        } catch let e {
            print(e)
            return nil
        }
        
        return response
    }
    
    
    
    public func acceptedPresentationContexts(forSOPClassUID sopClassUID:String) -> [PresentationContext] {
        var pcs:[PresentationContext] = []
        
        for (_,pc) in self.presentationContexts {
            if pc.result != 0x3 { // Unsupported abtract syntax
                if pc.abstractSyntax == sopClassUID {
                    if let _ = self.acceptedPresentationContexts[pc.contextID] {
                        pcs.append(pc)
                    }
                }
            }
        }
        
        return pcs
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
