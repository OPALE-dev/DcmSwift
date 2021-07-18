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

public class DicomServer: DicomService, CStoreRQDelegate {
    var calledAET:DicomEntity!
    var port: Int = 11112
    
    var channel: Channel!
    var group:MultiThreadedEventLoopGroup!
    var bootstrap:ServerBootstrap!

    
    
    public init(port: Int, localAET:String) {
        super.init(localAET: localAET)
        
        self.calledAET  = DicomEntity(title: localAET, hostname: "localhost", port: port)
        self.port       = port
        
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.bootstrap = ServerBootstrap(group: group)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                // we create a new DicomAssociation for each new activating channel
                let assoc = DicomAssociation(calledAET: self.calledAET)
                
                assoc.cStoreRQDelegate = self
                
                return channel.pipeline.addHandlers([ByteToMessageHandler(PDUBytesDecoder(withAssociation: assoc)), assoc])
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
    }
    
    deinit {
        channel.close(mode: .all, promise: nil)
    }
    
    
    public func start() {
        do {
            channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
            
            Logger.info("Server listening on port \(port)...")
            
            try channel.closeFuture.wait()
            
        } catch let e {
            Logger.error(e.localizedDescription)
        }
        
        do {
            try! group.syncShutdownGracefully()
        }
    }
    
    
    
    // MARK: -
    
    public func receive(message: CStoreRQ) {
        if message.receivedData.count > 0 {
            let dis = DicomInputStream(data: message.receivedData)
            
            dis.vrMethod = .Explicit
            
            if let d = try? dis.readDataset(enforceVR: false) {
                if let sopClassUID      = d.string(forTag: "SOPClassUID"),
                   let sopInstanceUID   = d.string(forTag: "SOPInstanceUID") {

                    _ = d.set(value: 0x0000, forTagName: "FileMetaInformationVersion")
                    _ = d.set(value: sopClassUID, forTagName: "MediaStorageSOPClassUID")
                    _ = d.set(value: sopInstanceUID, forTagName: "MediaStorageSOPInstanceUID")
                    _ = d.set(value: TransferSyntax.explicitVRLittleEndian, forTagName: "TransferSyntaxUID")
                    _ = d.set(value: orgRoot, forTagName: "ImplementationClassUID")
                    _ = d.set(value: "DcmSwift", forTagName: "ImplementationVersionName")
                    
                    if let t = message.association.callingAET?.title {
                        _ = d.set(value: t, forTagName: "SourceApplicationEntityTitle")
                    }
                    
                    d.hasPreamble = true
                    
                    try? d.toData().write(to: URL(fileURLWithPath: "/Users/nark/test_sore.dcm"))
                }
            }
        }
    }
}
