//
//  ApplicationContext.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 02/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

/**
 Application Context Item Structure
 
 TODO: rewrite with OffsetInputStream
 
 ApplicationContext consists of:
 - item type (10)
 - 1 reserved byte
 - 2 item length
 - application context name
 
 http://dicom.nema.org/dicom/2013/output/chtml/part08/sect_9.3.html#sect_9.3.2.1
 */
public class ApplicationContext {
    var applicationContextName:String = DicomConstants.applicationContextName
    
    
    public init(applicationContextName:String = DicomConstants.applicationContextName) {
        self.applicationContextName = applicationContextName
    }
    
    /// Parse bytes to get Application Context fields
    public init?(data:Data) {
        
        var offset = 0
        let acType = data.first
        offset += 1
        
        if acType != ItemType.applicationContext.rawValue {
            return nil
        }
                    
        offset += 1 // reserved byte
        
        let acLength = data.subdata(in: offset..<offset+2).toInt16(byteOrder: .BigEndian)
        offset += 2
        
        let applicationContextData = data.subdata(in: offset..<Int(acLength))
        if let applicationContextName = String(bytes: applicationContextData, encoding: .utf8) {
            self.applicationContextName = applicationContextName
        }
    }
    
    /// Length of application context name
    public var length:Int {
        return self.applicationContextName.count
    }
    
    /// Builds Application Context bytes as `Data`
    public func data() -> Data {
        var data = Data()
        let appContext = self.applicationContextName.data(using: .utf8)
        
        data.append(uint8: ItemType.applicationContext.rawValue, bigEndian: true)
        data.append(byte: 0x00) // reserved        
        data.append(uint16: UInt16(self.applicationContextName.count), bigEndian: true)
        data.append(appContext!)
        
        return data
    }
}
