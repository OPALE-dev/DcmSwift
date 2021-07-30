//
//  File.swift
//  
//
//  Created by Rafael Warnault on 28/07/2021.
//

import Foundation
import NIO


/**
 This service delegate provides a way to implement specific behaviors in the end-program
 */
public protocol CFindSCPDelegate {
    func query(level:QueryRetrieveLevel, dataset:DataSet) -> [DataSet]
}


public class CFindSCP: ServiceClassProvider {
    private var delegate:CFindSCPDelegate?
    private var lastFindRQ:CFindRQ?
    
    public override var commandField:CommandField {
        .C_FIND_RSP
    }
    
    
    public init(_ delegate:CFindSCPDelegate?) {
        super.init()
        
        self.delegate = delegate
    }
    
    
    
    public override func reply(request: PDUMessage?, association:DicomAssociation, channel:Channel) -> EventLoopFuture<Void> {
        self.requestMessage = request
        
        if let cFindRQ = request as? CFindRQ {
            lastFindRQ = cFindRQ
            
            // we already got the query dataset
            if cFindRQ.resultsDataset != nil {
                return query(dataset: cFindRQ.resultsDataset!, association: association, channel: channel)
            }
            
        } else if let dataTF = request as? DataTF {
            let pc = association.acceptedPresentationContexts[association.acceptedPresentationContexts.keys.first!]
            let ts = pc?.transferSyntaxes.first
            
            if ts == nil {
                Logger.error("No transfer syntax found, refused")
                return channel.eventLoop.makeFailedFuture(NetworkError.internalError)
            }
            
            let transferSyntax = TransferSyntax(ts!)
            
            if dataTF.receivedData.count > 0 {
                let dis = DicomInputStream(data: dataTF.receivedData)

                dis.vrMethod    = transferSyntax!.vrMethod
                dis.byteOrder   = transferSyntax!.byteOrder

                if let resultDataset = try? dis.readDataset(enforceVR: false) {
                    lastFindRQ?.resultsDataset = resultDataset
                    
                    return query(dataset: resultDataset, association: association, channel: channel)
                }
            }
        }
        
        return channel.eventLoop.makeFailedFuture(NetworkError.internalError)
    }
    
    
    
    // MARK: - Private
    private func query(dataset: DataSet, association:DicomAssociation, channel:Channel) -> EventLoopFuture<Void> {
        guard let qrl = dataset.string(forTag: "QueryRetrieveLevel")?.trimmingCharacters(in: .whitespaces) else {
            Logger.fatal("Query Retrieve Level is required, abort")
            return channel.eventLoop.makeFailedFuture(NetworkError.internalError)
        }
        
        // loop over delegate find results and send data-tf
        if delegate != nil {
            var datasets:[DataSet] = []
            
            if qrl == "PATIENT" {
                datasets = delegate!.query(level: .PATIENT, dataset: dataset)
            }
            else if qrl == "STUDY" {
                datasets = delegate!.query(level: .STUDY, dataset: dataset)
            }
            else if qrl == "SERIES" {
                datasets = delegate!.query(level: .SERIES, dataset: dataset)
            }
            else if qrl == "IMAGE" {
                datasets = delegate!.query(level: .IMAGE, dataset: dataset)
            }
            
            for dataset in datasets {
                // send dataset as data-tf
            }
        }
        
        // Send data-tf success
        if let message = PDUEncoder.createDIMSEMessage(pduType: .dataTF, commandField: self.commandField, association: association) as? PDUMessage {

            message.requestMessage = self.requestMessage
            message.dimseStatus = DIMSEStatus(status: .Success, command: self.commandField)
            
            self.requestMessage = nil

            let p:EventLoopPromise<Void> = channel.eventLoop.makePromise()

            return association.write(message: message, promise: p)
        }
        
        return channel.eventLoop.makeFailedFuture(NetworkError.internalError)
    }
}
