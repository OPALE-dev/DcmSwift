//
//  DataElement.swift
//  DICOM Test
//
//  Created by Rafael Warnault, OPALE on 17/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation

/**
 The `DataElement` class represent Data Element of the DICOM Data Set defined in Part. 05, Chap. 7 of the standard.
 
 A `DataElement` object is uniquely identified `DataTag` instance and has a `value` which the representation is defined by the `VR` property.
 
 `DataElement` can be read from files or data stream using the `DicomFile` and `DicomInputStream` classes.
 
 http://dicom.nema.org/medical/dicom/current/output/chtml/part05/chapter_7.html
 */
public class DataElement : DicomObject {
    public var startOffset:Int      = 0
    public var vrOffset:Int         = 0
    public var lengthOffset:Int     = 0
    public var dataOffset:Int       = 0
    public var endOffset:Int        = 0
    public var length:Int           = 0
    
    public var parent:DataElement?
    public var dataset:DataSet?
    public var tag:DataTag
    private var storedData:Data?
    public internal(set) var bulkDataReference:DICOMBulkDataReference?

    /// Accessing `data` preserves the historical API and materializes lazy
    /// file-backed Bulk Data on first access. Use `loadData()` when errors must
    /// be observed explicitly.
    public var data:Data! {
        get {
            if storedData == nil, bulkDataReference != nil {
                storedData = try? bulkDataReference?.load()
            }
            return storedData
        }
        set {
            storedData = newValue
            bulkDataReference = nil
        }
    }

    public var isDataLoaded:Bool { storedData != nil }

    public func loadData() throws -> Data {
        if let storedData { return storedData }
        guard let reference = bulkDataReference else { return Data() }
        let loaded = try reference.load()
        storedData = loaded
        return loaded
    }

    /// Reads a Value Field subrange without forcing a deferred value to become
    /// resident in memory.
    public func loadData(range:Range<Int>) throws -> Data {
        if let storedData {
            guard range.lowerBound >= 0, range.upperBound <= storedData.count else {
                throw StreamError.cannotReadStream(message: "Invalid Data Element value range")
            }
            return storedData.subdata(in: range)
        }
        guard let reference = bulkDataReference else {
            throw StreamError.cannotReadStream(message: "Data Element has no Value Field")
        }
        return try reference.load(range: range)
    }

    internal func deferData(to reference:DICOMBulkDataReference) {
        storedData = nil
        bulkDataReference = reference
    }
    
    public var vr:VR.VR               = VR.VR.UN
    public var vrMethod:VRMethod      = .Explicit
    public var byteOrder:ByteOrder    = .LittleEndian

    /// Private Creator identifier that reserves this element's block, if found
    /// in the same Data Set or Sequence Item.
    public internal(set) var privateCreator:String?

    /// Character repertoire effective when this element was decoded. Nested
    /// Data Sets may override the repertoire inherited from their container.
    public internal(set) var characterSet:DICOMCharacterSet?

    public var effectiveCharacterSet:DICOMCharacterSet {
        return characterSet ?? dataset?.characterSet ?? .defaultRepertoire
    }
    
    private var dataValues:[DataValue] = []
    
    public var group:String     { return self.tag.group }
    public var element:String   { return self.tag.element }
    public var name:String      { return self.tag.name }
    
    
    
    init(withTag tag:DataTag, parent:DataElement? = nil) {
        self.tag = tag
        
        if let vr = DicomSpec.shared.vrForTag(withCode: tag.code) {
            self.vr  = vr
        }
        
        if let p = parent {
            self.parent = p
        }
    }
    
    
    init(withTag tag:DataTag, dataset:DataSet? = nil, parent:DataElement? = nil) {
        self.dataset    = dataset
        self.tag        = tag
        
        if let p = parent {
            self.parent = p
        }
    }
    
    
    init?(withTagName name:String, dataset:DataSet, parent:DataElement? = nil) {
        if let t = DicomSpec.shared.dataTag(forName: name) {
            self.vr     = DicomSpec.shared.vrForTag(withCode: t.code)!
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
        
        if self.vr == .AT {
            let tags: [DataTag]
            if let tag = val as? DataTag {
                tags = [tag]
            } else if let values = val as? [DataTag] {
                tags = values
            } else {
                return false
            }
            self.data = tags.reduce(into: Data()) {
                $0.append($1.data(withByteOrder: self.byteOrder))
            }
            self.length = self.data.count
            self.recalculateParentsLength()
            return true
        }
        else if self.vr == .OB || self.vr == .OD || self.vr == .OF ||
                self.vr == .OL || self.vr == .OV || self.vr == .OW ||
                self.vr == .UN {
            if let data = val as? Data {
                self.data = data
                self.length = data.count
                self.recalculateParentsLength()
                return true
            }
        }
                
        if let string = val as? String {
            let encoded: Data?
            if usesSpecificCharacterSet {
                encoded = effectiveCharacterSet.encode(string)
            } else {
                encoded = string.data(using: .ascii)
            }

            guard var encoded else { return false }
            if encoded.count % 2 != 0 {
                encoded.append(byte: self.vr == .UI ? 0x00 : 0x20)
            }
            self.data = encoded
            self.length = encoded.count
            self.dataValues = string.components(separatedBy: "\\").enumerated().map {
                DataValue($0.element, atIndex: $0.offset)
            }
            ret = true
        } else {
            if let values = val as? [Int16], self.vr == .SS {
                self.data = values.reduce(into: Data()) {
                    $0.append(uint16: UInt16(bitPattern: $1), bigEndian: self.byteOrder == .BigEndian)
                }
                self.length = self.data.count
                ret = true
            }
            else if let values = val as? [Int32], self.vr == .SL {
                self.data = values.reduce(into: Data()) {
                    $0.append(uint32: UInt32(bitPattern: $1), bigEndian: self.byteOrder == .BigEndian)
                }
                self.length = self.data.count
                ret = true
            }
            else if let values = val as? [Int64], self.vr == .SV {
                self.data = values.reduce(into: Data()) {
                    $0.append(uint64: UInt64(bitPattern: $1), bigEndian: self.byteOrder == .BigEndian)
                }
                self.length = self.data.count
                ret = true
            }
            else if let values = val as? [UInt16], self.vr == .US {
                self.data = values.reduce(into: Data()) {
                    $0.append(uint16: $1, bigEndian: self.byteOrder == .BigEndian)
                }
                self.length = self.data.count
                ret = true
            }
            else if let values = val as? [UInt32], self.vr == .UL {
                self.data = values.reduce(into: Data()) {
                    $0.append(uint32: $1, bigEndian: self.byteOrder == .BigEndian)
                }
                self.length = self.data.count
                ret = true
            }
            else if let values = val as? [UInt64], self.vr == .UV {
                self.data = values.reduce(into: Data()) {
                    $0.append(uint64: $1, bigEndian: self.byteOrder == .BigEndian)
                }
                self.length = self.data.count
                ret = true
            }
            else if let values = val as? [Float32], self.vr == .FL {
                self.data = values.reduce(into: Data()) {
                    $0.append(uint32: $1.bitPattern, bigEndian: self.byteOrder == .BigEndian)
                }
                self.length = self.data.count
                ret = true
            }
            else if let values = val as? [Float64], self.vr == .FD {
                self.data = values.reduce(into: Data()) {
                    $0.append(uint64: $1.bitPattern, bigEndian: self.byteOrder == .BigEndian)
                }
                self.length = self.data.count
                ret = true
            }
            else if let v = val as? Int16 {
                self.data = Data()
                self.data.append(uint16: UInt16(bitPattern: v), bigEndian: self.byteOrder == .BigEndian)
                self.length = self.data.count
                ret = true
            }
            else if let v = val as? Int32 {
                self.data = Data()
                self.data.append(uint32: UInt32(bitPattern: v), bigEndian: self.byteOrder == .BigEndian)
                self.length = self.data.count
                ret = true
            }
            else if let v = val as? Int64 {
                self.data = Data()
                self.data.append(uint64: UInt64(bitPattern: v), bigEndian: self.byteOrder == .BigEndian)
                self.length = self.data.count
                ret = true
            }
            else if let v = val as? UInt16 {
                self.data = Data()
                self.data.append(uint16: v, bigEndian: self.byteOrder == .BigEndian)
                self.length = self.data.count
                ret = true
            }
            else if let v = val as? UInt32 {
                self.data = Data()
                self.data.append(uint32: v, bigEndian: self.byteOrder == .BigEndian)
                self.length = self.data.count
                ret = true
            }
            else if let v = val as? UInt64 {
                self.data = Data()
                self.data.append(uint64: v, bigEndian: self.byteOrder == .BigEndian)
                self.length = self.data.count
                ret = true
            }
            else if let v = val as? Float32 {
                self.data = Data()
                self.data.append(uint32: v.bitPattern, bigEndian: self.byteOrder == .BigEndian)
                self.length = self.data.count
                ret = true
            }
            else if let v = val as? Float64 {
                self.data = Data()
                self.data.append(uint64: v.bitPattern, bigEndian: self.byteOrder == .BigEndian)
                self.length = self.data.count
                ret = true
            }
        }
        
        self.recalculateParentsLength()

        return ret
    }

    public var int16Values:[Int16]? { fixedWidthValues(for: .SS, width: 2) { $0.toInt16(byteOrder: byteOrder) } }
    public var int32Values:[Int32]? { fixedWidthValues(for: .SL, width: 4) { $0.toInt32(byteOrder: byteOrder) } }
    public var int64Values:[Int64]? { fixedWidthValues(for: .SV, width: 8) { $0.toInt64(byteOrder: byteOrder) } }
    public var uint16Values:[UInt16]? { fixedWidthValues(for: .US, width: 2) { $0.toUInt16(byteOrder: byteOrder) } }
    public var uint32Values:[UInt32]? { fixedWidthValues(for: .UL, width: 4) { $0.toUInt32(byteOrder: byteOrder) } }
    public var uint64Values:[UInt64]? { fixedWidthValues(for: .UV, width: 8) { $0.toUInt64(byteOrder: byteOrder) } }
    public var float32Values:[Float32]? { fixedWidthValues(for: .FL, width: 4) { $0.toFloat32(byteOrder: byteOrder) } }
    public var float64Values:[Float64]? { fixedWidthValues(for: .FD, width: 8) { $0.toFloat64(byteOrder: byteOrder) } }

    public var attributeTagValues:[DataTag]? {
        guard vr == .AT, let data, data.count.isMultiple(of: 4) else { return nil }
        return data.chunked(into: 4).map { DataTag(withData: $0, byteOrder: byteOrder) }
    }

    /// Number of Values encoded by this Data Element. A zero-length Value Field
    /// has no values; bulk byte VRs and Sequences otherwise have VM 1.
    public var valueMultiplicity:Int {
        guard length > 0 else { return 0 }
        switch vr {
        case .AT: return data.count / 4
        case .SS, .US: return data.count / 2
        case .FL, .SL, .UL: return data.count / 4
        case .FD, .SV, .UV: return data.count / 8
        case .AE, .AS, .CS, .DA, .DS, .DT, .IS, .LO, .LT, .PN, .SH, .ST, .TM, .UC, .UI, .UR, .UT:
            guard let text = value as? String else { return 1 }
            return text.components(separatedBy: "\\").count
        default: return 1
        }
    }
    

    /**
     Contains the value fo the `DataElement`.
     - Important: If it's Pixel Data or a Sequence, returns an empty string
     */
    public var value:Any {
        if self.data == nil || self.data.count == 0 {
            return ""
        }
        
        if self.tag.code == "7fe00010" {
            return ""
        }
        
        if self.vr == .UL {
            return self.data.toUInt32(byteOrder: self.byteOrder)
        }
        else if self.vr == .SL {
            return self.data.toInt32(byteOrder: self.byteOrder)
        }
        else if self.vr == .SV {
            return self.data.toInt64(byteOrder: self.byteOrder)
        }
        else if self.vr == .US {
            return self.data.toUInt16(byteOrder: self.byteOrder)
        }
        else if self.vr == .SS {
            return self.data.toInt16(byteOrder: self.byteOrder)
        }
        else if self.vr == .UV {
            return self.data.toUInt64(byteOrder: self.byteOrder)
        }
        else if self.vr == .FL {
            return self.data.toFloat32(byteOrder: self.byteOrder)
        }
        else if self.vr == .FD {
            return self.data.toFloat64(byteOrder: self.byteOrder)
        }
        else if self.vr == .DA {
            return Date(dicomDate: self.data.toString()) as Any
        }
        else if self.vr == .DT {
            return Date(dicomDateTime: self.data.toString()) as Any
        }
        else if self.vr == .TM {
            return Date(dicomTime: self.data.toString()) as Any
        }
        else if self.vr == .UI ||
                self.vr == .AS ||
                self.vr == .CS ||
                self.vr == .DS ||
                self.vr == .IS ||
                self.vr == .AE ||
                self.vr == .UR {
            return DICOMCharacterSet.defaultRepertoire.decode(self.data) ?? self.data as Any
        }
        else if usesSpecificCharacterSet {
            return effectiveCharacterSet.decode(self.data) ?? self.data as Any
        }
        else if self.vr == .AT ||
                self.vr == .OB ||
                self.vr == .OW {
            return self.data as Any
        }
        else if self.vr == .SQ {
            return ""
        }
        
        return self.data as Any
    }

    private var usesSpecificCharacterSet: Bool {
        switch vr {
        case .LO, .LT, .PN, .SH, .ST, .UC, .UT:
            return true
        default:
            return false
        }
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
        
        if self.isMultiple {
            return false
        }
        
        if  self.vr == .AT ||
            self.vr == .OB ||
            self.vr == .DA ||
            self.vr == .DT ||
            self.vr == .TM ||
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
    
    /**
     Contains an array of values
     
     - Remark: useful when the value field of the `DataElement` has a VM > 1
     */
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
    
    /**
     Converts a `DataElement` to `XML`
     
     - Returns: an XML `String` representing the `DataElement`
     */
    public override func toXML(_ pretty: Bool? = true) -> String {
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
    
    
    /**
     - Returns: the `DataElement` tag all attached
     */
    public func tagCode() -> String {
        return "\(self.group)\(self.element)"
    }
    
    override public var description: String {
        return "\(self.startOffset) \(self.tag) \(self.vr)[\(self.value)] \t \(self.name) \(self.dataOffset) [\(self.length)] \(self.endOffset)"
    }
    
    
    
    public override func toData(transferSyntax: TransferSyntax) -> Data {
        return toData(vrMethod: transferSyntax.vrMethod, byteOrder: transferSyntax.byteOrder)
    }
    
    
    public override func toData(vrMethod inVrMethod:VRMethod = .Explicit, byteOrder inByteOrder:ByteOrder = .LittleEndian) -> Data {
        var data = Data()
        
        // write tag code
        data.append(self.tag.data(withByteOrder: inByteOrder))
        
        // write VR (only explicit)
        if inVrMethod == .Explicit  {
            let vrData = "\(self.vr)".data(using: .ascii)
            data.append(vrData!)
            
            if self.vr == .SQ {
                data.append(byte: 0x00, count: 2)
            }
            else if self.vr == .OB ||
                self.vr == .OW ||
                self.vr == .OF ||
                self.vr == .OL ||
                self.vr == .OV ||
                self.vr == .SQ ||
                self.vr == .SV ||
                self.vr == .UC ||
                self.vr == .UT ||
                self.vr == .UN ||
                self.vr == .UR ||
                self.vr == .UV {
                data.append(byte: 0x00, count: 2)
            }
        }
        
        
        // write length
        if self.vr == .SQ {
            data.append(uint32: UInt32(bitPattern: Int32(self.length)), bigEndian: inByteOrder == .BigEndian)
        }
        else if self.vr == .OB ||
            self.vr == .OW ||
            self.vr == .OF ||
            self.vr == .OL ||
            self.vr == .OV ||
            self.vr == .SV ||
            self.vr == .UC ||
            self.vr == .UT ||
            self.vr == .UN ||
            self.vr == .UR ||
            self.vr == .UV {
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
                    data.append(byte: 0xff, count: 4)
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
                data.append(uint32: UInt32(bitPattern: Int32(self.length)), bigEndian: inByteOrder == .BigEndian)
            }
        }
        
        
        // write value
        if self.data != nil {
            data.append(encodedValueData(byteOrder: inByteOrder))
        }
        
        return data
    }
    
    
    
    
    /**
     Converts the `DataElement` values to a JSON array
     
     - Note: why does it return `Any` instead of String ? is it because of the encoding ?
     - Returns: a json string array containing the values
     */
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

    private func fixedWidthValues<T>(for expectedVR:VR.VR, width:Int, decode:(Data) -> T) -> [T]? {
        guard vr == expectedVR, let data, data.count.isMultiple(of: width) else { return nil }
        return data.chunked(into: width).map(decode)
    }

    private func encodedValueData(byteOrder targetByteOrder: ByteOrder) -> Data {
        guard byteOrder != targetByteOrder else { return data }

        let wordSize: Int
        switch vr {
        case .US, .SS, .OW, .AT:
            wordSize = 2
        case .UL, .SL, .FL, .OF, .OL:
            wordSize = 4
        case .FD, .OD, .OV, .SV, .UV:
            wordSize = 8
        default:
            return data
        }

        guard data.count.isMultiple(of: wordSize) else { return data }
        var converted = Data(capacity: data.count)
        for start in stride(from: 0, to: data.count, by: wordSize) {
            converted.append(contentsOf: data[start..<start + wordSize].reversed())
        }
        return converted
    }
}
