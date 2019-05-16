//
//  DataElement.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 17/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
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
    
    public var parent:DataElement?
    public var dataset:DataSet?
    public var tag:DataTag
    public var data:Data!
    
    public var vr:DicomConstants.VR                  = DicomConstants.VR.UN
    public var vrMethod:DicomConstants.VRMethod      = .Explicit
    public var byteOrder:DicomConstants.ByteOrder    = .LittleEndian
    
    private var dataValues:[DataValue] = []
    
    public var group:String     { return self.tag.group }
    public var element:String   { return self.tag.element }
    public var name:String      { return self.tag.name }
    
    
    
    init(withTag tag:DataTag, parent:DataElement? = nil) {
        self.tag = tag
        
        if let p = parent {
            self.parent = p
        }
    }
    
    
    init(withTag tag:DataTag, dataset:DataSet, parent:DataElement? = nil) {
        self.dataset    = dataset
        self.tag        = tag
        
        if let p = parent {
            self.parent = p
        }
    }
    
    
    init?(withTagName name:String, dataset:DataSet, parent:DataElement? = nil) {
        if let t = DicomSpec.shared.dataTag(forName: name) {
            self.vr     = DicomSpec.shared.vrForTag(withCode: t.code)
            self.tag    = t
        } else {
            return nil
        }
       
        self.dataset = dataset
        
        if let p = parent {
            self.parent = p
        }
    }
    
    
    public func setValue(_ val:Any) -> Bool {
        var ret = false
        
        if  self.vr == .AT ||
            self.vr == .OB ||
            self.vr == .OW {
            // currently not implemented
            return ret
        }
        
        if self.isMultiple {
            if let string = val as? String {
                self.data       = string.data(using: .utf8)
                self.length     = self.data.count
                self.dataValues = []
                
                let slice = string.components(separatedBy: "\\")
                var index = 0
                
                for string in slice {
                    self.dataValues.append(DataValue(string, atIndex:index))
                    
                    index += 1
                }
                
                ret = true
            }
        } else {
            if let string = val as? String {
                self.data = string.data(using: .utf8)
                self.length = self.data.count
                
                if string.count % 2 != 0 {
                    self.data.append(byte: 0x00)
                    self.length += 1
                }
                
                ret = true
            }
            else if let v = val as? UInt16 {
                self.data = Data()
                self.data.append(uint16: v)
                self.length = self.data.count
                ret = true
            }
            else if let v = val as? UInt32 {
                self.data = Data()
                self.data.append(uint32: v)
                self.length = self.data.count
                ret = true
            }
            else {
                print("not supported yet")
            }
            
        }
        
        self.recalculateParentsLength()

        return ret
    }
    

    
    
    
    public var value:Any {
        if self.data == nil || self.data.count == 0 {
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
                self.vr == .DS ||
                self.vr == .IS ||
                self.vr == .LT ||
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
        else if self.vr == .DA {
            if let date = Date(dicomDate: self.data.toString()) {
                return date
            }
        }
        else if self.vr == .DT {
            if let date = Date(dicomDateTime: self.data.toString()) {
                return date
            }
        }
        else if self.vr == .TM {
            if let date = Date(dicomTime: self.data.toString()) {
                return date
            }
        }
        
        return self.data
    }
    
    
    public var isEditable:Bool  {
        if let ds = self.dataset {
            if ds.isCorrupted {
                return false
            }
        }
        
        if self.element == "0000" {
            return false
        }
        
        if self.tagCode() == "7fe00010" {
            return false
        }
        
        if  self.vr == .AT ||
            self.vr == .OB ||
            self.vr == .OW {
            return false
        }
        return true
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
    
    
    public override func toXML() -> String {
        var xml = "<DicomAttribute Tag=\"\(self.tagCode())\" VR=\"\(self.vr)\" Keyword=\"\(self.name)\">"
        if self.isMultiple {
            for v in self.values {
                xml += "<Value number=\"\(v.index+1)\">\(v.value)</Value>"
            }
        } else {
            xml += "<Value number=\"\(1)\">\(self.value)</Value>"
        }
        xml += "</DicomAttribute>"
        return xml
    }
    
    
    
    public func tagCode() -> String {
        return "\(self.group)\(self.element)"
    }
    
    
    
    override public var description: String {
        return "\(self.startOffset) \(self.tag) \(self.vr)[\(self.length)] \t \(self.name) \(self.dataOffset) [\(self.value)] \(self.endOffset)"
    }
    
    
    
    public override func toData(vrMethod inVrMethod:DicomConstants.VRMethod = .Explicit, byteOrder inByteOrder:DicomConstants.ByteOrder = .LittleEndian) -> Data {
        var data = Data()
        
        // write tag code
        data.append(self.tag.data(withByteOrder: inByteOrder))
        
        // write VR (only explicit)
        if inVrMethod == .Explicit  {
            let vrString = "\(self.vr)"
            let vrData = vrString.data(using: .ascii)
            data.append(vrData!)
            
            if self.vr == .SQ {
                data.append(Data(repeating: 0x00, count: 2))
            }
            else if self.vr == .OB ||
                self.vr == .OW ||
                self.vr == .OF ||
                self.vr == .SQ ||
                self.vr == .UT ||
                self.vr == .UN {
                data.append(Data(repeating: 0x00, count: 2))
            }
        }
        
        
        // write length
        if self.vr == .SQ {
            var intLength = UInt32(self.length)
            let lengthData = Data(bytes: &intLength, count: 4)
            data.append(lengthData)
        }
        else if self.vr == .OB ||
            self.vr == .OW ||
            self.vr == .OF ||
            self.vr == .UT ||
            self.vr == .UN {
            if self.length >= 0 {
                let intLength = UInt32(self.length)
                var convertedNumber = inByteOrder == .LittleEndian ?
                    intLength.littleEndian : intLength.bigEndian
                
                let lengthData = Data(bytes: &convertedNumber, count: 4)
                data.append(lengthData)
            }
                // negative length indicate sequence here
            else if self.length == -1 {
                // if OB/OW is a Pixel Sequence
                if let _ = self as? PixelSequence {
                    //print(pixelSequence)
                    data.append(Data(repeating: 0xff, count: 4))
                }
            }
        }
        else {
            if inVrMethod == .Explicit {
                // we only take care of endianneess with Explicit
                let intLength = UInt16(self.length)
                var convertedNumber = inByteOrder == .LittleEndian ?
                    intLength.littleEndian : intLength.bigEndian
                
                withUnsafePointer(to: &convertedNumber) {
                    data.append(UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self), count: 2)
                }
            }
            else if inVrMethod == .Implicit {
                var intLength = UInt32(self.length)
                let lengthData = Data(bytes: &intLength, count: 4)
                data.append(lengthData)
            }
        }
        
        
        // write value
        if  self.vr == .UL {
            data.append(self.data)
        }
        else if self.vr == .OB {
            //print("OB \(type(of: self))")
            if self is PixelSequence {
                let pixelSequence = self as! PixelSequence
                //print("PixelSequence")
                data.append(pixelSequence.toData(vrMethod: inVrMethod, byteOrder: inByteOrder))
            } else {
                if self.data != nil {
                    data.append(self.data)
                }
            }
        }
        else if self.vr == .OW {
            if let pixelSequence = self as? PixelSequence {
                data.append(pixelSequence.toData(vrMethod: inVrMethod, byteOrder: inByteOrder))
            } else {
                if self.data != nil {
                    data.append(self.data)
                }
            }
        }
        else if self.vr == .UI {
            data.append(self.data)
        }
        else if self.vr == .FL {
            data.append(self.data)
        }
        else if self.vr == .FD {
            data.append(self.data)
        }
        else if self.vr == .SL {
            data.append(self.data)
        }
        else if self.vr == .SS {
            data.append(self.data)
        }
        else if self.vr == .US {
            if self.data != nil {
                data.append(self.data)
            }
        }
        else if self.vr == .SQ {
            if let sequence = self as? DataSequence {
                data.append(sequence.toData())
            }
        }
        else if self.vr == .SH ||
            self.vr == .AS ||
            self.vr == .CS ||
            self.vr == .DS ||
            self.vr == .LO ||
            self.vr == .LT ||
            self.vr == .ST ||
            self.vr == .OD ||
            self.vr == .OF ||
            self.vr == .AE ||
            self.vr == .UT ||
            self.vr == .IS ||
            self.vr == .PN ||
            self.vr == .DA ||
            self.vr == .DT ||
            self.vr == .UN ||
            self.vr == .AT ||
            self.vr == .TM  {
            if self.data != nil {
                data.append(self.data)
            }
        }
        
        return data
    }
    
    
    
    override public func toJSONArray() -> Any {
        var val:Any = ""
        
        if self.isMultiple {
            val = self.values.map { $0.value == "" ? "null" : $0.value }
        }
        else {
            if  self.vr == .OB ||
                self.vr == .OD ||
                self.vr == .OF ||
                self.vr == .OW ||
                self.vr == .UN {
                if (self.data != nil) {
                    val = self.data.base64EncodedString()
                    
                } else {
                    val = ""
                }
            }
            else {
                val = "\(self.value)"
            }
        }
        
        let json:[String:Any] = [
            "\(self.tagCode().uppercased())": [
                    "vr": "\(self.vr)",
                    "value": val
            ]
        ]
        
        return json
    }
    
    
    
    
    
    
    
    // MARK: - Private
    
    
    
    private func recalculateParentsLength() {
        var p = self.parent
        
        while p != nil {
            if let item = p as? DataItem {
                item.length = item.elements.map({$0.length}).reduce(0, +) + 16
            }
            else if let sequence = p as? DataSequence {
                sequence.length = sequence.items.map({$0.length}).reduce(0, +) + 8
            }
            p = p?.parent
        }
    }
}
