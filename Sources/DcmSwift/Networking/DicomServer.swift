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

public class DicomServer: DicomService {
    var calledAET:DicomEntity!
    var port: Int = 11112
    
    var channel: Channel!
    var group:MultiThreadedEventLoopGroup!
    var bootstrap:ServerBootstrap!

    
    
    public init(port: Int, localAET:String) {
        super.init(localAET: localAET)
        
        self.calledAET = DicomEntity(title: localAET, hostname: "localhost", port: port)
        
        self.port = port
        
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.bootstrap = ServerBootstrap(group: group)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                    // we create a new DicomAssociation for each new activating channel
                    let assoc = DicomAssociation(calledAET: self.calledAET)
                
                    return channel.pipeline.addHandlers([ByteToMessageHandler(PDUMessageDecoder(withAssociation: assoc)), assoc])
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
}
