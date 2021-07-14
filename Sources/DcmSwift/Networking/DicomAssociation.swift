//
//  DicomAssociation.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 20/03/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation
import NIO


public typealias PDUCompletion = (_ message:PDUMessage?, _ response:PDUMessage, _ assoc:DicomAssociation) -> Void
public typealias AbortCompletion = (_ response:PDUMessage?, _ error:DicomError?) -> Void
public typealias CloseCompletion = (_ association:DicomAssociation?) -> Void


public class DicomAssociation : ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    
    public enum Origin {
        case Local
        case Remote
    }
    
    // http://dicom.nema.org/medical/dicom/2017e/output/chtml/part08/sect_9.3.4.html
    // http://dicom.nema.org/medical/dicom/2014c/output/chtml/part02/sect_F.4.2.2.4.html#table_F.4.2-14
    //
    // TODO: State Machine http://dicom.nema.org/dicom/2013/output/chtml/part08/sect_9.2.html#sect_9.2.3
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
    
    private var channel:Channel!
    private var connectedAssociations = [ObjectIdentifier: DicomAssociation]()
    private var currentDIMSEMessage:PDUMessage?
    private var currentPDUCompletion:PDUCompletion!
    private var currentAbortCompletion:AbortCompletion!
    private var currentCloseCompletion:CloseCompletion!
    private var origin:Origin
    
    public var protocolVersion:Int = 1
    public var contextID:UInt8 = 1
    
    var isPending:Bool = false
    
    
    /*
     Initialize an Association for a Local to Remote connection, i.e. WRIT to a remote DICOM entity
     */
    public init(
        channel:Channel,
        callingAET:DicomEntity,
        calledAET:DicomEntity,
        origin: Origin = .Local
    ) {
        self.calledAET  = calledAET
        self.callingAET = callingAET
        self.channel    = channel
        self.origin     = origin
 
        _ = channel.pipeline.addHandlers([ByteToMessageHandler(PDUMessageDecoder(withAssociation: self)), self])
    }
    
    
    /*
     Initialize an Association for a Remote to Local connection, i.e. received from a remote DICOM entity
     */
    public init(
        calledAET:DicomEntity,
        origin: Origin = .Remote
    ) {
        self.origin     = origin
        self.calledAET  = calledAET

        _ = channel.pipeline.addHandlers([ByteToMessageHandler(PDUMessageDecoder(withAssociation: self)), self])
    }
    
    
    
    deinit {
        // Logger.verbose("deinit association")
    }
    
    
    
    // MARK: -
    
    public func addPresentationContext(abstractSyntax: String, result:UInt8? = nil) {
        let ctID = self.getNextContextID()
        
        let pc = PresentationContext(
            abstractSyntax: abstractSyntax,
            transferSyntaxes: [TransferSyntax.explicitVRLittleEndian],
            contextID: ctID,
            result: result)
        
        self.presentationContexts[ctID] = pc
    }
    
    
    
    
    
    //MARK: -
    private func handleError(description: String, message: PDUMessage?, closeAssoc: Bool) {
        Logger.error(description)
        
        currentAbortCompletion?(message, DicomError(description: description, level: .error, realm: .custom))
        
        if closeAssoc {
            abort()
        }
    }

    
    
    
    private func handleAssociation(message:PDUMessage) {
        Logger.info("READ \(message.messageName())", "Association")
                    
        if origin == .Remote {
            // read AA-RQ
            if let associationRQ = message as? AssociationRQ {
                if associationRQ.remoteCallingAETitle == nil || self.calledAET.title != associationRQ.remoteCalledAETitle {
                    Logger.error("Called AE title not recognized")
                    
                    // WRIT ASSOCIATION-RJ
                    self.reject(withResult: .RejectedPermanent,
                                source: .DICOMULServiceUser,
                                reason: DicomAssociation.UserReason.CalledAETitleNotRecognized)
                }
                
                if let hostname = channel.remoteAddress?.description,
                   let remoteCallingAETitle = associationRQ.remoteCallingAETitle,
                   let port = channel.remoteAddress?.port
                {
                    self.callingAET = DicomEntity(
                        title: remoteCallingAETitle,
                        hostname: hostname,
                        port: port)
                }
                
                if let associationAC = PDUEncoder.shared.createAssocMessage(pduType: .associationAC, association: self) as? AssociationAC {
                    self.write(message: associationAC) { (message, response, self) in
                        
                    } abortCompletion: { (message, err) in
                        
                    } closeCompletion: { (assoc) in
                        
                    }
                }
            }
        }
        else if origin == .Local {
            if message.pduType == .abort {
                handleError(description: "Association aborted", message: message, closeAssoc: false)
                currentDIMSEMessage = nil
                return
            }
            
            currentPDUCompletion?(currentDIMSEMessage, message, self)
        }
    }
    
    private func handleDIMSE(message:PDUMessage) {
        Logger.info("READ \(message.messageName())", "Association")
        
        if  message.dimseStatus.status != .Success &&
            message.dimseStatus.status != .Pending {
            currentDIMSEMessage = nil
            handleError(description: "Wrong DIMSE status: \(message.dimseStatus.status)", message: message, closeAssoc: true)
            return
        }
        
        if origin == .Remote {
            
        }
        else if origin == .Local {
            currentPDUCompletion?(currentDIMSEMessage, message, self)
            
            // TODO: make sure it is always the case
            if message.dimseStatus.status != .Pending {
                close()
            }
        }
        
        if message.dimseStatus.status == .Success {
            // no more response to handle
            currentDIMSEMessage = nil
        }
    }
    
    
    
    
    // MARK: -
    public func channelActive(context: ChannelHandlerContext) {
        // setup accepted presentation contexts
        self.addPresentationContext(abstractSyntax: DicomConstants.verificationSOP, result: 0x00)
        self.addPresentationContext(abstractSyntax: DicomConstants.StudyRootQueryRetrieveInformationModelFIND, result: 0x00)

        for sop in DicomConstants.storageSOPClasses {
            self.addPresentationContext(abstractSyntax: sop, result: 0x00)
        }
        
        Logger.verbose("Server Presentation Contexts: \(self.presentationContexts)");
        
        self.channel = context.channel
        self.connectedAssociations[ObjectIdentifier(context.channel)] = self
    }
    
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer          = self.unwrapInboundIn(data)
        let messageLength   = buffer.readableBytes
        
        guard let bytes = buffer.readBytes(length: messageLength) else {
            handleError(description: "Cannot read bytes", message: nil, closeAssoc: true)
            return
        }
        
        let readData = Data(bytes)
        
        guard let f = readData.first, PDUType.isSupported(f) else {
            handleError(description: "Unsupported PDU Type (channelRead)", message: nil, closeAssoc: true)
            return
        }
        
        guard let pt = PDUType(rawValue: f) else {
            handleError(description: "Cannot read PDU Type", message: nil, closeAssoc: true)
            return
        }
                
        if pt.rawValue == PDUType.dataTF.rawValue {
            guard let message = currentDIMSEMessage?.handleResponse(data: readData) else {
                handleError(description: "Cannot read DIMSE message of type \(pt)", message: nil, closeAssoc: true)
                return
            }
                            
            handleDIMSE(message: message)
        }
        else {
            // we received an association message
            guard let message = PDUDecoder.shared.receiveAssocMessage(data: readData, pduType: pt, association: self) as? PDUMessage else {
                currentAbortCompletion?(nil, DicomError(description: "Cannot decode \(pt) message", level: .error))
                return
            }
            
            if let transferSyntax = self.acceptedPresentationContexts.values.first?.transferSyntaxes.first {
                self.acceptedTransferSyntax = transferSyntax
            }
                
            handleAssociation(message: message)
        }
    }

    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        currentAbortCompletion?(nil, DicomError(description: error.localizedDescription, level: .error))
        
        // As we are not really interested getting notified on success or failure we just pass nil as promise to
        // reduce allocations.
        context.close(promise: nil)
    }
    
    
    
    
    // MARK: -
    /*
     ASSOCIATION RQ -> AC procedure
     */
    public func request(
        pduCompletion:   @escaping PDUCompletion,
        abortCompletion: @escaping AbortCompletion,
        closeCompletion: @escaping CloseCompletion
    ) {
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
            
            self.write(message: message, readResponse: true, pduCompletion: pduCompletion, abortCompletion: abortCompletion, closeCompletion: closeCompletion)
            
            return
        }
        
        abortCompletion(nil, DicomError(description: "Cannot create AssociationRQ message", level: .error))
    }
    
    
    public func acknowledge() -> Bool {
//        // read ASSOCIATION-RQ
//        if let associationRQ = self.readMessage() as? AssociationRQ {
//            // check AETs are properly defined
//            if associationRQ.remoteCallingAETitle == nil || self.calledAET.title != associationRQ.remoteCalledAETitle {
//                Logger.error("Called AE title not recognized")
//
//                // WRIT ASSOCIATION-RJ
//                self.reject(withResult: .RejectedPermanent,
//                            source: .DICOMULServiceUser,
//                            reason: DicomAssociation.UserReason.CalledAETitleNotRecognized.rawValue)
//
//                return false
//            }
//
//            // Build calling AET Dicom Entity
//            self.callingAET = DicomEntity(title: associationRQ.remoteCallingAETitle!, hostname: channel!.remoteAddress!.description, port: channel!.remoteAddress!.port!)
//
//            // check presentation contexts ?
//
//            // WRIT ASSOCIATION-AC
//            if let associationAC = PDUEncoder.shared.createAssocMessage(pduType: .associationAC, association: self) as? AssociationAC {
//                self.write(message: associationAC, readResponse: false, completion: nil)
//            }
//
//            self.associationAccepted = true
//
//            return true
//        }

        return false
    }
    
    

    
    
    public func reject(withResult result: RejectResult, source: RejectSource, reason: UserReason) {
        // WRIT A-Association-RJ message
        if let message = PDUEncoder.shared.createAssocMessage(pduType: .associationRJ, association: self) as? AssociationRJ {
            message.result = result
            message.source = source
            message.reason = reason
            
            let data = message.data()
            
            Logger.info("WRIT A-ASSOCIATION-RJ", "Association")
            
            self.write(data)
        }

    }
    
    
    
    public func close() {
        if !self.associationAccepted {
            return
        }
            
        // WRIT A-Release-RQ message
        guard let message = PDUEncoder.shared.createAssocMessage(pduType: .releaseRQ, association: self) else {
            Logger.error("Cannot create A-RELEASE-RQ message")
            return
        }
        
        guard let data = message.data() else {
            Logger.error("Cannot generate A-RELEASE-RQ message", "Association")
            return
        }
        
        Logger.info("WRIT A-RELEASE-RQ", "Association")
        
        self.write(data)
        
        channel.close(mode: .all, promise: nil)
        
        currentCloseCompletion?(self)
            
    }
    
    
    
    public func abort() {
        // create A-Abort message
        guard let message = PDUEncoder.shared.createAssocMessage(pduType: .abort, association: self) else {
            Logger.error("Cannot create A-ABORT message")
            return
        }
        
        // get message data
        guard let data = message.data() else {
            Logger.error("Cannot generate A-ABORT message")
            return
        }
        
        Logger.info("WRIT A-ABORT", "Association")
            
        // write message
        self.write(data)
    }
    
    
    
    private func write(_ data:Data) {
        let buffer = channel.allocator.buffer(bytes: data)
        
        channel.writeAndFlush(buffer, promise: nil)
    }
    
    
    
    public func write(
        message:PDUMessage,
        readResponse:Bool = false,
        pduCompletion: @escaping PDUCompletion,
        abortCompletion: @escaping AbortCompletion,
        closeCompletion: @escaping CloseCompletion)
    {
        guard let data = message.data() else {
            Logger.error("WRITE ERROR: no data to write")
            return
        }
                
        if readResponse {
            currentPDUCompletion    = pduCompletion
            currentAbortCompletion  = abortCompletion
            currentCloseCompletion  = closeCompletion
        }
        
        // handle response later
        if let cf = message.commandField {
            currentDIMSEMessage = message
        }
        
        self.write(data)
                
        Logger.info("WRIT \(message.messageName() )", "Association")
        //Logger.debug(message.debugDescription)
                
        for messageData in message.messagesData() {
            Logger.info("WRIT \(message.messageName())-DATA", "Association")
            if messageData.count > 0 {
                self.write(messageData)
            }
        }
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
        
        for ts in TransferSyntax.transfersSyntaxes {
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
