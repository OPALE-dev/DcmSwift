//
//  PDUMessage.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 02/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation
import SwiftyBeaver



public class PDUMessage: PDUDecodable {
    public var pduType:PDUType!
    public var association:DicomAssociation!
    

    
    public init(pduType:PDUType, association:DicomAssociation) {
        self.pduType = pduType
        self.association = association
    }
    
    
    
    public convenience init?(data:Data, pduType:PDUType, association:DicomAssociation) {
        self.init(pduType: pduType, association: association)
        
        if !decodeData(data: data) {
            return nil
        }
    }
    
    
    public func data() -> Data {
        return Data()
    }
    
    public func decodeData(data:Data) -> Bool {
        return false
    }
    
    
    public func associationRQ(association:DicomAssociation) -> Data {
        var data = Data()
        
        let apData = association.applicationContext.data()
        let pcData = association.presentatinContext!.data()
        let uiData = association.userInfo!.data()
        
        let length = UInt32(2 + 2 + 16 + 16 + 32 + apData.count + pcData.count + uiData.count)
        
        data.append(uint8: self.pduType.rawValue, bigEndian: true)
        data.append(byte: 0x00) // 00H
        data.append(uint32: length, bigEndian: true)
        data.append(Data(bytes: [0x00, 0x01])) // Protocol version
        data.append(byte: 0x00, count: 2)
        data.append(association.calledAET.paddedTitleData()!) // Called AET Title
        data.append(association.callingAET.paddedTitleData()!) // Calling AET Title
        data.append(Data(repeating: 0x00, count: 32)) // 00H
        
        data.append(apData)
        data.append(pcData)
        data.append(uiData)
        
        return data
    }
    
    
    
    public func releaseRQ() -> Data {
        var data = Data()
        let length = UInt32(4)
        
        data.append(uint8: self.pduType.rawValue, bigEndian: true)
        data.append(byte: 0x00)
        data.append(uint32: length, bigEndian: true)
        data.append(byte: 0x00, count: 4)
        
        return data
    }
    

    
    
    public func echoRQ(association:DicomAssociation) -> Data {
        var data = Data()
                
        let pdvDataset = DataSet()
        _ = pdvDataset.set(value: CommandField.C_ECHO_RQ.rawValue.bigEndian, forTagName: "CommandField")
        _ = pdvDataset.set(value: DicomConstants.verificationSOP, forTagName: "AffectedSOPClassUID")
        _ = pdvDataset.set(value: UInt16(1).bigEndian, forTagName: "MessageID")
        _ = pdvDataset.set(value: UInt16(257).bigEndian, forTagName: "CommandDataSetType")

        let commandGroupLength = pdvDataset.toData().count
        _ = pdvDataset.set(value: UInt32(commandGroupLength).bigEndian, forTagName: "CommandGroupLength")
        
        var pdvData = Data()
        let pdvLength = commandGroupLength + 14
        pdvData.append(uint32: UInt32(pdvLength), bigEndian: true)
        pdvData.append(uint8: association.contextID, bigEndian: true) // Context
        pdvData.append(byte: 0x03) // Flags
        pdvData.append(pdvDataset.toData())
        
        let pduLength = UInt32(pdvLength + 4)
        data.append(uint8: self.pduType.rawValue, bigEndian: true)
        data.append(byte: 0x00) // reserved
        data.append(uint32: pduLength, bigEndian: true)
        data.append(pdvData)
        
        return data
    }
    
    
    public func cfindRQ(queryDataset:DataSet, rootLevelSopClassUID:String = "1.2.840.10008.5.1.4.1.2.2.1") -> Data {
        var data = Data()
        
        let pdvDataset = DataSet()
        _ = pdvDataset.set(value: "C-FIND-RQ", forTagName: "CommandField")
        _ = pdvDataset.set(value: rootLevelSopClassUID as Any, forTagName: "AffectedSOPInstanceUID")
        _ = pdvDataset.set(value: "1", forTagName: "MessageID")
        _ = pdvDataset.set(value: "2", forTagName: "Priority")
        _ = pdvDataset.set(value: "2", forTagName: "CommandDataSetType")
        
        let commandGroupLength = pdvDataset.toData().count
        _ = pdvDataset.set(value: commandGroupLength, forTagName: "CommandGroupLength")
        
        var pdvData = Data()
        let pdvLength = pdvDataset.toData().count + 2
        pdvData.append(uint32: UInt32(pdvLength), bigEndian: true)
        pdvData.append(byte: 0x01) // Context
        pdvData.append(byte: 0x03) // Flags
        pdvData.append(pdvDataset.toData())
        
        let pduLength = UInt32(pdvLength + 4)
        data.append(uint8: self.pduType.rawValue, bigEndian: true)
        data.append(byte: 0x00) // reserved
        data.append(uint32: pduLength, bigEndian: true)
        data.append(pdvData)
        
//        var queryLength = queryDataset.toData().count + 4
//        print("queryLength: \(queryLength)")
//        data.append(Data(repeating: self.pduType.rawValue, count: 1))
//        data.append(Data(repeating: 0x00, count: 1)) // reserved
//        data.append(unsignedInteger: UInt32(queryLength), bigEndian: true)
//        data.append(queryDataset.toData())
        
        return data
    }
    

    
    
//    private func decodeAssocAC(data:Data) -> Bool {
//        SwiftyBeaver.info("==================== RECEIVE A-ASSOCIATE-AC ====================")
//        SwiftyBeaver.debug("A-ASSOCIATE-AC DATA : \(data.toHex().separate(every: 2, with: " "))")
//        
//        // get full length
//        var offset = 2
//        //let length = data.subdata(in: offset..<6).toInt32(byteOrder: .BigEndian)
//        offset = 6
//        
//        // check protocol version
//        let protocolVersion = data.subdata(in: offset..<offset+2).toInt16(byteOrder: .BigEndian)
//        if Int(protocolVersion) != self.association?.protocolVersion {
//            SwiftyBeaver.error("WARN: Wrong protocol version")
//            return false
//        }
//        offset = 8
//        
//        // TODO: Called / Calling AE Titles
//        offset = 74
//        
//        // parse app context
//        var subdata = data.subdata(in: offset..<data.count)
//        guard let applicationContext = ApplicationContext(data: subdata) else {
//            SwiftyBeaver.error("Missing application context. Abort.")
//            return false
//        }
//        
//        SwiftyBeaver.info("  -> Application Context Name: \(applicationContext.applicationContextName)")
//        
//        // parse presentation context
//        SwiftyBeaver.info("  -> Presentation Contexts:")
//        offset = Int(applicationContext.length) + 8
//        subdata = subdata.subdata(in: offset..<subdata.count)
//        offset = 0
//        
//        guard let presentationContext = PresentationContext(data: subdata) else {
//            SwiftyBeaver.error("Missing presentation context. Abort.")
//            return false
//        }
//        
//        if presentationContext.contextID != self.association?.contextID {
//            SwiftyBeaver.error("Wrong context ID. Abort.")
//            return false
//        }
//        
//        if let ats = presentationContext.acceptedTransferSyntax {
//            if let assoc = self.association {
//                if !assoc.checkTransferSyntax(ats) {
//                    SwiftyBeaver.error("Unsupported accepted Transfer Syntax. Abort.")
//                    return false
//                }
//            }
//            self.association?.acceptedTransferSyntax = ats
//        }
//        
//        SwiftyBeaver.info("    -> Context ID: \(presentationContext.contextID ?? 0)")
//        SwiftyBeaver.info("      -> Accepted Transfer Syntax(es): \(presentationContext.acceptedTransferSyntax ?? "")")
//        
//        // read user info
//        SwiftyBeaver.info("  -> User Informations:")
//        offset = Int(presentationContext.length()) + 4
//        subdata = subdata.subdata(in: offset..<subdata.count)
//        
//        guard let userInfo = UserInfo(data: subdata) else {
//            SwiftyBeaver.warning("No user information values provided. Abort")
//            return false
//        }
//        
//        self.association?.maxPDULength = userInfo.maxPDULength
//        self.association?.remoteImplementationUID = userInfo.implementationUID
//        self.association?.remoteImplementationVersion = userInfo.implementationVersion
//        
//        SwiftyBeaver.info("    -> Remote Max PDU: \(self.association!.maxPDULength)")
//        SwiftyBeaver.info("    -> Implementation class UID: \(self.association!.remoteImplementationUID ?? "")")
//        SwiftyBeaver.info("    -> Implementation version: \(self.association!.remoteImplementationVersion ?? "")")
//    
//        self.association?.associationAccepted = true
//        
//        SwiftyBeaver.info(" ")
//        
//        return true
//    }
    
    
    private func decodeAssocRJ(data:Data) -> Bool {
        print("decodeAssocRJ")
        return false
    }
    
    
    private func decodeReleaseRP(data:Data) -> Bool {
        return false
    }
}
