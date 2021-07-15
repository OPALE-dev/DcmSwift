//
//  DicomAssociation.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 20/03/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation
import NIO

/**
 Block type used by the `DicomAssociation` class to return response asynchronously
 */
public typealias PDUCompletion = (_ message:PDUMessage?, _ response:PDUMessage, _ assoc:DicomAssociation) -> Void

/**
 Block type used by the `DicomAssociation` class when abort or error are encountered
 */
public typealias AbortCompletion = (_ response:PDUMessage?, _ error:DicomError?) -> Void

/**
 Block type used by the `DicomAssociation` class close the association
 */
public typealias CloseCompletion = (_ association:DicomAssociation?) -> Void



/**
 The `DicomAssociation` class represents an association betwwen two DICOM AEs over the network.
 
 As `DcmSwift` relies on `SwiftNIO` to handle the network, the `DicomAssociation` class
 is the best candidate to implement the `ChannelInboundHandler` protocol.
 */
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
    
    /**
     Association rejection result
     */
    public enum RejectResult: UInt8 {
        case RejectedPermanent = 0x1
        case RejectedTransient = 0x2
    }
    
    /**
     Source of the association rejection
     */
    public enum RejectSource: UInt8 {
        case DICOMULServiceUser                 = 0x1
        case DICOMULServiceProviderACSE         = 0x2
        case DICOMULServiceProviderPresentation = 0x3
    }
    
    /**
     Reasons returned in association rejection
     */
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
    
    
    /**
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
    
    
    /**
     Initialize an Association for a Remote to Local connection, i.e. READ from a remote DICOM entity
     */
    public init(
        calledAET:DicomEntity,
        origin: Origin = .Remote
    ) {
        self.origin     = origin
        self.calledAET  = calledAET
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
    
    
    
    
    
    
    // MARK: -
    /**
     Called to read a new received message on the channel
     */
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
                
        // we received an DIMSE message
        if pt.rawValue == PDUType.dataTF.rawValue {
            if origin == .Local {
                // handle message received from remote
                if let message = currentDIMSEMessage?.handleResponse(data: readData) {
                    handleDIMSE(message: message)
                }
            } else if origin == .Remote {
                // handle message received as remote
                if let message = PDUDecoder.receiveDIMSEMessage(
                    data: readData,
                    pduType: pt,
                    association: self
                ) as? PDUMessage {
                    handleDIMSE(message: message)
                }
            }
        }
        else {
        // we received an association message
            guard let message = PDUDecoder.receiveAssocMessage(
                    data: readData,
                    pduType: pt,
                    association: self
            ) as? PDUMessage else {
                currentAbortCompletion?(nil, DicomError(description: "Cannot decode \(pt) message", level: .error))
                return
            }
            
            if let transferSyntax = self.acceptedPresentationContexts.values.first?.transferSyntaxes.first {
                self.acceptedTransferSyntax = transferSyntax
            }
                
            handleAssociation(message: message)
        }
    }

    
    /**
     Called when the association receives a connection (server-side only)
     */
    public func channelActive(context: ChannelHandlerContext) {
        // setup accepted presentation contexts
        self.addPresentationContext(abstractSyntax: DicomConstants.verificationSOP, result: 0x00)
        self.addPresentationContext(abstractSyntax: DicomConstants.StudyRootQueryRetrieveInformationModelFIND, result: 0x00)

        for sop in DicomConstants.storageSOPClasses {
            self.addPresentationContext(abstractSyntax: sop, result: 0x00)
        }
        
        // Logger.verbose("Server Presentation Contexts: \(self.presentationContexts)");
        
        // set the remote channel
        self.channel = context.channel
        
        // add channel handlers to decode messages for this child association
        _ = self.channel.pipeline.addHandlers([ByteToMessageHandler(PDUMessageDecoder(withAssociation: self)), self])
        
        // store a reference of the connected association
        self.connectedAssociations[ObjectIdentifier(context.channel)] = self
    }
    
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        currentAbortCompletion?(nil, DicomError(description: error.localizedDescription, level: .error))
        
        // As we are not really interested getting notified on success or failure we just pass nil as promise to
        // reduce allocations.
        context.close(promise: nil)
    }
    
    
    
    
    // MARK: -
    /**
     ASSOCIATION RQ -> AC procedure
     */
    public func request(
        pduCompletion:   @escaping PDUCompletion,
        abortCompletion: @escaping AbortCompletion,
        closeCompletion: @escaping CloseCompletion
    ) {
        if let message = PDUEncoder.createAssocMessage(pduType: .associationRQ, association: self) as? PDUMessage {
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

    
    public func reject(withResult result: RejectResult, source: RejectSource, reason: UserReason) {
        // WRIT A-Association-RJ message
        if let message = PDUEncoder.createAssocMessage(pduType: .associationRJ, association: self) as? AssociationRJ {
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
        guard let message = PDUEncoder.createAssocMessage(pduType: .releaseRQ, association: self) else {
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
        guard let message = PDUEncoder.createAssocMessage(pduType: .abort, association: self) else {
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
        if message.commandField != nil {
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
}
    
    


//MARK: - Private
private extension DicomAssociation {
    private func write(message:PDUMessage) {
        guard let data = message.data() else {
            Logger.error("Cannot encode message of type `\(message.pduType!)`")
            return
        }
        
        Logger.info("WRIT \(message.messageName())", "Association")
        
        write(data)
    }
    
    
    private func write(_ data:Data) {
        let buffer = channel.allocator.buffer(bytes: data)
        
        channel.writeAndFlush(buffer, promise: nil)
    }
    
    
    private func handleError(description: String, message: PDUMessage?, closeAssoc: Bool) {
        Logger.error(description)
        
        currentAbortCompletion?(message, DicomError(description: description, level: .error, realm: .custom))
        
        if closeAssoc {
            abort()
        }
    }
    
    
    private func associationRQ(associationRQ:AssociationRQ) {
        // check for called AE title
        if associationRQ.remoteCallingAETitle == nil || self.calledAET.title != associationRQ.remoteCalledAETitle {
            Logger.error("Called AE title not recognized")

            // WRIT ASSOCIATION-RJ
            self.reject(withResult: .RejectedPermanent,
                        source: .DICOMULServiceUser,
                        reason: DicomAssociation.UserReason.CalledAETitleNotRecognized)
        }

        // create calling AE
        if let hostname = channel.remoteAddress?.description,
           let remoteCallingAETitle = associationRQ.remoteCallingAETitle,
           let port = channel.remoteAddress?.port
        {
            self.callingAET = DicomEntity(
                title: remoteCallingAETitle,
                hostname: hostname,
                port: port)
        }

        guard let response = associationRQ.handleRequest() else {
            // Reject ??
            Logger.error("Cannot handle request of type `\(associationRQ.pduType!)`")
            return
        }
        
        write(message: response)
    }
    
    
    private func releaseRQ(releaseRQ:ReleaseRQ) {
        guard let response = releaseRQ.handleRequest() else {
            // Reject ??
            Logger.error("Cannot handle request of type `\(releaseRQ.pduType!)`")
            return
        }
        
        write(message: response)
    }
    
    
    private func handleAssociation(message:PDUMessage) {
        Logger.info("READ \(message.messageName())", "Association")
                    
        // messages received as remote
        if origin == .Remote {
            // handle requests
            if let aRQ = message as? AssociationRQ {
                associationRQ(associationRQ: aRQ)
            }
            else if let rRQ = message as? ReleaseRQ {
                releaseRQ(releaseRQ: rRQ)
            }
        }
        // messages received as client
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
        
        if origin == .Remote {
            // generate and send request
            if let response = message.handleRequest() {
                write(message: response)
            }
        }
        else if origin == .Local {
            if  message.dimseStatus.status != .Success &&
                message.dimseStatus.status != .Pending {
                currentDIMSEMessage     = nil
                
                currentPDUCompletion    = nil
                currentAbortCompletion  = nil
                currentCloseCompletion  = nil
                
                handleError(description: "Wrong DIMSE status: \(message.dimseStatus.status)", message: message, closeAssoc: true)
                return
            }
            
            currentPDUCompletion?(currentDIMSEMessage, message, self)
            
            if message.dimseStatus.status != .Pending {
                close()
            }
            
            if message.dimseStatus.status == .Success {
                // no more response to handle
                currentDIMSEMessage = nil
                currentPDUCompletion = nil
                currentAbortCompletion = nil
                currentCloseCompletion = nil
            }
        }
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
