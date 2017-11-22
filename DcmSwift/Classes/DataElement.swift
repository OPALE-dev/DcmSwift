//
//  DataElement.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 17/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Foundation


public class DataValue {
    public var value:String    = ""
    public var index:Int       = 0
    
    init(_ val:String, atIndex index:Int = 0) {
        self.value = val
        self.index = index
    }
}


public class DataElement : DicomObject {
    public var startOffset:Int              = 0
    public var dataOffset:Int               = 0
    public var endOffset:Int                = 0
    public var length:Int                   = 0
    
    public var tag:DataTag
    public var data:Data!
    public var vr:DicomSpec.VR              = DicomSpec.VR.UN
    public var vrMethod:DicomSpec.VRMethod  = .Explicit
    public var byteOrder:DicomSpec.ByteOrder = .LittleEndian
    
    private var dataValues:[DataValue] = []
    
    public var group:String     { return self.tag.group }
    
    public var element:String   { return self.tag.element }
    
    public var name:String      { return self.tag.name }
    
    
    public var value:Any {
        if self.data == nil {
            return ""
        }
        
        if self.tag.code == "7fe00010" {
            return ""
        }
        
        if self.vr == .UL ||
           self.vr == .SL {
            return self.data.toInt32(byteOrder: self.byteOrder)
        }
        else if self.vr == .US ||
                self.vr == .SS {
            return self.data.toInt16(byteOrder: self.byteOrder)
        }
        else if self.vr == .FL {
            return self.data.toFloat32(byteOrder: self.byteOrder)
        }
        else if self.vr == .FD {
            return self.data.toFloat64(byteOrder: self.byteOrder)
        }
        else if self.vr == .UI ||
                self.vr == .SH ||
                self.vr == .AS ||
                self.vr == .CS ||
                self.vr == .LO ||
                self.vr == .ST ||
                self.vr == .PN ||
                self.vr == .DS ||
                self.vr == .DA ||
                self.vr == .DS ||
                self.vr == .DT ||
                self.vr == .IS ||
                self.vr == .LT ||
                self.vr == .TM ||
                self.vr == .AE {
            return self.data.toString()
        }
        else if self.vr == .AT ||
                self.vr == .OB ||
                self.vr == .OW {
            return self.data
        }
        else if self.vr == .SQ {
            return ""
        }
        
        return self.data
    }
    
    

    public var isMultiple:Bool  {
        if let string = self.value as? String {
            if string.range(of:"\\") != nil {
                return true
            }
        }
        return false
    }
    
    
    public var values:[DataValue] {
        if self.isMultiple {
            if self.dataValues.count == 0 {
                if let string = self.value as? String {
                    let slice = string.components(separatedBy: "\\")
                    var index = 0
                    for string in slice {
                        self.dataValues.append(DataValue(string, atIndex:index))
                        index += 1
                    }
                }
            }
        }
        return self.dataValues
    }
    
    
    
    init(withTag tag:DataTag) {
        self.tag = tag
    }
    
    
    
    public func tagCode() -> String {
        return "\(self.group)\(self.element)"
    }
    
    
    
    override public var description: String {
        return "\(self.startOffset) \(self.tag) \(self.vr)[\(self.length)] \t \(self.name) \(self.dataOffset) [\(self.value)] \(self.endOffset)"
    }
}
