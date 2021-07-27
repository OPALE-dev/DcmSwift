//
//  File.swift
//  
//
//  Created by Rafael Warnault on 20/07/2021.
//

import Foundation
import NIO


/**
 Association between 2 DICOM peers

 This class implements a finite state machine provided by the DICOM specification. The same
 class is used by both requestor and acceptor peers to communicate.
 
 The class relies on SCU and SCP services objects (`DicomService` and inherited) to run
 several DIMSE-C services like C-ECHO, C-STORE, etc.
 
 As we rely on `SwiftNIO` for networking, the `DicomAssociaton` class is also the `ChannelInboundHandler`
 used by the `SwiftNIO` channel to read and decode received messages.
 
 Example of a C-STORE-SCU ready assocation:
 
        // create a new association on NIO event loop
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let assoc = DicomAssociation(group: eventLoopGroup, callingAE: callingAE, calledAE: calledAE)

        // set a C-ECHO-SCU service up
        assoc.setServiceClassUser(CEchoSCUService())
 
 * DICOM P.07 S.D.3: http://dicom.nema.org/dicom/2013/output/chtml/part07/sect_D.3.html
 * DICOM P.08 S.9.3: http://dicom.nema.org/dicom/2013/output/chtml/part08/sect_9.2.html
 
 */
public class DicomAssociation: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
        
    
    
    public enum Origin {
        case Requestor
        case Acceptor
    }
    
    
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
    
    
    
    private enum PDUState: Equatable {
        case Sta1
        case Sta2
        case Sta3
        case Sta4
        case Sta5
        case Sta6
        case Sta7
        case Sta8
        case Sta13
    }
    
    
    public enum PDUAction {
        case AE1
        case AE2
        case AE3(_ message:AssociationAC)
        case AE4
        case AE5
        case AE6(_ message:AssociationRQ)
        case AE7
        case AE8
        
        case DT1
        case DT2(_ message:DataTF)
        
        case AR1
        case AR2(_ message:ReleaseRQ)
        case AR3(_ message:ReleaseRSP)
        case AR4
        case AR5
        case AR6
        case AR7
        case AR8
        case AR9
        case AR10
        
        case AA1
        case AA2
        case AA3
        case AA4
        case AA5
        case AA6
        case AA7
        case AA8
    }
 
    
    private static var lastContextID:UInt8 = 1
    
    public var dicomTimeout:Int = DicomConstants.dicomTimeOut
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

    public var protocolVersion:Int = 1
    public var contextID:UInt8 = 1
    
    var calledAE:DicomEntity!
    var callingAE:DicomEntity?
    
    public let group: MultiThreadedEventLoopGroup
    public var promise: EventLoopPromise<DIMSEStatus.Status>?
    public var dimseStatus:DIMSEStatus.Status?
    
    public var serviceClassUsers:ServiceClassUser?
    public var serviceClassProviders:[CommandField:ServiceClassProvider] = [:]
    
    private var channel: Channel?
    private var connectedAssociations = [ObjectIdentifier: DicomAssociation]()
    
    private var artimTimer:Timer?
    internal var origin:Origin
    private var _state = PDUState.Sta1
    private let lock = NSLock()
    private var state: PDUState {
        get {
            return self.lock.withLock {
                _state
            }
        }
        set {
            self.lock.withLock {
                _state = newValue
                //Logger.notice("\(self) \(_state)")
            }
        }
    }
    
    
    
    
    /**
     Constructor for Associations created by users
        -> Origin is `Requestor`
     */
    public init(group: MultiThreadedEventLoopGroup, callingAE:DicomEntity, calledAE:DicomEntity) {
        self.group      = group
        self.calledAE   = calledAE
        self.callingAE  = callingAE
        self.origin     = .Requestor
    }
    
    /**
     Constructor for Associations created by providers
        -> Origin is `Acceptor`
     */
    public init(group: MultiThreadedEventLoopGroup, calledAE:DicomEntity) {
        self.group      = group
        self.calledAE   = calledAE
        self.origin     = .Acceptor
    }
    
    
    deinit {
        stopARTIM()
    }
    
    
    
    
    // MARK: -
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = self.unwrapInboundIn(data)
        let bytes = buffer.readBytes(length: buffer.readableBytes)
        let pduData = Data(bytes!)
        
        // print("channelRead")
        
        switch state {
        case .Sta2:
            if let message = PDUDecoder.receiveAssocMessage(
                data: pduData,
                pduType: .associationRQ,
                association: self
            ) as? AssociationRQ {
                // get the first accepted TS in accepted presentation contexts
                if let transferSyntax = self.acceptedPresentationContexts.values.first?.transferSyntaxes.first {
                    self.acceptedTransferSyntax = transferSyntax
                }
                
                log(message: message, write: false)
                
                _ = try? handle(event: .AE6(message))
            }
        case .Sta5:
            if let message = PDUDecoder.receiveAssocMessage(
                data: pduData,
                pduType: .associationAC,
                association: self
            ) as? AssociationAC {
                // get the first accepted TS in accepted presentation contexts
                if let transferSyntax = self.acceptedPresentationContexts.values.first?.transferSyntaxes.first {
                    self.acceptedTransferSyntax = transferSyntax
                }
                
                log(message: message, write: false)
                
                _ = try? handle(event: .AE3(message))
                
            }
            else if let message = PDUDecoder.receiveAssocMessage(
                        data: pduData,
                        pduType: .associationRJ,
                        association: self
            ) as? AssociationRJ {
                log(message: message, write: false)
                                
                promise?.fail(NetworkError.associationRejected(reason: "\(message.reason)"))
                
                // _ = try? handle(event: .AR3(message))
            }
        case .Sta6:
            if origin == .Requestor {
                switch self.serviceClassUsers {
                case is CEchoSCUService:
                    if let message = PDUDecoder.receiveDIMSEMessage(
                        data: pduData,
                        pduType: .dataTF,
                        association: self
                    ) as? CEchoRSP {
                        log(message: message, write: false)
                        
                        _ = try? handle(event: .DT2(message))
                    }
                case is CFindSCUService:
                    if let message = PDUDecoder.receiveDIMSEMessage(
                        data: pduData,
                        pduType: .dataTF,
                        association: self
                    ) as? CFindRSP {
                        log(message: message, write: false)
                        
                        _ = try? handle(event: .DT2(message))
                    }
                    // message can also be a single DATA-TF fragment
                    else if let message = PDUDecoder.receiveDIMSEMessage(
                        data: pduData,
                        pduType: .dataTF,
                        association: self
                    ) as? DataTF {
                        log(message: message, write: false)
                                            
                        _ = try? handle(event: .DT2(message))
                    }
                case is CStoreSCUService:
                    if let message = PDUDecoder.receiveDIMSEMessage(
                        data: pduData,
                        pduType: .dataTF,
                        association: self
                    ) as? CStoreRSP {
                        log(message: message, write: false)
                        
                        _ = try? handle(event: .DT2(message))
                    }
                default:
                    break
                }
            }
            else if origin == .Acceptor {
                if let message = PDUDecoder.receiveDIMSEMessage(
                    data: pduData,
                    pduType: .dataTF,
                    association: self
                ) as? DataTF {
                    log(message: message, write: false)
                    
                    if let commandField = message.commandField,
                       let service = serviceClassProviders[commandField.inverse] {
                        service.requestMessage = message
                    
                        _ = try? handle(event: .DT2(message))
                    }
                }
                else if let message = PDUDecoder.receiveAssocMessage(
                    data: pduData,
                    pduType: .releaseRQ,
                    association: self
                ) as? ReleaseRQ {
                    log(message: message, write: false)
                    
                    _ = try? handle(event: .AR2(message))
                }
            }
        case .Sta7:
            if let message = PDUDecoder.receiveAssocMessage(
                data: pduData,
                pduType: .releaseRP,
                association: self
            ) as? ReleaseRSP {
                log(message: message, write: false)
                
                _ = try? handle(event: .AR3(message))
                
            }
        default:
            break
        }
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        if origin == .Requestor {
            _ = try? handle(event: .AE2)
        }
        else if origin == .Acceptor {
            self.addPresentationContext(abstractSyntax: DicomConstants.verificationSOP, result: 0x00)
            self.addPresentationContext(abstractSyntax: DicomConstants.StudyRootQueryRetrieveInformationModelFIND, result: 0x00)

            for sop in DicomConstants.storageSOPClasses {
                self.addPresentationContext(abstractSyntax: sop, result: 0x00)
            }
            
            // Logger.verbose("Server Presentation Contexts: \(self.presentationContexts)");
            
            // set the remote channel
            self.channel = context.channel
            
            // add channel handlers to decode messages for this child association
            _ = self.channel?.pipeline.addHandlers([ByteToMessageHandler(PDUBytesDecoder(withAssociation: self)), self])
            
            // store a reference of the connected association
            self.connectedAssociations[ObjectIdentifier(context.channel)] = self

    
            _ = try? handle(event: .AE5)
        }
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        self.connectedAssociations[ObjectIdentifier(context.channel)] = self
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error \(error)")
    }
    
    
    
    // MARK: -
    /**
     Set a service class user to the Association
     The service will be used as a requestor.
     */
    public func setServiceClassUser(_ service:ServiceClassUser) {
        self.serviceClassUsers = service
        
        for ast in service.abstractSyntaxes {
            self.addPresentationContext(abstractSyntax: ast)
        }
    }
    
    /**
     Add a service class provider to the Association.
     SCP association can handle multiple service class providers.
     The service will be used as a acceptor.
     */
    public func addServiceClassProvider(_ service:ServiceClassProvider) {
        self.serviceClassProviders[service.commandField] = service
    }
    
    
    
    
    // MARK: -
    /**
    State Machine transitions
     */
    private func transition(forEvent event: PDUAction) throws -> EventLoopFuture<Void> {
        Logger.verbose("FSM  [STATE] (\(state)) \(event)", "Association")
        
        switch (state, event) {
        case (.Sta1, .AE1):                 return AE1()
        case (.Sta1, .AE5):                 return AE5()
        case (.Sta2, .AE6(let message)):    return AE6(message)
        case (.Sta3, .AE7):                 return AE7()
        case (.Sta4, .AE2):                 return AE2()
        case (.Sta5, .AE3):                 return AE3()
        case (.Sta6, .DT1):                 return DT1()
        case (.Sta6, .DT2(let message)):    return DT2(message)
        case (.Sta6, .AR1):                 return AR1()
        case (.Sta6, .AR2(let message)):    return AR2(message)
        case (.Sta7, .AR3(let message)):    return AR3(message)
        default: throw NetworkError.transitionNotFound
        }
    }
    
    
    /**
    State Machine handler
     */
    public func handle(event: PDUAction) throws -> EventLoopFuture<Void> {
        return try transition(forEvent: event)
    }
    
    
    
    // MARK: -
    /**
    State Machine actions
     */
    private func AE1() -> EventLoopFuture<Void> {
        let bootstrap = ClientBootstrap(group: self.group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.maxMessagesPerRead, value: 10)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([
                    ByteToMessageHandler(PDUBytesDecoder(withAssociation: self)),
                    self
                ])
            }

        self.state = .Sta4
    
        return bootstrap.connect(host: self.calledAE.hostname, port: self.calledAE.port).flatMap { channel in
            self.channel = channel
            //self.state = .connected
            
            self.promise = self.channel?.eventLoop.makePromise(of: DIMSEStatus.Status.self)
            
            return channel.eventLoop.makeSucceededVoidFuture()
        }
    }
    
    
    private func AE2() -> EventLoopFuture<Void> {
        self.state = .Sta5
        
        guard let associationRQ = PDUEncoder.createAssocMessage(pduType: .associationRQ, association: self) as? AssociationRQ else {
            return channel!.eventLoop.makeFailedFuture(NetworkError.internalError)
        }
        
        associationRQ.remoteCalledAETitle   = self.calledAE.title
        
        if let callingAE = self.callingAE {
            associationRQ.remoteCallingAETitle  = callingAE.title
        }
        
        let p:EventLoopPromise<Void> = channel!.eventLoop.makePromise()
        
        return write(message: associationRQ, promise: p)
    }
    
    
    private func AE3() -> EventLoopFuture<Void> {
        self.state = .Sta6
        
        if origin == .Requestor {
            _ = try? handle(event: .DT1)
        }

        return channel!.eventLoop.makeSucceededVoidFuture()
    }
    
    
    
    private func AE5() -> EventLoopFuture<Void> {
        self.state = .Sta2
        
        startARTIM()
        
        return channel!.eventLoop.makeSucceededVoidFuture()
    }
    
    
    
    private func AE6(_ message:AssociationRQ) -> EventLoopFuture<Void> {
        stopARTIM()
        
        // check for called AE title
        if message.remoteCallingAETitle == nil || self.calledAE.title != message.remoteCalledAETitle {
            Logger.error("Called AE title not recognized")

            let reason = DicomAssociation.UserReason.CalledAETitleNotRecognized
            
            // WRIT ASSOCIATION-RJ
            let f = reject(withResult: .RejectedPermanent,
                   source: .DICOMULServiceUser,
                   reason: reason)
            
            startARTIM()
            
            self.state = .Sta13
            
            return f
        }

        self.state = .Sta3
        
        self.callingAE = DicomEntity(
            title: message.remoteCallingAETitle ?? "UNKNOW-AE",
            hostname: channel!.remoteAddress?.ipAddress ?? "0.0.0.0",
            port: channel!.remoteAddress?.port ?? 11112)
        
        _ = try? handle(event: .AE7)
        
        return channel!.eventLoop.makeSucceededVoidFuture()
    }
    
    
    private func AE7() -> EventLoopFuture<Void> {
        guard let associationAC = PDUEncoder.createAssocMessage(pduType: .associationAC, association: self) as? AssociationAC else {
            return channel!.eventLoop.makeFailedFuture(NetworkError.internalError)
        }
        
        let p:EventLoopPromise<Void> = channel!.eventLoop.makePromise()
    
        self.state = .Sta6
        
        return self.write(message: associationAC, promise: p)
    }
    
    
    
    private func DT1() -> EventLoopFuture<Void> {
        self.state = .Sta6
        
        if origin == .Requestor {
            if let service = self.serviceClassUsers {
                // rely on service
                return service.run(association: self, channel: self.channel!)
            }
        }

        return channel!.eventLoop.makeSucceededVoidFuture()
    }
    
    
    private func DT2(_ message:DataTF) -> EventLoopFuture<Void> {
        self.state = .Sta6
        
        if origin == .Requestor {
            if let service = self.serviceClassUsers {
                switch service {
                case is CEchoSCUService:
                    if message is CEchoRSP {
                        dimseStatus = message.dimseStatus.status
                        
                        if message.dimseStatus.status == .Success {
                            _ = try? handle(event: .AR1)
                            
                            return channel!.eventLoop.makeSucceededVoidFuture()
                        }
                        else {
                            
                        }
                    }
                    
                case is CFindSCUService:
                    if let s = service as? CFindSCUService {
                        if let m = message as? CFindRSP {
                            // C-FIND-RSP message (with or without DATA fragment)
                            dimseStatus = message.dimseStatus.status
                            
                            s.receiveRSP(m)
                            
                            if message.dimseStatus.status == .Success {
                                _ = try? handle(event: .AR1)
                                
                                return channel!.eventLoop.makeSucceededVoidFuture()
                            }
                        }
                        else {
                            // single DATA-TF fragment
                            if let ats = acceptedTransferSyntax,
                               let transferSyntax = TransferSyntax(ats) {
                                s.receiveData(message, transferSyntax: transferSyntax)
                            }
                        }
                    }
                    
                case is CStoreSCUService:
                    if service is CStoreSCUService {
                        if message.dimseStatus != nil {
                            dimseStatus = message.dimseStatus.status
                            
                            if message.dimseStatus.status == .Success {
                                _ = try? handle(event: .AR1)
                                
                                return channel!.eventLoop.makeSucceededVoidFuture()
                            }
                        } else {
                            if let command = message.commandDataset {
                                Logger.debug(command.description)
                                
                                if let status = command.integer16(forTag: "Status"), status > 0 {
                                    if let errorComment = command.string(forTag: "ErrorComment") {
                                        let error = NetworkError.errorComment(message: errorComment)
                                        
                                        Logger.error(error.localizedDescription, "Association")
                                        
                                        //promise!.fail(error)
                                        
                                        return channel!.eventLoop.makeFailedFuture(error)
                                    }
                                }
                            }
                        }
                    }
                default:
                    break
                }
            }
        }
        else if origin == .Acceptor {
            if let commandField = message.commandField,
               let service = serviceClassProviders[commandField.inverse] {
                
                //let future = service.run(association: self, channel: channel!)
                
                //_ = try? handle(event: .AR2)
                
                return service.run(association: self, channel: channel!)
            }
        }

        return channel!.eventLoop.makeFailedFuture(NetworkError.internalError)
    }
    
    
    private func AR1() -> EventLoopFuture<Void> {
        self.state = .Sta7
        
        guard let releaseRQ = PDUEncoder.createAssocMessage(pduType: .releaseRQ, association: self) as? PDUMessage else {
            return channel!.eventLoop.makeFailedFuture(NetworkError.internalError)
        }
                    
        let p:EventLoopPromise<Void> = channel!.eventLoop.makePromise()
        
        return write(message: releaseRQ, promise: p)
    }
    
    
    private func AR2(_ message:ReleaseRQ) -> EventLoopFuture<Void> {
        self.state = .Sta8

        guard let releaseRSP = PDUEncoder.createAssocMessage(pduType: .releaseRP, association: self) as? ReleaseRSP else {
            return channel!.eventLoop.makeFailedFuture(NetworkError.internalError)
        }

        let p:EventLoopPromise<Void> = channel!.eventLoop.makePromise()

        return write(message: releaseRSP, promise: p)
//        return channel!.eventLoop.makeSucceededVoidFuture()
    }
    
    
    private func AR3(_ message:ReleaseRSP, error:Error? = nil) -> EventLoopFuture<Void> {
        self.state = .Sta1
                
        // release the global promise with DIMSE status
        if let s = self.dimseStatus {
            if s == .Success {
                promise?.succeed(s)
            } else {
                if let e = error {
                    promise?.fail(e)
                    
                    return channel!.eventLoop.makeFailedFuture(e)
                }
            }
        }
        
        return channel!.eventLoop.makeSucceededVoidFuture()
    }

    

    
    // MARK: -
    public func disconnect() -> EventLoopFuture<Void> {
        if .Sta5 != self.state {
            return self.group.next().makeFailedFuture(NetworkError.notReady)
        }
        
        guard let channel = self.channel else {
            return self.group.next().makeFailedFuture(NetworkError.notReady)
        }
        
        self.state = .Sta13
        
        channel.closeFuture.whenComplete { _ in
            self.state = .Sta1
        }
        
        channel.close(promise: nil)
        
        return channel.closeFuture
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
    


    
    
    // MARK: -
    internal func write(message:PDUMessage, promise: EventLoopPromise<Void>) -> EventLoopFuture<Void> {
        log(message: message, write: true)
        
        guard var data = message.data() else {
            Logger.error("Cannot encode message of type `\(message.pduType!)`")
            return channel!.eventLoop.makeFailedFuture(NetworkError.internalError)
        }
        
        for d in message.messagesData() {
            data.append(d)
        }
                
        return write(data, promise: promise)
    }
    
    
    private func write(_ data:Data, promise: EventLoopPromise<Void>) -> EventLoopFuture<Void> {
        let buffer = channel!.allocator.buffer(bytes: data)
        
        channel!.writeAndFlush(buffer, promise: promise)
        
        return promise.futureResult
    }

    
    private func getNextContextID() -> UInt8 {
        if DicomAssociation.lastContextID == 127 {
            DicomAssociation.lastContextID = 1
        } else {
            DicomAssociation.lastContextID += 1
        }
        
        return DicomAssociation.lastContextID
    }
    
    
    private func log(message:PDUMessage, write:Bool) {
        let infos   = message.messageInfos()
        var prefix  = ""
        
        if write {
            prefix = "WRIT"
        } else {
            prefix = "READ"
        }
        
        let from = message.pduType == .dataTF ? "DIMSE" : "ASSOC"
        let info = infos.count > 0 ? "[\(infos)]" : ""
        
        Logger.info("\(prefix) [\(from)] (\(state)) \(message.messageName()) \(info)", "Association")
    }
    
    
    
    private func restartARTIM() {
        stopARTIM()
        startARTIM()
    }
    
    
    private func startARTIM() {
        if #available(OSX 10.12, *) {
            artimTimer = Timer.scheduledTimer(
                withTimeInterval: TimeInterval(dicomTimeout),
                repeats: false
            ) { timer in
                Logger.error("ARTIM [Timed Out] \(self.dicomTimeout) sec.", "Association")
            }
        }
    }
    
    
    private func stopARTIM() {
        artimTimer?.invalidate()
        artimTimer = nil
    }
    
    
    private func reject(withResult result: RejectResult, source: RejectSource, reason: UserReason) -> EventLoopFuture<Void> {
        // WRIT A-Association-RJ message
        if let message = PDUEncoder.createAssocMessage(pduType: .associationRJ, association: self) as? AssociationRJ {
            message.result = result
            message.source = source
            message.reason = reason
            
            let p:EventLoopPromise<Void> = channel!.eventLoop.makePromise()
            
            return self.write(message: message, promise: p)
        }
        
        return channel!.eventLoop.makeFailedFuture(NetworkError.internalError)
    }
}
