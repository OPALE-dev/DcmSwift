//
//  File.swift
//  
//
//  Created by Rafael Warnault, OPALE on 23/07/2021.
//

import Foundation
import NIO

public class CFindSCUService: ServiceClassUser {
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
    
    
    public override func request(association:DicomAssociation, channel:Channel) -> EventLoopFuture<Void> {
        if let message = PDUEncoder.createDIMSEMessage(pduType: .dataTF, commandField: self.commandField, association: association) as? CFindRQ {
            let p:EventLoopPromise<Void> = channel.eventLoop.makePromise()

            _ = queryDataset.set(value: "STUDY", forTagName: "QueryRetrieveLevel")

            message.queryDataset = queryDataset
            
            return association.write(message: message, promise: p)
        }
        return channel.eventLoop.makeSucceededVoidFuture()
    }
    
    
    public override func receive(association:DicomAssociation, dataTF message:DataTF) -> DIMSEStatus.Status {
        var result:DIMSEStatus.Status = .Pending
        
        if let m = message as? CFindRSP {
            // C-FIND-RSP message (with or without DATA fragment)
            result = message.dimseStatus.status
            
            receiveRSP(m)
            
            return result
        }
        else {
            // single DATA-TF fragment
            if let ats = association.acceptedTransferSyntax,
               let transferSyntax = TransferSyntax(ats) {
                receiveData(message, transferSyntax: transferSyntax)
            }
        }
        
        return result
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
