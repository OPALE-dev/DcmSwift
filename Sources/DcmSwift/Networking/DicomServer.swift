//
//  DicomServer.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 08/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation
import NIO
import Dispatch


public struct ServerConfig {
    public var enableCEchoSCP:Bool?     = true
    public var enableCFindSCP:Bool?     = true
    public var enableCStoreSCP:Bool?    = true
    
    public init(enableCEchoSCP:Bool, enableCFindSCP:Bool, enableCStoreSCP:Bool) {
        self.enableCEchoSCP     = enableCEchoSCP
        self.enableCFindSCP     = enableCFindSCP
        self.enableCStoreSCP    = enableCStoreSCP
    }
}

public class DicomServer: CEchoSCPDelegate, CFindSCPDelegate, CStoreSCPDelegate {
    var calledAE:DicomEntity!
    var port: Int = 11112
    
    var config:ServerConfig
    
    var channel: Channel!
    var group:MultiThreadedEventLoopGroup!
    var bootstrap:ServerBootstrap!

    
    
    public init(port: Int, localAET:String, config:ServerConfig) {
        self.calledAE   = DicomEntity(title: localAET, hostname: "localhost", port: port)
        self.port       = port
        self.config     = config
        
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                // we create a new DicomAssociation for each new activating channel
                let assoc = DicomAssociation(group: self.group, calledAE: self.calledAE)
                
                // this assoc implements to the following SCPs:
                // C-ECHO-SCP
                if config.enableCEchoSCP ?? false {
                    assoc.addServiceClassProvider(CEchoSCP(self))
                }
                // C-FIND-SCP
                if config.enableCEchoSCP ?? false {
                    assoc.addServiceClassProvider(CFindSCP(self))
                }
                // C-STORE-SCP
                if config.enableCEchoSCP ?? false {
                    assoc.addServiceClassProvider(CStoreSCP(self))
                }
                
                return channel.pipeline.addHandlers([ByteToMessageHandler(PDUBytesDecoder(withAssociation: assoc)), assoc])
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
    }
    
    
    deinit {
//        channel.close(mode: .all, promise: nil)
//
//        try? group.syncShutdownGracefully()
    }
    
    /**
     Starts the server
     */
    public func start() {
        do {
            defer {
                try? group.syncShutdownGracefully()
            }
            
            channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
            
            Logger.info("Server listening on port \(port)...")
            
            try channel.closeFuture.wait()
            
        } catch let e {
            Logger.error(e.localizedDescription)
        }
    }
    
    
    
    // MARK: - CEchoSCPDelegate
    public func validateEcho(callingAE: DicomEntity) -> DIMSEStatus.Status {
        return .Success
    }
    
    
    
    // MARK: - CFindSCPDelegate
    public func query(level: QueryRetrieveLevel, dataset: DataSet) -> [DataSet] {
        print("query \(level) \(dataset)")
        return []
    }
    
    
    // MARK: - CStoreSCPDelegate
    public func store(fileMetaInfo:DataSet, dataset: DataSet, tempFile:String) -> Bool {
//        if message.receivedData.count > 0 {
//            let dis = DicomInputStream(data: message.receivedData)
//
//            dis.vrMethod = .Explicit
//
//            if let d = try? dis.readDataset(enforceVR: false) {
//                if let sopClassUID      = d.string(forTag: "SOPClassUID"),
//                   let sopInstanceUID   = d.string(forTag: "SOPInstanceUID") {
//
//                    _ = d.set(value: 0x0000, forTagName: "FileMetaInformationVersion")
//                    _ = d.set(value: sopClassUID, forTagName: "MediaStorageSOPClassUID")
//                    _ = d.set(value: sopInstanceUID, forTagName: "MediaStorageSOPInstanceUID")
//                    _ = d.set(value: TransferSyntax.explicitVRLittleEndian, forTagName: "TransferSyntaxUID")
//                    _ = d.set(value: orgRoot, forTagName: "ImplementationClassUID")
//                    _ = d.set(value: "DcmSwift", forTagName: "ImplementationVersionName")
//
//                    if let t = message.association.callingAE?.title {
//                        _ = d.set(value: t, forTagName: "SourceApplicationEntityTitle")
//                    }
//
//                    d.hasPreamble = true
//
//                    try? d.toData().write(to: URL(fileURLWithPath: "/Users/nark/test_sore.dcm"))
//                }
//            }
//        }
        return false
    }
}
