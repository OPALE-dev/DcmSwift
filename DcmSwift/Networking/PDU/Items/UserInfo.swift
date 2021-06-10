//
//  UserInfo.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 02/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

public class UserInfo {
    public var implementationUID:String = DicomConstants.implementationUID
    public var implementationVersion:String = DicomConstants.implementationVersion
    public var maxPDULength:Int = 16384
    
    public init(implementationVersion:String = DicomConstants.implementationVersion, implementationUID:String = DicomConstants.implementationUID, maxPDULength:Int = 16384) {
        self.implementationVersion = implementationVersion
        self.implementationUID = implementationUID
        self.maxPDULength = maxPDULength
    }
    
    
    public init?(data:Data) {
        let uiType = data.first //.subdata(in: offset..<offset+1).toInt18(byteOrder: .BigEndian)
        
        if uiType == ItemType.userInfo.rawValue {
            //Logger.info("  -> User Informations:")
            let uiItemData = data.subdata(in: 4..<data.count)
            
            var offset = 0
            while offset < uiItemData.count-1 {
                // read type
                let uiItemType = uiItemData.subdata(in: offset..<offset+1).toInt8(byteOrder: .BigEndian)
                let uiItemLength = uiItemData.subdata(in: offset+2..<offset+4).toInt16(byteOrder: .BigEndian)
                offset += 4
                
                if uiItemType == ItemType.maxPduLength.rawValue {
                    let maxPDU = uiItemData.subdata(in: offset..<offset+Int(uiItemLength)).toInt32(byteOrder: .BigEndian)
                    self.maxPDULength = Int(maxPDU)
                    //Logger.info("    -> Remote Max PDU: \(self.association!.maxPDULength)")
                }
                else if uiItemType == ItemType.implClassUID.rawValue {
                    let impClasslUID = uiItemData.subdata(in: offset..<offset+Int(uiItemLength)).toString()
                    self.implementationUID = impClasslUID
                    //Logger.info("    -> Implementation class UID: \(self.association!.remoteImplementationUID ?? "")")
                }
                else if uiItemType == ItemType.implVersionName.rawValue {
                    let impVersion = uiItemData.subdata(in: offset..<offset+Int(uiItemLength)).toString()
                    self.implementationVersion = impVersion
                    //Logger.info("    -> Implementation version: \(self.association!.remoteImplementationVersion ?? "")")
                    
                }
                
                offset += Int(uiItemLength)
            }
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
