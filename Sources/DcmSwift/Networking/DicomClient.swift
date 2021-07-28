//
//  DicomClient.swift
//  
//
//  Created by Rafael Warnault, OPALE on 20/07/2021.
//

import Foundation
import NIO


/**
 A client with implementation of the basic DICOM services.
 
 This class provides its own `MultiThreadedEventLoopGroup` based on `System.coreCount`
 number of threads, but can also be instanciated with your own NIO event loop if you need.
 
 Example of use:
 
     // create a DICOM client
     let client = DicomClient(
         callingAE: callingAE,
         calledAE: calledAE)
     
     // run C-ECHO SCU service
     do {
         if try client.echo() {
             print("C-ECHO \(calledAE) SUCCEEDED")
         } else {
             print("C-ECHO \(callingAE) FAILED")
         }
     } catch let e {
         Logger.error(e.localizedDescription)
     }
 
 */
public class DicomClient {
    /**
     The NIO event loop used by the client
     */
    private var eventLoopGroup:MultiThreadedEventLoopGroup
    
    /**
     The self AE, aka calling AE, which represent the local AE requesting the remote AE
     */
    private var callingAE:DicomEntity
    
    /**
     The called AE represents the remote AE requested by the local AE
     */
    private var calledAE:DicomEntity
    

    /**
     Init a client with a self AET, regarless to the hostname and port (they are unused for the `callingAE`)
     The NIO event loop will be created automatically
     
     - Parameter aet: yourself Application Entity Title
     - Parameter calledAE: the remote `DicomEntity`to request
     
     */
    public init(aet: String, calledAE:DicomEntity) {
        self.calledAE       = calledAE
        self.callingAE      = DicomEntity(title: aet, hostname: "localhost", port: 11112)
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }
    
    /**
     Init a client with `callingAE` and `calledAE` objects
     The NIO event loop will be created automatically
     
     - Parameter callingAE: yourself `DicomEntity`
     - Parameter calledAE: the remote `DicomEntity`to request
     
     */
    public init(callingAE: DicomEntity, calledAE:DicomEntity) {
        self.calledAE       = calledAE
        self.callingAE      = callingAE
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }
    
    
    /**
     Init a client with your own NIO event loop
     
     - Parameter callingAE: yourself `DicomEntity`
     - Parameter calledAE: the remote `DicomEntity`to request
     - Parameter eventLoopGroup: your own NIO event loop
     */
    public init(callingAE: DicomEntity, calledAE:DicomEntity, eventLoopGroup:MultiThreadedEventLoopGroup? = nil) {
        self.calledAE   = calledAE
        self.callingAE  = callingAE
        
        if let elg = eventLoopGroup {
            self.eventLoopGroup = elg
        } else {
            self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        }
    }
    
    
    /**
     Perform a C-ECHO request to the `calledAE`
     
     - Throws: `NetworkError.*`, `StreamError.*` or any other NIO realm errors
     
     - Returns: `true` if the C-ECHO-RSP DIMSE Status is `Success`
     
     Example of use:
     
         // create a DICOM client
         let client = DicomClient(
             callingAE: callingAE,
             calledAE: calledAE)
         
         // run C-ECHO SCU service
         do {
             if try client.echo() {
                 print("C-ECHO \(calledAE) SUCCEEDED")
             } else {
                 print("C-ECHO \(callingAE) FAILED")
             }
         } catch let e {
             Logger.error(e.localizedDescription)
         }
     
     */
    public func echo() throws -> Bool {
        let assoc = DicomAssociation(group: eventLoopGroup, callingAE: callingAE, calledAE: calledAE)
        var result = false
        
        assoc.setServiceClassUser(CEchoSCUService())

        _ = try assoc.handle(event: .AE1).wait()
        
        if let status = try assoc.promise?.futureResult.wait(),
           status == .Success {
            result = true
        }
        
        _ = try assoc.disconnect().wait()
        
        return result
    }
    
    
    /**
     Perform a C-FIND request to the `calledAE`
          
     - Parameter queryDataset: Your query dataset, primarilly used by the C-FIND SCP to determine
     what attributes you want to get as result, and also to set filters to precise your search. If no query dataset
     is given, the `CFindSCUService` will provide you some default attributes (see `CFindSCUService.init()`)
     
     - Throws: `NetworkError.*`, `StreamError.*` or any other NIO realm errors
     
     - Returns: a dataset array if the C-FIND-RSP DIMSE Status is `Success`. If the returned array is empty,
     the C-FIND SCP probably has no result for the given query.
     
     Example of use:
     
            // create a dataset
            let queryDataset = DataSet()
     
            queryDataset.set(value:"", forTagName: "PatientID")
            queryDataset.set(value:"", forTagName: "PatientName")
            queryDataset.set(value:"", forTagName: "PatientBirthDate")
            queryDataset.set(value:"", forTagName: "StudyDescription")
            queryDataset.set(value:"", forTagName: "StudyDate")
            queryDataset.set(value:"", forTagName: "StudyTime")
            queryDataset.set(value:"MR", forTagName: "ModalitiesInStudy") // only MR modality studies
            queryDataset.set(value:"", forTagName: "AccessionNumber")

             // create a DICOM client
             let client = DicomClient(
                 callingAE: callingAE,
                 calledAE: calledAE)
             
             // run C-FIND SCU service
             do {
                print(try client.find())
             } catch let e {
                print(e)
             }
     
     */
    public func find(queryDataset:DataSet? = nil) throws -> [DataSet] {
        let assoc = DicomAssociation(group: eventLoopGroup, callingAE: callingAE, calledAE: calledAE)
        let service = CFindSCUService(queryDataset)
        var result:[DataSet] = []
        
        assoc.setServiceClassUser(service)

        _ = try assoc.handle(event: .AE1).wait()
        
        if let status = try assoc.promise?.futureResult.wait(),
           status == .Success {
            result.append(contentsOf: service.studiesDataset)
        }
        
        _ = try assoc.disconnect().wait()
        
        return result
    }
    
    /**
     Perform a C-STORE request to the `calledAE`
          
     - Parameter filePaths: an array of absolute path of DICOM files
     
     - Throws: `NetworkError.*`, `StreamError.*` or any other NIO realm errors
     
     - Returns: `true` if the C-STORE-RSP DIMSE Status is `Success`
     
     Example of use:
     
         let client = DicomClient(
             callingAE: callingAE,
             calledAE:  calledAE)
         
         // run C-STORE SCU service to send files given as arguements
         do {
             if try client.store(filePaths: flattenPaths(filePaths)) {
                 print("\nC-STORE \(calledAE) SUCCEEDED.\n")
             }
         } catch let e {
             Logger.error(e.localizedDescription)
         }
     
     */
    public func store(filePaths:[String]) throws -> Bool {
        let assoc = DicomAssociation(group: eventLoopGroup, callingAE: callingAE, calledAE: calledAE)
        var result = false
        
        assoc.setServiceClassUser(CStoreSCUService(filePaths))

        _ = try assoc.handle(event: .AE1).wait()
        
        let status = try assoc.promise?.futureResult.wait()
                    
        if status == .Success {
            result = true
        }
        
        _ = try assoc.disconnect().wait()
        
        return result
    }
    
    
    
    public func move(uids:[String], aet:String) -> Bool {
        return false
    }
    
    
    
    public func get() -> Bool {
        return false
    }
}
