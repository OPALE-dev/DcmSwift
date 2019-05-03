//
//  ApplicationContext.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 02/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation


public class ApplicationContext {
    var applicationContextName:String = DicomConstants.applicationContextName
    
    
    public init(applicationContextName:String = DicomConstants.applicationContextName) {
        self.applicationContextName = applicationContextName
    }
    
    
    public init?(data:Data) {
        let acType = data.first
        
        if acType != ItemType.applicationContext.rawValue {
            return nil
        }
        
        let acLength = data.subdata(in: 2..<4).toInt16(byteOrder: .BigEndian)
        let applicationContextData = data.subdata(in: 4..<Int(acLength))
        let applicationContextName = String(bytes: applicationContextData, encoding: .utf8)
        
        self.applicationContextName = applicationContextName ?? DicomConstants.applicationContextName
    }
    
    
    public var length:Int {
        return self.applicationContextName.count
    }
    
    
    public func data() -> Data {
        var data = Data()
        let appContext = self.applicationContextName.data(using: .utf8)
        
        data.append(uint8: ItemType.applicationContext.rawValue, bigEndian: true)
        data.append(byte: 0x00) // reserved        
        data.append(uint16: UInt16(self.length), bigEndian: true)
        data.append(appContext!)
        
        return data
    }
}
