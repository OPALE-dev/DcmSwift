//
//  AssociationAC.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 03/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation
import SwiftyBeaver

public class AssociationAC: PDUMessage {
    public override func data() -> Data {
        return Data()
    }
    
    public override func decodeData(data:Data) -> Bool {
        SwiftyBeaver.info("==================== RECEIVE A-ASSOCIATE-AC ====================")
        SwiftyBeaver.debug("A-ASSOCIATE-AC DATA : \(data.toHex().separate(every: 2, with: " "))")
        
        // get full length
        var offset = 2
        //let length = data.subdata(in: offset..<6).toInt32(byteOrder: .BigEndian)
        offset = 6
        
        // check protocol version
        let protocolVersion = data.subdata(in: offset..<offset+2).toInt16(byteOrder: .BigEndian)
        if Int(protocolVersion) != self.association?.protocolVersion {
            SwiftyBeaver.error("WARN: Wrong protocol version")
            return false
        }
        offset = 8
        
        // TODO: Called / Calling AE Titles
        offset = 74
        
        // parse app context
        var subdata = data.subdata(in: offset..<data.count)
        guard let applicationContext = ApplicationContext(data: subdata) else {
            SwiftyBeaver.error("Missing application context. Abort.")
            return false
        }
        
        SwiftyBeaver.info("  -> Application Context Name: \(applicationContext.applicationContextName)")
        
        // parse presentation context
        SwiftyBeaver.info("  -> Presentation Contexts:")
        offset = Int(applicationContext.length) + 8
        subdata = subdata.subdata(in: offset..<subdata.count)
        offset = 0
        
        guard let presentationContext = PresentationContext(data: subdata) else {
            SwiftyBeaver.error("Missing presentation context. Abort.")
            return false
        }
        
//        if presentationContext.contextID != self.association?.contextID {
//            SwiftyBeaver.error("Wrong context ID. Abort.")
//            return false
//        }
        
        if let ats = presentationContext.acceptedTransferSyntax {
            if let assoc = self.association {
                if !assoc.checkTransferSyntax(ats) {
                    SwiftyBeaver.error("Unsupported accepted Transfer Syntax. Abort.")
                    return false
                }
            }
            self.association?.acceptedTransferSyntax = ats
        }
        
        SwiftyBeaver.info("    -> Context ID: \(presentationContext.contextID ?? 0)")
        SwiftyBeaver.info("      -> Accepted Transfer Syntax(es): \(presentationContext.acceptedTransferSyntax ?? "")")
        
        // read user info
        SwiftyBeaver.info("  -> User Informations:")
        offset = Int(presentationContext.length()) + 4
        subdata = subdata.subdata(in: offset..<subdata.count)
        
        guard let userInfo = UserInfo(data: subdata) else {
            SwiftyBeaver.warning("No user information values provided. Abort")
            return false
        }
        
        self.association?.maxPDULength = userInfo.maxPDULength
        self.association?.remoteImplementationUID = userInfo.implementationUID
        self.association?.remoteImplementationVersion = userInfo.implementationVersion
        
        SwiftyBeaver.info("    -> Remote Max PDU: \(self.association!.maxPDULength)")
        SwiftyBeaver.info("    -> Implementation class UID: \(self.association!.remoteImplementationUID ?? "")")
        SwiftyBeaver.info("    -> Implementation version: \(self.association!.remoteImplementationVersion ?? "")")
        
        self.association?.associationAccepted = true
        
        SwiftyBeaver.info(" ")
        
        return true
    }
    
    
    public override func messageData() -> Data? {
        return nil
    }
}
