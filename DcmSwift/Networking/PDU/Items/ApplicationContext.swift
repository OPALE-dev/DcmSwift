//
//  ApplicationContext.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 02/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation


public class ApplicationContext {
    var applicationContextName:String = DicomConstants.applicationContextName
    
    
    public init(applicationContextName:String = DicomConstants.applicationContextName) {
        self.applicationContextName = applicationContextName
    }
    
    
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
    
    
    public var length:Int {
        return self.applicationContextName.count
    }
    
    
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
