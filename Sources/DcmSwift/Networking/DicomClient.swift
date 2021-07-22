//
//  File.swift
//  
//
//  Created by Rafael Warnault on 20/07/2021.
//

import Foundation
import NIO

public class DicomClient {
    var eventLoopGroup:MultiThreadedEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    var callingAE:DicomEntity
    var calledAE:DicomEntity
    
    
    public init(aet: String, calledAE:DicomEntity) {
        self.calledAE   = calledAE
        self.callingAE  = DicomEntity(title: aet, hostname: "localhost", port: 11112)
    }
    
    
    public init(callingAE: DicomEntity, calledAE:DicomEntity) {
        self.calledAE   = calledAE
        self.callingAE  = callingAE
    }
    
    
    public func echo() -> Bool {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let assoc = DicomAssociation(group: eventLoopGroup, callingAE: callingAE, calledAE: calledAE)
        
        assoc.setService(CEchoSCUService())

        do {
            _ = try assoc.handle(event: .AE1).wait()
            
            if let status = try assoc.promise?.futureResult.wait(),
               status == .Success {
                return true
            }
            
        } catch let e {
            Logger.error(e.localizedDescription)
        }
        
        return false
    }
    
    
    public func find(queryDataset:DataSet? = nil) -> [DataSet] {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let assoc = DicomAssociation(group: eventLoopGroup, callingAE: callingAE, calledAE: calledAE)
        let service = CFindSCUService(queryDataset)
        
        assoc.setService(service)

        do {
            _ = try assoc.handle(event: .AE1).wait()
            
            if let status = try assoc.promise?.futureResult.wait(),
               status == .Success {
                return service.studiesDataset
            }
            
        } catch let e {
            Logger.error(e.localizedDescription)
        }
        
        return []
    }
    
    
    public func store(filePaths:[String]) -> Bool {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let assoc = DicomAssociation(group: eventLoopGroup, callingAE: callingAE, calledAE: calledAE)
        
        assoc.setService(CStoreSCUService(filePaths))

        do {
            _ = try assoc.handle(event: .AE1).wait()
            
            let status = try assoc.promise?.futureResult.wait()
                        
            if status == .Success {
                return true
            }
            
        } catch let e {
            Logger.error(e.localizedDescription)
        }
        
        return false
    }
    
    
    
    public func move(uids:[String], aet:String) -> Bool {
        return false
    }
    
    
    
    public func get() -> Bool {
        return false
    }
}
