//
//  UserInfo.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 02/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 User Information Item Structure
 
 TODO: rewrite with OffsetInputStream
 
 User Information consists of:
 - item type
 - 1 reserved byte
 - 2 item length
 - user data
 
 http://dicom.nema.org/dicom/2013/output/chtml/part08/sect_9.3.html#sect_9.3.3.3
 */
public class UserInfo {
    public var implementationUID:String = DicomConstants.implementationUID
    public var implementationVersion:String = DicomConstants.implementationVersion
    public var maxPDULength:Int = 16384
    
    public init(implementationVersion:String = DicomConstants.implementationVersion, implementationUID:String = DicomConstants.implementationUID, maxPDULength:Int = 16384) {
        self.implementationVersion = implementationVersion
        self.implementationUID = implementationUID
        self.maxPDULength = maxPDULength
    }
    
    /**
     - Remark: Why read max pdu length ? it's only a sub field in user info
     */
    public init(data:Data) throws {
        let stream = OffsetInputStream(data: data)
        
        stream.open()
        
        let itemType = try stream.read(length: 1)// else { return }
        let userInfoItemType = itemType.toUInt8(byteOrder: .BigEndian)
        
        try stream.forward(by: 1)// reserved byte
        
        let itemLength = try stream.read(length: 2)// else { return }
        let userInfoItemLength = itemLength.toInt16(byteOrder: .BigEndian)
        
        switch userInfoItemType {
        case ItemType.maxPduLength.rawValue:
            let maxLengthReceived = try stream.read(length: Int(userInfoItemLength))// else { return }
            self.maxPDULength = Int(maxLengthReceived.toInt32(byteOrder: .BigEndian))
            Logger.verbose("    -> Local  Max PDU: \(DicomConstants.maxPDULength)", "UserInfo")
            Logger.verbose("    -> Remote Max PDU: \(self.maxPDULength)", "UserInfo")
            
        case ItemType.implVersionName.rawValue:
            let implementationVersionName = try stream.read(length: Int(userInfoItemLength))// else { return }
            self.implementationVersion = implementationVersionName.toString()
            
        case ItemType.implClassUID.rawValue:
            let implementationClassUID = try stream.read(length: Int(userInfoItemLength))// else { return }
            self.implementationUID = implementationClassUID.toString()
            
        default:
            Logger.error("Unexpected item type for user info")
        }
    }
    
    
    public func data() -> Data {
        var data = Data()
        
        // Max PDU length item
        var pduData = Data()
        var itemLength = UInt16(4).bigEndian
        var pduLength = UInt32(self.maxPDULength).bigEndian
        pduData.append(Data(repeating: ItemType.maxPduLength.rawValue, count: 1)) // 51H (Max PDU Length)
        pduData.append(Data(repeating: 0x00, count: 1)) // 00H
        pduData.append(UnsafeBufferPointer(start: &itemLength, count: 1)) // Length
        pduData.append(UnsafeBufferPointer(start: &pduLength, count: 1)) // PDU Length
        
        // TODO: Application UID and version
        // Items
        var length = UInt16(pduData.count).bigEndian
        data.append(Data(repeating: ItemType.userInfo.rawValue, count: 1)) // 50H
        data.append(Data(repeating: 0x00, count: 1)) // 00H
        data.append(UnsafeBufferPointer(start: &length, count: 1)) // Length
        data.append(pduData) // Items
        
        return data
    }
}
