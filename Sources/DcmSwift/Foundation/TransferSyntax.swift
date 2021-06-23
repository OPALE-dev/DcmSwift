//
//  File.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 23/06/2021.
//  Copyright © 2021 Read-Write.fr. All rights reserved.
//

import Foundation


public class TransferSyntax: CustomStringConvertible, Equatable {
    public var tsUID:String                     = "1.2.840.10008.1.2.1"
    public var tsName:String                    = DicomConstants.explicitVRLittleEndian
    
    var vrMethod:DicomConstants.VRMethod        = .Explicit
    var byteOrder:DicomConstants.ByteOrder      = .LittleEndian
    
    public init?(transferSyntax:String) {
        if !DicomSpec.shared.isSupported(transferSyntax: transferSyntax) {
            return nil
        }
        
        tsUID   = transferSyntax
        tsName  = DicomSpec.shared.nameForUID(withUID: tsUID)
        
        if transferSyntax == DicomConstants.implicitVRLittleEndian {
            vrMethod    = .Implicit
            byteOrder   = .LittleEndian
        }
    }
    
    public static func == (lhs: TransferSyntax, rhs: TransferSyntax) -> Bool {
        return lhs.tsUID == rhs.tsUID
    }
    
    public static func == (lhs: TransferSyntax, rhs: String) -> Bool {
        return lhs.tsUID == rhs
    }
    
    public var description: String {
        return "\(tsName) (\(tsUID))"
    }
}
