//
//  DicomServer.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 08/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation
import Socket
import Dispatch

public class DicomServer: DicomService {
    var calledAET:DicomEntity!
    var port: Int = 11112
    
    var listenSocket: Socket? = nil
    var continueRunningValue = true
    
    var connectedAssociations = [Int32: DicomAssociation]()
    let socketLockQueue = DispatchQueue(label: "pro.opale.DcmSwift.socketLockQueue")
    
    var continueRunning: Bool {
        set(newValue) {
            socketLockQueue.sync {
                self.continueRunningValue = newValue
            }
        }
        get {
            return socketLockQueue.sync {
                self.continueRunningValue
            }
        }
    }
    
    public init(port: Int, localAET:String) {
        super.init(localAET: localAET)
        
        self.calledAET = DicomEntity(title: localAET, hostname: "localhost", port: port)
        
        self.port = port
    }
    
    deinit {
        // Close all open sockets...
        for assoc in connectedAssociations.values {
            assoc.close()
        }
        self.listenSocket?.close()
    }
    
    @available(OSX 10.12, *)
    public func run() {
        do {
            // Create an IPV4 socket...
            try self.listenSocket = Socket.create(family: .inet)
            guard let socket = self.listenSocket else {
                Logger.error("Unable to unwrap socket...")
                return
            }
    
            // Listen on the socket
            try socket.listen(on: self.port)
            Logger.info("Listening on port: \(socket.listeningPort)")
            
            repeat {
                let newSocket = try socket.acceptClientConnection()
                
                // detach new socket on another thread
                Thread.detachNewThread {
                    newSocket.readBufferSize = DicomConstants.maxPDULength
                    Logger.debug("Accepted connection from: \(newSocket.remoteHostname) on port \(newSocket.remotePort)")
                    
                    // handle new association
                    self.handleAssociation(DicomAssociation(socket: newSocket, calledAET: self.calledAET), socket: newSocket)
                }
                
            } while self.continueRunning
            
        }
        catch let error {
            guard let socketError = error as? Socket.Error else {
                Logger.error("Unexpected error...")
                return
            }
            
            if self.continueRunning {
                Logger.error("Error reported:\n \(socketError.description)")
                
            }
        }
    }
    
    
    private func handleAssociation(_ association:DicomAssociation, socket: Socket) {
        // setup accepted presentation contexts
        association.addPresentationContext(abstractSyntax: DicomConstants.verificationSOP, result: 0x00)
        association.addPresentationContext(abstractSyntax: DicomConstants.StudyRootQueryRetrieveInformationModelFIND, result: 0x00)
        for sop in DicomConstants.storageSOPClasses {
            association.addPresentationContext(abstractSyntax: sop, result: 0x00)
        }
        Logger.verbose("Server Presentation Contexts: \(association.presentationContexts)");
        
        // read ASSOCIATION-AC
        if association.acknowledge() {
            Logger.debug("Add association: [\(socket.socketfd)] calledAET:\(String(describing: association.calledAET)) <-> callingAET:\(String(describing: association.callingAET))")
            self.connectedAssociations[socket.socketfd] = association
            
            // listen for DIMSE service messages (C-ECHO-RQ, C-FIND-RQ, etc.)
            association.listen { (sock) in
                self.connectedAssociations.removeValue(forKey: sock.socketfd)
                Logger.debug("Remove association: [\(socket.socketfd)]")
                
                sock.close()
            }
        }
    }
}
