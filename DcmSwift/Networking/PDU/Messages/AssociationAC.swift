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
    public var remoteCalledAETitle:String?
    public var remoteCallingAETitle:String?
    
    public override func data() -> Data {
        return Data()
    }
    
    public override func messageName() -> String {
        return "A-ASSOCIATE-AC"
    }
    
    
    public override func decodeData(data:Data) -> Bool {
        var offset = 0
        
        // PDU type
        let pcPduType = data.first
        if pcPduType != 0x02 {
            SwiftyBeaver.error("ERROR: Waiting for an A-ASSOCIATE-AC message, received \(String(describing: pcPduType))")
            return false
        }
        offset += 2
        
        // get full length
        let _ = data.subdata(in: offset..<6).toInt32(byteOrder: .BigEndian)
        offset += 4 
        
        // check protocol version
        let protocolVersion = data.subdata(in: offset..<offset+2).toInt16(byteOrder: .BigEndian)
        if Int(protocolVersion) != self.association?.protocolVersion {
            SwiftyBeaver.error("WARN: Wrong protocol version")
            return false
        }
        offset += 2
        
        // reserved bytes
        offset += 2
        
        // TODO: Called / Calling AE Titles
        self.remoteCalledAETitle = data.subdata(in: offset..<offset+16).toString()
        offset += 16
        self.remoteCallingAETitle = data.subdata(in: offset..<offset+16).toString()
        offset += 16
        
        // reserved bytes
        offset += 32
        
        // parse app context
        let acLength = Int(data.subdata(in: offset+2..<offset+4).toInt16(byteOrder: .BigEndian))
        var acData = data.subdata(in: offset..<offset+acLength+4)
        guard let applicationContext = ApplicationContext(data: acData) else {
            SwiftyBeaver.error("Missing application context. Abort.")
            return false
        }
        offset += acData.count
        self.association.remoteApplicationContext = applicationContext
        
        // parse presentation context
        var pcType = data.subdata(in: offset..<offset + 1).toInt8()
        
        while pcType == ItemType.acPresentationContext.rawValue {
            offset += 2
            
            let pcLength = data.subdata(in: offset..<offset + 2).toInt16().bigEndian
            offset += 2
            
            let pcData = data.subdata(in: offset-4..<offset+Int(pcLength))
            
            if let presentationContext = PresentationContext(data: pcData) {
                self.association.acceptedPresentationContexts[presentationContext.contextID] = presentationContext
            }
            
            offset += Int(pcLength)
            pcType = data.subdata(in: offset..<offset + 1).toInt8()
        }

        // read user info
        offset = offset + 4
        let userInfoData = data.subdata(in: offset..<data.count)
        
        guard let userInfo = UserInfo(data: userInfoData) else {
            SwiftyBeaver.warning("No user information values provided. Abort")
            return false
        }

        self.association?.maxPDULength = userInfo.maxPDULength
        self.association?.remoteImplementationUID = userInfo.implementationUID
        self.association?.remoteImplementationVersion = userInfo.implementationVersion
        self.association?.associationAccepted = true

        SwiftyBeaver.info(" ")
        
        return true
    }
    
    
    public override func messagesData() -> [Data] {
        return []
    }
}
