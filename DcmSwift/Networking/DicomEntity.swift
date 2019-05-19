//
//  DicomEntity.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 20/03/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation


public class DicomEntity : Codable, CustomStringConvertible {
    /**
     A string description of the DICOM object
     */
    public var description: String { return self.fullname() }
    
    public var title:String
    public var hostname:String
    public var port:Int
    
    public init(title:String, hostname:String, port:Int) {
        self.title      = title
        self.hostname   = hostname
        self.port       = port
    }
    
    public func paddedTitleData() -> Data? {
        var data = self.title.data(using: .utf8)
        
        if data!.count < 16 {
            data!.append(Data(repeating: 0x00, count: 16-data!.count))
        }
        
        return data
    }
    
    public func fullname() -> String {
        return "\(self.title)@\(self.hostname):\(self.port)"
    }
}
