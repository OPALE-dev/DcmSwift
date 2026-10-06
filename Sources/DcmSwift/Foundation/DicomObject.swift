//
//  DicomObject.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 30/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation

public protocol DicomObjectProtocol {
    var description: String { get }
    func toData(vrMethod inVrMethod:VRMethod, byteOrder inByteOrder:ByteOrder) -> Data
    func toData(transferSyntax:TransferSyntax) -> Data
    func toXML(_ pretty: Bool?) -> String
    func toJSONArray() -> Any
    func toJSON(_ pretty: Bool?) -> String
}

public class DicomObject: CustomStringConvertible, DicomObjectProtocol {
    public var description: String { return "" }
    
    public func toData(vrMethod inVrMethod:VRMethod = .Explicit, byteOrder inByteOrder:ByteOrder = .LittleEndian) -> Data {
        return Data()
    }
    
    public func toData(transferSyntax:TransferSyntax) -> Data {
        return Data()
    }
    
    public func toXML(_ pretty: Bool? = true) -> String {
        return ""
    }
    
    public func toJSONArray() -> Any {
        return [:]
    }
    
    public func toJSON(_ pretty: Bool? = true) -> String {
        var options: JSONSerialization.WritingOptions = []
        
        if pretty == true {
            options = [.prettyPrinted]
        }
        
        let data = try! JSONSerialization.data(withJSONObject: self.toJSONArray(), options: options)
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        
        return ""
    }
}
