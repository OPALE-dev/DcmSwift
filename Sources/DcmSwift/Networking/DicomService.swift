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
}



public class CStoreSCUService: DicomService {
    public override var commandField:CommandField {
        .C_STORE_RQ
    }
    
    
    public override var abstractSyntaxes:[String] {
        DicomConstants.storageSOPClasses
    }
}
