//
//  DicomAssociation.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 20/03/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation
import SwiftyBeaver
import Socket

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

extension String {
    func separate(every stride: Int = 4, with separator: Character = " ") -> String {
        return String(enumerated().map { $0 > 0 && $0 % stride == 0 ? [separator, $1] : [$1]}.joined())
    }
}


public class DicomAssociation : NSObject {
    private static var lastContextID:UInt8 = 1
    
    public var callingAET:DicomEntity!
    public var calledAET:DicomEntity!
    
    public var maxPDULength:Int = 16384
    public var associationAccepted:Bool = false
    public var sop:String = "1.2.840.10008.1.1"
    
    public var acceptedTransferSyntax:String?
    public var remoteMaxPDULength:Int = 0
    
    private var socket:Socket!
    private var protocolVersion:Int = 1
    private var contextID:UInt8 = 1
    
    private enum AssociationCommand: UInt8 {
        case associationRQ  = 0x01
        case associationAC  = 0x02
        case associationRJ  = 0x03
        case dataTF         = 0x04
        case releaseRQ      = 0x05
        case releaseRP      = 0x06
        case abort          = 0x07
    }
    
    
    
    
    public init(_ callingAET:DicomEntity, calledAET:DicomEntity, socket:Socket) {
        self.calledAET = calledAET
        self.callingAET = callingAET
        self.socket = socket

        initLogger()
    }
    
    
    public func request(sop:String, completion: (_ accepted:Bool) -> Void) {
        self.sop = sop
        self.contextID = self.getNextContextID()
        
        var data = Data()
        let appContext = self.applicationContext()
        let presentationContext = self.presentationContext(sop: sop)
        
        data.append(self.associationRQ(appContext:appContext, presentationContext:presentationContext))
        data.append(appContext)
        data.append(presentationContext)
        data.append(self.userInfo())
        
        SwiftyBeaver.info("==================== SEND A-ASSOCIATE-RQ ====================")
        SwiftyBeaver.debug("A-ASSOCIATE-RQ DATA : \(data.toHex().separate(every: 2, with: " "))")
        SwiftyBeaver.info("  -> Application Context Name: \(DicomConstants.applicationContextName)")
        SwiftyBeaver.info("  -> Called Application Entity: \(calledAET.fullname())")
        SwiftyBeaver.info("  -> Calling Application Entity: \(callingAET.fullname())")
        SwiftyBeaver.info("  -> Local Max PDU: \(self.maxPDULength)")
        
        SwiftyBeaver.info("  -> Presentation Contexts:")
        SwiftyBeaver.info("    -> Context ID: \(self.contextID)")
        SwiftyBeaver.info("      -> Abstract Syntax: \(self.sop)")
        SwiftyBeaver.info("      -> Proposed Transfer Syntax(es): \(DicomConstants.transfersSyntaxes)")
        
        SwiftyBeaver.info("  -> User Informations:")
        SwiftyBeaver.info("    -> Local Max PDU: \(self.maxPDULength)")
        
        do {
            try socket.write(from: data)
            
            var readData = Data()
            try _ = socket.read(into: &readData)
            
            self.readAssociationResponse(readData)
            
        } catch {
            completion(false)
        }
        
        return completion(true)
    }
    
    
    public func close() {
        if self.socket.isConnected && self.associationAccepted {
            do {
                // send A-Release-RQ message
                let data = self.releaseRQ()
                
                SwiftyBeaver.info("==================== SEND A-RELEASE-RQ ====================")
                SwiftyBeaver.debug("A-RELEASE-RQ DATA : \(data.toHex().separate(every: 2, with: " "))")
                
                try socket.write(from: data)
                var readData = Data()
                try _ = socket.read(into: &readData)
            } catch let e {
                print(e)
            }
        }
    }
    
    
    public func abort() {
        do {
            // send A-Release-RQ message
            let data = self.abortRQ()
            
            SwiftyBeaver.info("==================== SEND A-ABORT ====================")
            SwiftyBeaver.debug("A-ABORT DATA : \(data.toHex().separate(every: 2, with: " "))")
            
            try socket.write(from: data)
            var readData = Data()
            try _ = socket.read(into: &readData)
            
            
            
        } catch let e {
            print(e)
        }
    }

    
    public func write(_ data:Data) {
//        var offset = 0
//        
//        while offset <= data.count-1 && socket.isConnected {
//            var allData = Data()
//            
//            var itemData = Data()
//            var itemLength = UInt32(self.remoteMaxPDULength).bigEndian
//            var contextID = self.contextID.bigEndian
//            print(data.count)
//            print(offset+self.remoteMaxPDULength)
//            
//            var limit = offset + self.remoteMaxPDULength
//            if offset+self.remoteMaxPDULength > data.count-1 {
//                limit = data.count - 1
//            }
//            
//            let dataFragment = data.subdata(in: offset..<limit)
//            itemData.append(UnsafeBufferPointer(start: &itemLength, count: 1)) // Length
//            itemData.append(UnsafeBufferPointer(start: &contextID, count: 1)) // Length
//            itemData.append(Data(repeating: 0x00, count: 1)) // 00H
//            itemData.append(dataFragment)
//            
//            offset += self.remoteMaxPDULength
//            
//            var length = Int32(self.remoteMaxPDULength).bigEndian
//            allData.append(Data(repeating: 0x04, count: 1)) // 04H DATA
//            allData.append(Data(repeating: 0x00, count: 1)) // 00H
//            allData.append(UnsafeBufferPointer(start: &length, count: 1)) // Length
//            allData.append(itemData)
//            
//            do {
//                // send P-Data-TF message
//                try socket.write(from: allData)
//                
//                // close the association
//                self.close()
//                
//            } catch let e {
//                print(e)
//            }
//        }
    }
    
    
    
    private func applicationContext() -> Data {
        var apData = Data()
        apData.append(Data(repeating: 0x10, count: 1)) // 10H
        apData.append(Data(repeating: 0x00, count: 1)) // 00H
        let appContext = DicomConstants.applicationContextName.data(using: .utf8)
        var appContextLen = UInt16(appContext!.count).bigEndian
        apData.append(UnsafeBufferPointer(start: &appContextLen, count: 1))  // Length 11H
        apData.append(appContext!)
        
        return apData
    }
    
    
    private func presentationContext(sop:String) -> Data {
        // ABSTRACT SYNTAX Data
        var asData = Data()
        var asLength = UInt16(sop.data(using: .utf8)!.count).bigEndian
        asData.append(Data(repeating: 0x30, count: 1)) // 30H
        asData.append(Data(repeating: 0x00, count: 1)) // 00H
        asData.append(UnsafeBufferPointer(start: &asLength, count: 1))
        asData.append(sop.data(using: .utf8)!)
        
        // TRANSFER SYNTAXES Data
        var tsData = Data()
        for ts in DicomConstants.transfersSyntaxes {
            var tsLength = UInt16(ts.data(using: .utf8)!.count).bigEndian
            tsData.append(Data(repeating: 0x40, count: 1)) // 40H
            tsData.append(Data(repeating: 0x00, count: 1)) // 00H
            tsData.append(UnsafeBufferPointer(start: &tsLength, count: 1))
            tsData.append(ts.data(using: .utf8)!)
        }
        
        // Presentation Context
        var pcData = Data()
        pcData.append(Data(repeating: 0x20, count: 1)) // 20H
        pcData.append(Data(repeating: 0x00, count: 1)) // 00H
        
        var pcLength = UInt16(4 + asData.count + tsData.count).bigEndian
        pcData.append(UnsafeBufferPointer(start: &pcLength, count: 1))  // Presentation Context Length
        
        var contextID = self.contextID.bigEndian
        pcData.append(UnsafeBufferPointer(start: &contextID, count: 1))  // Presentation Context ID
        pcData.append(Data(bytes: [0x00, 0x00, 0x00])) // 00H x 3 RESERVED
        pcData.append(asData)
        pcData.append(tsData)
        
        return pcData
    }
    
    
    private func associationRQ(appContext:Data, presentationContext:Data) -> Data {
        var data = Data()
        
        let apData = appContext
        let pcData = presentationContext
        let uiData = self.userInfo()
        
        var length = UInt32(2 + 2 + 16 + 16 + 32 + apData.count + pcData.count + uiData.count).bigEndian
        data.append(Data(repeating: 0x01, count: 1)) // 01H
        data.append(Data(repeating: 0x00, count: 1)) // 00H
        data.append(UnsafeBufferPointer(start: &length, count: 1))  // Length
        data.append(Data(bytes: [0x00, 0x01])) // Protocol version
        data.append(Data(repeating: 0x00, count: 2)) // 0000H
        data.append(calledAET.paddedTitleData()!) // Called AET Title
        data.append(callingAET.paddedTitleData()!) // Calling AET Title
        data.append(Data(repeating: 0x00, count: 32)) // 00H
        
        return data
    }
    
    
    private func userInfo() -> Data {
        var data = Data()
        
        // Max PDU length item
        var pduData = Data()
        var itemLength = UInt16(4).bigEndian
        var pduLength = UInt32(self.maxPDULength).bigEndian
        pduData.append(Data(repeating: 0x51, count: 1)) // 50H
        pduData.append(Data(repeating: 0x00, count: 1)) // 00H
        pduData.append(UnsafeBufferPointer(start: &itemLength, count: 1)) // Length
        pduData.append(UnsafeBufferPointer(start: &pduLength, count: 1)) // PDU Length
        
        // Items
        var length = UInt16(pduData.count).bigEndian
        data.append(Data(repeating: 0x50, count: 1)) // 50H
        data.append(Data(repeating: 0x00, count: 1)) // 00H
        data.append(UnsafeBufferPointer(start: &length, count: 1)) // Length
        data.append(pduData) // Items
        
        //print(data.toHex())//
        
        return data
    }
    
    
    private func releaseRQ() -> Data {
        // PDU header
        var data = Data()
        
        var length = UInt32(4).bigEndian
        data.append(Data(repeating: 0x05, count: 1)) // 05H
        data.append(Data(repeating: 0x00, count: 1)) // 00H
        data.append(UnsafeBufferPointer(start: &length, count: 1)) // 000000040H Length
        data.append(Data(repeating: 0x00, count: 4)) // 00000000H
        
        return data
    }
    
    
    private func abortRQ() -> Data {
        // PDU header
        var data = Data()
        
        var length = UInt32(4).bigEndian
        data.append(Data(repeating: 0x07, count: 1)) // 07H
        data.append(Data(repeating: 0x00, count: 1)) // 00H
        data.append(UnsafeBufferPointer(start: &length, count: 1)) // 000000040H Length
        data.append(Data(repeating: 0x00, count: 4)) // 00000000H
        
        return data
    }
    
    
    private func readAssociationResponse(_ data:Data) {
        if let command = data.first {
            if command == AssociationCommand.associationAC.rawValue {
                SwiftyBeaver.info("==================== RECEIVE A-ASSOCIATE-AC ====================")
                SwiftyBeaver.debug("A-ASSOCIATE-AC DATA : \(data.toHex().separate(every: 2, with: " "))")
                
                // get full length
                let length = data.subdata(in: 2..<6).toInt32(byteOrder: .BigEndian)
                
                
                // check protocol version
                let protocolVersion = data.subdata(in: 6..<8).toInt16(byteOrder: .BigEndian)
                if Int(protocolVersion) != self.protocolVersion {
                    SwiftyBeaver.error("WARN: Wrong protocol version")
                }
                
                
                
                
                // parse app context
                let acPcUiData = data.subdata(in: 74..<Int(length))
                let acType = acPcUiData.first
                if acType != 0x10 {
                    self.associationAccepted = false
                    SwiftyBeaver.error("Missing application context. Abort.")
                    self.abort()
                    return
                }
                
                let acLength = acPcUiData.subdata(in: 2..<4).toInt16(byteOrder: .BigEndian)
                let applicationContextData = acPcUiData.subdata(in: 4..<Int(acLength))
                let applicationContext = String(bytes: applicationContextData, encoding: .utf8)
                SwiftyBeaver.info("  -> Application Context Name: \(applicationContext ?? "")")
                
                
                // parse presentation context
                SwiftyBeaver.info("  -> Presentation Contexts:")
                var offset = Int(acLength) + 4
                let pcType = acPcUiData.subdata(in: offset..<offset+1).toInt8(byteOrder: .BigEndian)
                if pcType != 0x21 {
                    self.associationAccepted = false
                    SwiftyBeaver.error("Missing presentation context. Abort.")
                    self.abort()
                    return
                }
                //let pcLength = acPcUiData.subdata(in: offset+2..<offset+4).toInt16(byteOrder: .BigEndian)
                let pcContextID = acPcUiData.subdata(in: offset+4..<offset+6).toInt8(byteOrder: .BigEndian)
                if self.contextID != UInt8(pcContextID) {
                    self.associationAccepted = false
                    SwiftyBeaver.error("Wrong context ID. Abort.")
                    self.abort()
                    return
                }
                SwiftyBeaver.info("    -> Context ID: \(pcContextID)")
                offset += 8

                
                
                // parse & check transfer syntax
                let tsData = acPcUiData.subdata(in: offset..<acPcUiData.count)
                let tsLength = tsData.subdata(in: 2..<4).toInt16(byteOrder: .BigEndian)
                let transferSyntaxData = tsData.subdata(in: 4..<Int(tsLength)+4)
                let transferSyntax = String(bytes: transferSyntaxData, encoding: .utf8)
                
                SwiftyBeaver.info("      -> Accepted Transfer Syntax(es): \(transferSyntax ?? "")")
                
                var okSyntax = false
                for ts in DicomConstants.transfersSyntaxes {
                    if ts == transferSyntax {
                        okSyntax = true
                        break
                    }
                }
                
                if !okSyntax {
                    self.associationAccepted = false
                    SwiftyBeaver.error("Transfer syntax missmatch. Abort.")
                    self.abort()
                    return
                }
                
                self.acceptedTransferSyntax = transferSyntax
                self.associationAccepted = true
                
                
                // read user info
                offset = Int(tsLength)+4
                let uiData = tsData.subdata(in: offset..<tsData.count)
                let uiType = uiData.first
                if uiType == 0x50 {
                    SwiftyBeaver.info("  -> User Informations:")
                    let uiLength = tsData.subdata(in: offset+2..<offset+4).toInt16(byteOrder: .BigEndian)
                    let uiItemData = tsData.subdata(in: offset+4..<Int(uiLength))
                    
                    offset = 0
                    while offset < uiItemData.count-1 {
                        // read type
                        let uiItemType = uiItemData.subdata(in: offset..<offset+1).toInt8(byteOrder: .BigEndian)
                        let uiItemLength = uiItemData.subdata(in: offset+2..<offset+4).toInt16(byteOrder: .BigEndian)
                        offset += 4
                        
                        if uiItemType == 0x51 {
                            let maxPDU = uiItemData.subdata(in: offset..<offset+Int(uiItemLength)).toInt32(byteOrder: .BigEndian)
                            self.remoteMaxPDULength = Int(maxPDU)
                            SwiftyBeaver.info("    -> Remote Max PDU: \(self.remoteMaxPDULength)")
                        }
                        else if uiItemType == 0x52 {
                            //print("Implementation class UID")
                        }
                        else if uiItemType == 0x55 {
                            //print("Implementation version")
                        }
                        else {
                            
                        }
                        
                        offset += Int(uiItemLength)
                    }
                }
                SwiftyBeaver.info(" ")
            }
            else if command == AssociationCommand.associationRJ.rawValue {
                SwiftyBeaver.error("Association rejected")
            }
        }
    }
    
    
    private func getNextContextID() -> UInt8 {
        if DicomAssociation.lastContextID == 255 {
            DicomAssociation.lastContextID = 1
        } else {
            DicomAssociation.lastContextID += 1
        }
        
        return DicomAssociation.lastContextID
    }
}
