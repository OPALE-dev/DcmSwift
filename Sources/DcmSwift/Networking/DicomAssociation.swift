//
//  DicomAssociation.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 20/03/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation
import NIO


public typealias ConnectCompletion = (_ ok:Bool, _ error:DicomError?) -> Void
//public typealias PDUCompletion = (_ ok:Bool, _ response:PDUMessage?, _ error:DicomError?) -> Void

public typealias PDUCompletion = (_ response:PDUMessage) -> Void
public typealias ErrorCompletion = (_ error:DicomError?) -> Void
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
    
    private var channel:Channel!
    private var currentPDUCompletion:PDUCompletion!
    private var currentErrorCompletion:ErrorCompletion!
    private var currentCloseCompletion:CloseCompletion!
    
    public var protocolVersion:Int = 1
    public var contextID:UInt8 = 1
    
    var isPending:Bool = false
    
    
    /*
     Initialize an Association for a Local to Remote connection, i.e. send to a remote DICOM entity
     */
    public init(channel:Channel, callingAET:DicomEntity, calledAET:DicomEntity, origin: Origin = .Local) {
        self.calledAET  = calledAET
        self.callingAET = callingAET
        self.channel    = channel
        
        _ = channel.pipeline.addHandler(self)
    }
    
    
    /*
     Initialize an Association for a Remote to Local connection, i.e. received from a remote DICOM entity
     */
    public init(channel:Channel, calledAET:DicomEntity, origin: Origin = .Remote) {
        self.calledAET  = calledAET
        self.channel    = channel
        
        _ = channel.pipeline.addHandler(self)
    }
    
    
    
    deinit {
        print("DicomAssociation deinit")
    }
    
    
    // MARK: -
    
    public func addPresentationContext(abstractSyntax: String, result:UInt8? = nil) {
        let ctID = self.getNextContextID()
        let pc = PresentationContext(abstractSyntax: abstractSyntax, contextID: ctID, result: result)
        self.presentationContexts[ctID] = pc
    }
    
    
    
    
    
    //MARK: -
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer          = self.unwrapInboundIn(data)
        let messageLength   = buffer.readableBytes
        
        guard let bytes = buffer.readBytes(length: messageLength) else {
            currentErrorCompletion?(DicomError(description: "Cannot read bytes", level: .error))
            return
        }
        
        let readData = Data(bytes)
        
        guard let f = readData.first, PDUType.isSupported(f) else {
            currentErrorCompletion?(DicomError(description: "Unsupported PDU Type", level: .error))
            return
        }
        
        guard let pt = PDUType(rawValue: f) else {
            currentErrorCompletion?(DicomError(description: "Cannot read PDU Type", level: .error))
            return
        }
        
        if PDUType(rawValue: f) == PDUType.dataTF {
            // we received a command message (PDUMessage as DataTF and inherited)
            let commandData = readData.subdata(in: 12..<readData.count)
            
            if commandData.count == 0 {
                currentErrorCompletion?(DicomError(description: "Cannot read PDU command", level: .error))
                return
            }
            
            let inputStream = DicomInputStream(data: commandData)
                                        
            do {
                guard let dataset = try inputStream.readDataset() else {
                    currentErrorCompletion?(DicomError(description: "Cannot read command Dataset", level: .error))
                    return
                }
                                
                guard let command = dataset.element(forTagName: "CommandField") else {
                    currentErrorCompletion?(DicomError(description: "Cannot read CommandField in command Dataset", level: .error))
                    return
                }
                
                // we create a response (PDUMessage of DIMSE family) based on received CommandField value using PDUDecoder
                let c = command.data.toUInt16(byteOrder: .LittleEndian)
                
                guard let cf = CommandField(rawValue: c) else {
                    currentErrorCompletion?(DicomError(description: "Cannot read CommandField in command Dataset", level: .error))
                    return
                }
                
                guard let message = PDUDecoder.shared.receiveDIMSEMessage(data: readData, pduType: pt, commandField: cf, association: self) as? PDUMessage else {
                    currentErrorCompletion?(DicomError(description: "Cannot read DIMSE message of type \(pt)", level: .error))
                    return
                }
                
                currentPDUCompletion?(message)
            } catch let e {
                print(e)
                currentErrorCompletion?(DicomError(description: e.localizedDescription, level: .error))
            }
        }
        else {
            // we received an association message
            guard let message = PDUDecoder.shared.receiveAssocMessage(data: readData, pduType: pt, association: self) as? PDUMessage else {
                currentErrorCompletion?(DicomError(description: "Cannot decode \(pt) message", level: .error))
                return
            }
            
            if let transferSyntax = self.acceptedPresentationContexts.values.first?.transferSyntaxes.first {
                self.acceptedTransferSyntax = transferSyntax
            }
            
            currentPDUCompletion?(message)
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: ", error)
        // TODO: implement something here
        // As we are not really interested getting notified on success or failure we just pass nil as promise to
        // reduce allocations.
        context.close(promise: nil)
    }
    
    
    
    // MARK: -
    /*
     ASSOCIATION RQ -> AC procedure
     */
    public func request(pduCompletion: @escaping PDUCompletion, errorCompletion: @escaping ErrorCompletion, closeCompletion: @escaping CloseCompletion) {
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
            
            self.write(message: message, readResponse: true, pduCompletion: pduCompletion, errorCompletion: errorCompletion, closeCompletion: closeCompletion)
            
            return
        }
        
        errorCompletion(DicomError(description: "Cannot create AssociationRQ message", level: .error))
    }
    
    
    public func acknowledge() -> Bool {
//        // read ASSOCIATION-RQ
//        if let associationRQ = self.readMessage() as? AssociationRQ {
//            // check AETs are properly defined
//            if associationRQ.remoteCallingAETitle == nil || self.calledAET.title != associationRQ.remoteCalledAETitle {
//                Logger.error("Called AE title not recognized")
//
//                // send ASSOCIATION-RJ
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
//            // send ASSOCIATION-AC
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
    
    
    
    public func listen(withCompletion completion:((_ channel:Channel) -> Void)?) {
//        //var listen = true
//        //var message = self.readMessage()
//
//        while let message = self.readMessage() {
//            if let response = message.handleRequest() {
//                self.write(message: response)
//            }
//        }
//
//        Logger.debug("Association ended")
//        completion?(self.socket)
    }
    
    
    
    public func reject(withResult result: RejectResult, source: RejectSource, reason: UInt8) {
        // send A-Association-RJ message
        if let message = PDUEncoder.shared.createAssocMessage(pduType: .associationRJ, association: self) as? AssociationRJ {
            message.result = result
            message.source = source
            message.reason = reason
            
            let data = message.data()
            
            Logger.info("SEND A-ASSOCIATION-RJ")
            
            self.write(data)
            //try socket.write(from: data)
        }

    }
    
    
    
    public func close() {
        if self.associationAccepted {
            // send A-Release-RQ message
            if let message = PDUEncoder.shared.createAssocMessage(pduType: .releaseRQ, association: self) {
                let data = message.data()
                
                Logger.info("SEND A-RELEASE-RQ", "Association")
                
                self.write(data)
                
                channel.close(mode: .all, promise: nil)
            }
        }
    }
    
    
    
    public func abort() {
        // send A-Abort message
        if let message = PDUEncoder.shared.createAssocMessage(pduType: .abort, association: self) {
            let data = message.data()
            
            Logger.info("SEND A-ABORT", "Association")
            
            self.write(data)
        }
    }
    
    
    
    private func write(_ data:Data) {
        let buffer = channel.allocator.buffer(bytes: data)
        
        channel.writeAndFlush(buffer, promise: nil)
    }
    
    
    
    public func write(
        message:PDUMessage,
        readResponse:Bool = false,
        pduCompletion: @escaping PDUCompletion,
        errorCompletion: @escaping ErrorCompletion,
        closeCompletion: @escaping CloseCompletion)
    {
        let data = message.data()
                
        if readResponse {
            currentPDUCompletion    = pduCompletion
            currentErrorCompletion  = errorCompletion
            currentCloseCompletion  = closeCompletion
        }
        
        self.write(data)
                
        Logger.info("SEND \(message.messageName() )")
        Logger.debug(message.debugDescription)
        
        for messageData in message.messagesData() {
            Logger.info("SEND \(message.messageName())-DATA")
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
