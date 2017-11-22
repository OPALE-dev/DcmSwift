//
//  Dataset.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 17/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Foundation





public class DataSet: DicomObject {
    public var fileMetaInformationGroupLength:Int32 = 0
    public var transferSyntax:String                = "1.2.840.10008.1.2.1"
    public var vrMethod:DicomSpec.VRMethod          = .Explicit
    public var byteOrder:DicomSpec.ByteOrder        = .LittleEndian
    
    public var metaInformationHeaderElements:[DataElement]  = []
    public var datasetElements:[DataElement]                = []
    public var allElements:[DataElement]                    = []
    
    private var data:Data!
    
    
    
    
    public init?(withData data:Data) {
        self.data = data
    }
    
    
    
    override public var description: String {
        var string = ""
        for e in self.allElements {
            string += e.description + "\n"
        }
        return string
    }
    
    
    
    // MARK: - Public methods
    public func loadData() -> Bool {
        var offset = 132
        
        self.metaInformationHeaderElements  = []
        self.datasetElements                = []
        self.allElements                    = []
        
        while(offset < data.count) {
            let (newElement, elementOffset) = self.readDataElement(offset: offset)
            
            if !self.validate(dataElement: newElement) {
                return false
            }
            
            if newElement.name == "FileMetaInformationGroupLength" {
                self.fileMetaInformationGroupLength = newElement.value as! Int32
            }
            
            if newElement.name == "TransferSyntaxUID" {
                self.transferSyntax = newElement.value as! String
                
                if self.transferSyntax == "1.2.840.10008.1.2" {
                    self.vrMethod = .Implicit
                }
                
                if self.transferSyntax == "1.2.840.10008.1.2.2" {
                    self.byteOrder = .BigEndian
                }
            }
            
            if offset >= self.fileMetaInformationGroupLength+144 {
                self.datasetElements.append(newElement)
            }
            else {
                self.metaInformationHeaderElements.append(newElement)
                
            }
            
            self.allElements.append(newElement)
            
            offset = elementOffset
        }
        
        return true
    }

    
    
    
    public func string(forTag tag:String ) -> String! {
        for el in self.allElements {
            if el.name == tag {
                return el.value as! String
            }
        }
        return nil
    }
    
    
    public func integer32(forTag tag:String ) -> Int32 {
        for el in self.allElements {
            if el.name == tag {
                return el.value as! Int32
            }
        }
        return 0
    }
    
    
    public func integer16(forTag tag:String ) -> Int16 {
        for el in self.allElements {
            if el.name == tag {
                return el.value as! Int16
            }
        }
        return 0
    }
    
    
    public func date(forTag tag:String ) -> Date! {
        for el in self.allElements {
            if el.name == tag {
                if let dicomDateString = el.value as? String {
                    return Date(dicomDate: dicomDateString)
                }
            }
        }
        return nil
    }
    
    
    public func datetime(forTag tag:String ) -> Date {
        return Date()
    }
    
    
    public func time(forTag tag:String ) -> Date {
        return Date()
    }
    
    
    
    
    public func set(value:Any, toElement element:DataElement) -> Bool {
        if element.vr == .PN {
            if let string = value as? String {
                //element.value = string
            }
        }
        return false
    }
    
    
    
    
    public func element(forTagName name:String) -> DataElement? {
        for el in self.allElements {
            if el.name == name {
                return el
            }
        }
        return nil
    }
    
    
    
    public func remove(dataElement element:DataElement) -> DataElement {
        if let index = self.allElements.index(where: {$0 === element}) {
            self.allElements.remove(at: index)
        }
        if let index = self.metaInformationHeaderElements.index(where: {$0 === element}) {
            self.metaInformationHeaderElements.remove(at: index)
        }
        if let index = self.datasetElements.index(where: {$0 === element}) {
            self.datasetElements.remove(at: index)
        }
        return element
    }
    
    

    public var dicomImage:DicomImage? {
        get {
            if let pixelDataElement = self.element(forTagName: "PixelData") {
                return DicomImage(inDataset:self, withPixelDataElement: pixelDataElement)
            }
            return nil
        }
    }
    
    
    
    
    public func write(atPath path:String) -> Bool {
        var newData = Data()
        
        // overwrite file
        if FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                Swift.print("Error : Cannot overwrite file at path : \(path)")
                return false
            }
        }
        
        // write 128 bytes preamble
        newData.append(Data(repeating: 0x00, count: 128))
        
        // write DICM magic word
        newData.append("DICM".data(using: .utf8)!)
        
        // write meta header elements
        for element in self.metaInformationHeaderElements {
            newData.append(self.write(dataElement: element))
        }
        
        // write dataset elements
        for element in self.datasetElements {
            newData.append(self.write(dataElement: element))
        }
        
        // write file to FS
        let ok = FileManager.default.createFile(atPath: path, contents: newData, attributes: nil)
        
        return ok
    }
    
    
    
    
    
    
    
    
    // MARK: - Private methods
    private func validate(dataElement element:DataElement) -> Bool {
        if DicomSpec.shared.validate {
            if element.name == "TransferSyntaxUID" {
                if !DicomSpec.shared.isSupported(transferSyntax: element.value as! String) {
                    print("Validation error : this transfer syntax is not supported [\(element.value)]")
                    return false
                }
            }
            if element.name == "SOPClassUID" {
                if !DicomSpec.shared.isSupported(sopClass: element.value as! String) {
                    print("Validation error : this SOP class is not supported [\(element.value)]")
                    return false
                }
            }
        }
        
        return true
    }
    
    
    
    
    
    
    private func readDataElement(offset:Int) -> (DataElement, Int) {
        var order:DicomSpec.ByteOrder           = .LittleEndian
        var localVRMethod:DicomSpec.VRMethod    = .Explicit
        var length:Int                          = 0
        var os                                  = offset

        
        // set local byte order to enforce Little Endian for Meta Information Header elements
        if self.byteOrder == .BigEndian && os >= self.fileMetaInformationGroupLength+144 {
            order = .BigEndian
        } else {
            order = .LittleEndian
        }
        
        
        // set local VR Method to enforce Explicit for Meta Information Header elements
        if self.vrMethod == .Implicit && os >= self.fileMetaInformationGroupLength+144 {
            localVRMethod = .Implicit
        } else {
            localVRMethod = .Explicit
        }
        
        // read tag
        let tagData = data.subdata(in: os..<os+4)
        let tag = DataTag(withData:tagData, byteOrder:order)
        os += 4
        
        
        // create new data element
        var element:DataElement = DataElement(withTag:tag)
        element.startOffset = os
        element.byteOrder = order
        
        
        // read VR
        if localVRMethod == .Explicit {
            element.vr = DicomSpec.vr(for: data.subdata(in: os..<os+2).toString())
            
            // 0000H reserved VR bytes
            // http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_7.5.html
            if element.vr == .SQ {
                os += 4
            }
            // Table 7.1-1. Data Element with Explicit VR of OB, OW, OF, SQ, UT or UN
            // http://dicom.nema.org/Dicom/2013/output/chtml/part05/chapter_7.html
            else if element.vr == .OB ||
                element.vr == .OW ||
                element.vr == .OF ||
                element.vr == .SQ ||
                element.vr == .UT ||
                element.vr == .UN {
                os += 4
            } else {
                os += 2
            }
        }
        else {
            // if it's an implicit element group length
            if element.element == "0000" {
                element.vr = .UL
            }
            else {
                // TODO: manage VR couples (ex: "OB/OW" in xml spec)
                element.vr = DicomSpec.shared.vrForTag(withCode:element.tag.code)
            }
        }
        

        
        // read length
        if localVRMethod == .Explicit {
            if element.vr == .SQ {
                let bytes:Data = self.data.subdata(in: os..<os+4)
                
                if bytes.toHex() == "ffffffff" {
                    length = -1
                } else {
                    length = Int(data.subdata(in: os..<os+4).toInt32(byteOrder: order))
                }
                os += 4
            } else if element.vr == .OB ||
                element.vr == .OW ||
                element.vr == .OF ||
                element.vr == .SQ ||
                element.vr == .UT ||
                element.vr == .UN {
                length = Int(data.subdata(in: os..<os+4).toInt32(byteOrder: order))
                os += 4
            } else {
                length = Int(data.subdata(in: os..<os+2).toInt16(byteOrder: order))
                os += 2
            }
        }
        else {
            // implicit length
            length = Int(data.subdata(in: os..<os+4).toInt32(byteOrder: order))
            os += 4
        }
        
        // MISSING VR FOR IMPLICIT ELEMENT
        // TODO: if VR is implicit, we need to use the correpsondign tag VR ?
        
        element.dataOffset = os
        
        // read value data
        if element.vr == .OW {
            if element.name == "PixelData" && length == -1 {
                let (sequence, seqOffset) = self.readPixelSequence(tag: tag, offset: os, byteOrder: order)
                sequence.vr             = element.vr
                sequence.startOffset    = element.startOffset
                sequence.dataOffset     = element.dataOffset
                element                 = sequence
                os = seqOffset
            }
            else {
                element.data = data.subdata(in: os..<os+Int(length))
            }
        }
        else if element.vr == .OB {
            if element.name == "PixelData" && length == -1 {
                let (sequence, seqOffset) = self.readPixelSequence(tag: tag, offset: os, byteOrder: order)
                sequence.vr             = element.vr
                sequence.startOffset    = element.startOffset
                sequence.dataOffset     = element.dataOffset
                element                 = sequence
                os = seqOffset
            }
            else {
                element.data = data.subdata(in: os..<os+Int(length))
            }
        }
        else if element.vr == .SQ {
            let (sequence, seqOffset) = self.readDataSequence(tag:element.tag, offset: os, length: Int(length), byteOrder:order)
            sequence.vr             = element.vr
            sequence.startOffset    = element.startOffset
            sequence.dataOffset     = element.dataOffset
            element                 = sequence
            
            if sequence.vrMethod == .Implicit {
                length = 0
            }
            
            os = seqOffset
        }
        else {
            // TODO: manage default value better ?
            if length > 0 {
                element.data = data.subdata(in: os..<os+Int(length))
            }
        }
        
       
        
        element.length = Int(length)
        
        if element.vr != .SQ {
            //element.value = value
        }
        
        os += Int(length)
        
        // is Pixel Data reached
        if element.tagCode() == "7fe00010" {
            os = data.count
        }
        
        element.endOffset = os
        
        return (element, os)
    }
    
    
    
    
    private func readDataSequence(tag:DataTag, offset:Int, length:Int, byteOrder:DicomSpec.ByteOrder) -> (DataSequence, Int) {
        let sequence:DataSequence = DataSequence(withTag:tag)
        var bytesRead = 0
        var os = offset
        
        if length > 0 {
            // data items
            while (length > bytesRead) {
                let tag = DataTag(withData: data.subdata(in: os..<os+4), byteOrder: byteOrder)
                bytesRead       += 4
                os              += 4
                
                let itemLength   = data.subdata(in: os..<os+4).toInt16(byteOrder: byteOrder)
                bytesRead       += 4
                os              += 4
                
                let item         = DataItem(withTag:tag)
                item.length      = Int(itemLength)
                item.startOffset = os - 12
                item.dataOffset  = os
                sequence.items.append(item)
                
                // item data elements
                var itemBytesRead = 0
                while(itemLength > itemBytesRead) {
                    let (newElement, elementOffset) = self.readDataElement(offset: os)
                    itemBytesRead += newElement.length + 8
                    bytesRead += newElement.length + 8
                    os = elementOffset
                    
                    item.elements.append(newElement)
                }
                item.endOffset = os
            }
        }
            // Undefined Length data items (length == FFFFFFFF)
        else if length == -1 {
            sequence.vrMethod = .Implicit
            
            var tag = DataTag(withData: data.subdata(in: os..<os+4), byteOrder: byteOrder)
            os += 4
            
            while(tag.code == "fffee000") {
                let subdata = data.subdata(in: os..<os+4)
                var itemLength:Int16 = 0
                
                os += 4
                
                let item            = DataItem(withTag:tag)
                item.startOffset    = os - 8
                item.dataOffset     = os
                item.vrMethod       = .Implicit
                
                sequence.items.append(item)
                
                // Undefined Length data elements (ffffffff)
                if subdata.toHex() == "ffffffff" {
                    var reachEnd = false
                    
                    while(reachEnd == false) {
                        let subtag = DataTag(withData: data.subdata(in: os..<os+4), byteOrder: byteOrder)
                        
                        if subtag.code != "fffee00d" {
                            let (newElement, elementOffset) = self.readDataElement(offset: os)
                            os = elementOffset
                            
                            item.elements.append(newElement)
                        } else {
                            reachEnd = true
                            os += 8
                        }
                    }
                    
                    tag = DataTag(withData: data.subdata(in: os..<os+4), byteOrder: byteOrder)
                    os += 4
                    
                    if tag.code == "fffee0dd" {
                        os += 4
                    }
                }
                // Length defined data elements
                else {
                    itemLength  = subdata.toInt16(byteOrder: byteOrder)
                    item.length = Int(itemLength)
                    
                    var itemBytesRead = 0
                    while(itemLength > itemBytesRead) {
                        let (newElement, elementOffset) = self.readDataElement(offset: os)
                        itemBytesRead += newElement.length + 8
                        bytesRead += newElement.length + 8
                        os = elementOffset
                        
                        item.elements.append(newElement)
                    }
                    
                    tag = DataTag(withData: data.subdata(in: os..<os+4), byteOrder: byteOrder)
                    os += 4
                }
                
                item.endOffset = os
            }
            
            os += 4
            
            // in order to return the good offset
            return (sequence, os)
        }
        // empty sequence
        else if length == 0 {
            // TODO: fix issue when a empty sequence is the element of an item
            //print("empty seq")
            //print(sequence)
        }
        
        return (sequence, offset)
    }
    
    
    
    
    private func readPixelSequence(tag:DataTag, offset:Int, byteOrder:DicomSpec.ByteOrder) -> (PixelSequence, Int) {
        let pixelSequence = PixelSequence(withTag: tag)
        var os = offset
        
        // read item tag
        var itemTag = DataTag(withData: data.subdata(in: os..<os+4), byteOrder: byteOrder)
        os += 4
        
        while itemTag.code != "fffee0dd" {
            // read item
            let item            = DataItem(withTag: itemTag)
            item.startOffset    = os - 4
            item.dataOffset     = os
            item.vrMethod       = .Explicit
            
            pixelSequence.items.append(item)
            
            // read item length
            let itemLength = data.subdata(in: os..<os+4).toInt32(byteOrder: byteOrder)
            os += 4
            
            item.length = Int(itemLength)
            
            if itemLength > 0 {
                item.data = data.subdata(in: os..<os+Int(itemLength))
                os += Int(itemLength)
            }
            
            // read next again
            if os < self.data.count {
                itemTag = DataTag(withData: data.subdata(in: os..<os+4), byteOrder: byteOrder)
                os += 4
            }
        }
        
        return (pixelSequence, os)
    }
    
    
    
    
    
    private func write(dataElement element:DataElement, vrMethod:DicomSpec.VRMethod = .Explicit, byteOrder:DicomSpec.ByteOrder = .LittleEndian) -> Data {
        var data = Data()
        var localVRMethod:DicomSpec.VRMethod = .Explicit
        var order:DicomSpec.ByteOrder = .LittleEndian
        
        // set local byte order to enforce Little Endian for Meta Information Header elements
        if self.byteOrder == .BigEndian && element.endOffset > self.fileMetaInformationGroupLength+144 {
            order = .BigEndian
        }
        
        // set local VR Method to enforce Explicit for Meta Information Header elements
        if self.vrMethod == .Implicit && element.endOffset > self.fileMetaInformationGroupLength+144 {
            localVRMethod = .Implicit
        }
        
        // write tag code
        data.append(element.tag.data)

        // write VR (only explicit)
        if localVRMethod == .Explicit  {
            let vrString = "\(element.vr)"
            data.append(vrString.data(using: .utf8)!)
            if element.vr == .SQ {
                data.append(Data(repeating: 0x00, count: 2))
            }
            else if element.vr == .OB ||
                element.vr == .OW ||
                element.vr == .OF ||
                element.vr == .SQ ||
                element.vr == .UT ||
                element.vr == .UN {
                data.append(Data(repeating: 0x00, count: 2))
            }
        }
        
        
        // write length
        if element.vr == .SQ {
            var intLength = UInt32(element.length)
            let lengthData = Data(bytes: &intLength, count: 4)
            data.append(lengthData)
        }
        else if element.vr == .OB ||
                element.vr == .OW ||
                element.vr == .OF ||
                element.vr == .UT ||
                element.vr == .UN {
            if element.length >= 0 {
                var intLength = UInt32(element.length)
                let lengthData = Data(bytes: &intLength, count: 4)
                data.append(lengthData)
            }
            // negative length indicate sequence here
            else if element.length == -1 {
                // if OB/OW is a Pixel Sequence
                if let _ = element as? PixelSequence {
                    //print(pixelSequence)
                    data.append(Data(repeating: 0xff, count: 4))
                }
            }
        }
        else {
            if localVRMethod == .Explicit {
                var intLength = UInt32(element.length)
                let lengthData = Data(bytes: &intLength, count: 2)
                data.append(lengthData)
            }
            else if localVRMethod == .Implicit {
                var intLength = UInt32(element.length)
                let lengthData = Data(bytes: &intLength, count: 4)
                data.append(lengthData)
            }
        }
        
        
        // write value
        if  element.vr == .UL {
            data.append(element.data)
        }
        else if element.vr == .OB {
            Swift.print(element)
            Swift.print(element.data)
            data.append(element.data)
        }
        else if element.vr == .OW {
            if let pixelSequence = element as? PixelSequence {
                data.append(self.write(pixelSequence: pixelSequence))
            } else {
                if element.data != nil {
                    data.append(element.data)
                }
            }
        }
        else if element.vr == .UI {
            data.append(element.data)
        }
        else if element.vr == .FL {
            data.append(element.data)
        }
        else if element.vr == .FD {
            data.append(element.data)
        }
        else if element.vr == .SL {
            data.append(element.data)
        }
        else if element.vr == .SS {
            data.append(element.data)
        }
        else if element.vr == .US {
            data.append(element.data) 
        }
        else if element.vr == .SQ {
            if let sequence = element as? DataSequence {
                data.append(self.write(dataSequence: sequence))
            }
        }
        else if     element.vr == .SH ||
                    element.vr == .AS ||
                    element.vr == .CS ||
                    element.vr == .DS ||
                    element.vr == .LO ||
                    element.vr == .LT ||
                    element.vr == .ST ||
                    element.vr == .OD ||
                    element.vr == .OF ||
                    element.vr == .AE ||
                    element.vr == .UT ||
                    element.vr == .IS ||
                    element.vr == .PN ||
                    element.vr == .DA ||
                    element.vr == .DT ||
                    element.vr == .TM  {
            if element.data != nil {
                data.append(element.data)
            }
        }
        
        return data
    }
    
    
    
    private func write(pixelSequence sequence:PixelSequence) -> Data {
        var data = Data()
        
        for item in sequence.items {
            // write item tag
            data.append(item.tag.data)
            
            // write item length
            var intLength = UInt32(item.length)
            let lengthData = Data(bytes: &intLength, count: 4)
            data.append(lengthData)
            
            // write item value
            if intLength > 0 {
                data.append(item.data)
            }
        }
        
        // write pixel Sequence Delimiter Item
        let tag = DataTag(withGroup: "fffe", element: "e0dd")
        data.append(tag.data)
        data.append(Data(repeating: 0x00, count: 4))
        
        
        return data
    }
    
    
    
    private func write(dataSequence sequence:DataSequence) -> Data {
        var data = Data()
        
        for item in sequence.items {
            // write item tag
            data.append(item.tag.data)
                        
            // write item length
            if item.vrMethod == .Explicit && item.length != -1 {
                // Swift.print(item.length)
                var intLength = UInt32(item.length)
                let lengthData = Data(bytes: &intLength, count: 4)
                data.append(lengthData)
            }
            
            // write item sub-elements
            for element in item.elements {
                data.append(self.write(dataElement: element))
            }
            
            // write item delimiter
            if item.vrMethod == .Implicit {
                let tag = DataTag(withGroup: "fffe", element: "e00d")
                data.append(tag.data)
                data.append(Data(repeating: 0x00, count: 4))
            }
        }
        
        // write sequence delimiter
        if sequence.vrMethod == .Implicit {
            let tag = DataTag(withGroup: "fffe", element: "e0dd")
            data.append(tag.data)
            data.append(Data(repeating: 0x00, count: 4))
        }
        
        return data
    }
}
