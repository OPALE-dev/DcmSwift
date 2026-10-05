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
    public init?(data:Data) {
        let uiItemData = data
        
        var offset = 0
        while offset + 4 <= uiItemData.count {
            // read type
            let uiItemType = uiItemData[offset]
            let uiItemLength = Int(uiItemData.subdata(in: offset+2..<offset+4).toUInt16(byteOrder: .BigEndian))
            offset += 4
            guard uiItemLength <= uiItemData.count - offset else { return nil }
            let valueData = uiItemData.subdata(in: offset..<offset + uiItemLength)
            
            if uiItemType == ItemType.maxPduLength.rawValue {
                guard uiItemLength == 4 else { return nil }
                self.maxPDULength = Int(valueData.toUInt32(byteOrder: .BigEndian))
                Logger.verbose("    -> Local  Max PDU: \(DicomConstants.maxPDULength)", "UserInfo")
                Logger.verbose("    -> Remote Max PDU: \(self.maxPDULength)", "UserInfo")
            }
            else if uiItemType == ItemType.implClassUID.rawValue {
                self.implementationUID = valueData.toString()
                //Logger.info("    -> Implementation class UID: \(self.association!.remoteImplementationUID ?? "")")
            }
            else if uiItemType == ItemType.implVersionName.rawValue {
                self.implementationVersion = valueData.toString()
                //Logger.info("    -> Implementation version: \(self.association!.remoteImplementationVersion ?? "")")
                
            }
            
            offset += uiItemLength
        }
    }
    
    
    public func data() -> Data {
        var data = Data()
        var items = Data()
        
        // Max PDU length item
        items.append(uint8: ItemType.maxPduLength.rawValue)
        items.append(byte: 0x00)
        items.append(uint16: 4, bigEndian: true)
        items.append(uint32: UInt32(clamping: maxPDULength), bigEndian: true)

        appendSubItem(type: .implClassUID, value: implementationUID, to: &items)
        appendSubItem(type: .implVersionName, value: implementationVersion, to: &items)

        data.append(Data(repeating: ItemType.userInfo.rawValue, count: 1)) // 50H
        data.append(Data(repeating: 0x00, count: 1)) // 00H
        data.append(uint16: UInt16(clamping: items.count), bigEndian: true)
        data.append(items)
        
        return data
    }

    private func appendSubItem(type: ItemType, value: String, to data: inout Data) {
        guard !value.isEmpty, let valueData = value.data(using: .ascii), valueData.count <= Int(UInt16.max) else {
            return
        }
        data.append(uint8: type.rawValue)
        data.append(byte: 0x00)
        data.append(uint16: UInt16(valueData.count), bigEndian: true)
        data.append(valueData)
    }
}
