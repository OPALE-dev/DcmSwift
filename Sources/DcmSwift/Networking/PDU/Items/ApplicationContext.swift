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
        let stream = OffsetInputStream(data: data)
                
        stream.open()
        
        let applicationContextType = stream.read(length: 1)?.toUInt8()
        
        if applicationContextType != ItemType.applicationContext.rawValue {
            return nil
        }
        
        stream.forward(by: 1)// reserved byte
        
        guard let length = stream.read(length: 2) else {
            return nil
        }
        
        let applicationContextLength = length.toInt16(byteOrder: .BigEndian)
        
        guard let applicationContextData = stream.read(length: Int(applicationContextLength)) else { return nil }
        
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
