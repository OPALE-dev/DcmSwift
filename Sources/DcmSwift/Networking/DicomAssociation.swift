//
//  File.swift
//  
//
//  Created by Rafael Warnault on 20/07/2021.
//

import Foundation
import NIO

internal extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        self.lock()
        defer {
            self.unlock()
        }
        return body()
    }
}



public class DicomAssociation: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
        
    
    
    public enum Origin {
        case Local
        case Remote
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
        case Sta4
        case Sta5
        case Sta6
        case Sta7
        case Sta13
    }
    
    
    public enum PDUAction {
        case AE1
        case AE2
        case AE3(_ message:AssociationAC)
        case AE4
        case AE5
        case AE6
        case AE7
        case AE8
        
        case DT1
        case DT2(_ message:DataTF)
        
        case AR1
        case AR2
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
 
        
    internal enum ClientError: LocalizedError {
        case notReady
        case cantBind
        case timeout
        case connectionResetByPeer
        case transitionNotFound
        case internalError
        case errorComment(message:String)
        case associationRejected(reason:String)
        
        public var errorDescription: String? {
            switch self {
      
            case .notReady:
                return "Association is not ready"
            case .cantBind:
                return "Association cant bind"
            case .timeout:
                return "Timeout error"
            case .connectionResetByPeer:
                return "Connection reset by peer"
            case .transitionNotFound:
                return "Transition not found"
            case .internalError:
                return "Internal error"
            case .errorComment(message: let message):
                return "Error Comment: \(message)"
            case .associationRejected(reason: let reason):
                return "Association rejected: \(reason)"
            }
        }
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
    var callingAE:DicomEntity!
    
    public let group: MultiThreadedEventLoopGroup
    private var channel: Channel?
    public var promise: EventLoopPromise<DIMSEStatus.Status>?
    public var service:DicomService?
    public var dimseStatus:DIMSEStatus.Status?
    
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
     Constructor for Associations created by clients
        -> Origin is `Local`
     */
    public init(group: MultiThreadedEventLoopGroup, callingAE:DicomEntity, calledAE:DicomEntity) {
        self.group      = group
        self.calledAE   = calledAE
        self.callingAE  = callingAE
        self.origin     = .Local
    }
    
    
    
    
    // MARK: -
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = self.unwrapInboundIn(data)
        let bytes = buffer.readBytes(length: buffer.readableBytes)
        let pduData = Data(bytes!)
        
        //print("channelRead")
        
        switch state {
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
                                
                promise?.fail(ClientError.associationRejected(reason: "\(message.reason)"))
                
                // _ = try? handle(event: .AR3(message))
            }
        case .Sta6:
            switch self.service {
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
        if origin == .Local {
            _ = try? handle(event: .AE2)
        }
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        print("channelInactive")
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error \(error)")
    }
    
    
    public func setService(_ service:DicomService) {
        self.service = service
        
        for ast in service.abstractSyntaxes {
            self.addPresentationContext(abstractSyntax: ast)
        }
    }
    
    // MARK: -
    /**
    State Machine transitions
     */
    private func transition(forEvent event: PDUAction) throws -> EventLoopFuture<Void> {
        Logger.verbose("FSM  [STATE] (\(state)) \(event)", "Association")
        
        switch (state, event) {
        case (.Sta1, .AE1):                     return AE1()
            case (.Sta4, .AE2):                 return AE2()
            case (.Sta5, .AE3):                 return AE3()
            case (.Sta6, .DT1):                 return DT1()
            case (.Sta6, .DT2(let message)):    return DT2(message)
            case (.Sta6, .AR1):                 return AR1()
            case (.Sta7, .AR3(let message)):    return AR3(message)
            default: throw ClientError.transitionNotFound
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
            return channel!.eventLoop.makeFailedFuture(ClientError.internalError)
        }
        
        associationRQ.remoteCalledAETitle   = self.calledAE.title
        associationRQ.remoteCallingAETitle  = self.callingAE.title
        
        let p:EventLoopPromise<Void> = channel!.eventLoop.makePromise()
        
        return write(message: associationRQ, promise: p)
    }
    
    
    private func AE3() -> EventLoopFuture<Void> {
        self.state = .Sta6
        
        if origin == .Local {
            _ = try? handle(event: .DT1)
        }

        return channel!.eventLoop.makeSucceededVoidFuture()
    }
    
    
    
    private func DT1() -> EventLoopFuture<Void> {
        self.state = .Sta6
        
        if origin == .Local {
            if let service = self.service {
                // rely on service
                return service.run(association: self, channel: self.channel!)
            }
        }

        return channel!.eventLoop.makeSucceededVoidFuture()
    }
    
    
    private func DT2(_ message:DataTF) -> EventLoopFuture<Void> {
        self.state = .Sta6
        
        if let service = self.service {
            if origin == .Local {
                // Run services
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
                                        let error = ClientError.errorComment(message: errorComment)
                                        
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

        return channel!.eventLoop.makeFailedFuture(ClientError.internalError)
    }
    
    
    private func AR1() -> EventLoopFuture<Void> {
        self.state = .Sta7
        
        guard let releaseRQ = PDUEncoder.createAssocMessage(pduType: .releaseRQ, association: self) as? PDUMessage else {
            return channel!.eventLoop.makeFailedFuture(ClientError.internalError)
        }
                    
        let p:EventLoopPromise<Void> = channel!.eventLoop.makePromise()
        
        return write(message: releaseRQ, promise: p)
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
            return self.group.next().makeFailedFuture(ClientError.notReady)
        }
        
        guard let channel = self.channel else {
            return self.group.next().makeFailedFuture(ClientError.notReady)
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
            return channel!.eventLoop.makeFailedFuture(ClientError.internalError)
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

}
