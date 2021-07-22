//
//  File.swift
//  
//
//  Created by Rafael Warnault on 20/07/2021.
//

import Foundation
import NIO


public class DicomService {
    public init() {
        
    }
    
    
    public var abstractSyntaxes:[String] {
        []
    }
    
    
    public var commandField:CommandField {
        .NONE
    }
    
    
    public func run(association:DicomAssociation, channel:Channel) -> EventLoopFuture<Void> {
        if let message = PDUEncoder.createDIMSEMessage(pduType: .dataTF, commandField: self.commandField, association: association) as? PDUMessage {
            let p:EventLoopPromise<Void> = channel.eventLoop.makePromise()
            return association.write(message: message, promise: p)
        }
        return channel.eventLoop.makeSucceededVoidFuture()
    }
}




public class CEchoSCUService: DicomService {
    public override var commandField:CommandField {
        .C_ECHO_RQ
    }
    
    
    public override var abstractSyntaxes:[String] {
        [DicomConstants.verificationSOP]
    }
}



public class CFindSCUService: DicomService {
    var queryDataset:DataSet
    var studiesDataset:[DataSet] = []
    var lastFindRSP:CFindRSP?
    
    public override var commandField:CommandField {
        .C_FIND_RQ
    }
    
    
    public override var abstractSyntaxes:[String] {
        [DicomConstants.StudyRootQueryRetrieveInformationModelFIND]
    }
    
    
    public init(_ queryDataset:DataSet? = nil) {
        if let d = queryDataset {
            self.queryDataset = d
            
        } else {
            self.queryDataset = DataSet()
            
            _ = self.queryDataset.set(value:"", forTagName: "PatientID")
            _ = self.queryDataset.set(value:"", forTagName: "PatientName")
            _ = self.queryDataset.set(value:"", forTagName: "PatientBirthDate")
            _ = self.queryDataset.set(value:"", forTagName: "StudyDescription")
            _ = self.queryDataset.set(value:"", forTagName: "StudyDate")
            _ = self.queryDataset.set(value:"", forTagName: "StudyTime")
            _ = self.queryDataset.set(value:"", forTagName: "AccessionNumber")
        }
        
        super.init()
    }
    
    
    public override func run(association:DicomAssociation, channel:Channel) -> EventLoopFuture<Void> {
        if let message = PDUEncoder.createDIMSEMessage(pduType: .dataTF, commandField: self.commandField, association: association) as? CFindRQ {
            let p:EventLoopPromise<Void> = channel.eventLoop.makePromise()

            _ = queryDataset.set(value: "STUDY", forTagName: "QueryRetrieveLevel")

            message.queryDataset = queryDataset
            
            return association.write(message: message, promise: p)
        }
        return channel.eventLoop.makeSucceededVoidFuture()
    }
    
    
    public func receiveRSP(_ message:CFindRSP) {
        if let dataset = message.studiesDataset {
            studiesDataset.append(dataset)
        } else {
            lastFindRSP = message
        }
    }
    
    
    public func receiveData(_ message:DataTF, transferSyntax:TransferSyntax) {
        if message.receivedData.count > 0 {
            let dis = DicomInputStream(data: message.receivedData)
            
            dis.vrMethod    = transferSyntax.vrMethod
            dis.byteOrder   = transferSyntax.byteOrder
        
            if let resultDataset = try? dis.readDataset(enforceVR: false) {
                studiesDataset.append(resultDataset)
            }
        }
    }
}



public class CStoreSCUService: DicomService {
    var filePaths:[String] = []
    
    
    public init(_ filePaths:[String]) {
        self.filePaths = filePaths
    }
    
    
    public override var commandField:CommandField {
        .C_STORE_RQ
    }
    
    
    public override var abstractSyntaxes:[String] {
        DicomConstants.storageSOPClasses
    }
    
    
    public override func run(association:DicomAssociation, channel:Channel) -> EventLoopFuture<Void> {
        for fp in filePaths {
            if let message = PDUEncoder.createDIMSEMessage(pduType: .dataTF, commandField: self.commandField, association: association) as? CStoreRQ {
                let p:EventLoopPromise<Void> = channel.eventLoop.makePromise()
                                
                message.dicomFile = DicomFile(forPath: fp)
                
                if fp != filePaths.last {
                    _ = association.write(message: message, promise: p)
                } else {
                    return association.write(message: message, promise: p)
                }
            }
        }
        return channel.eventLoop.makeSucceededVoidFuture()
    }
}
