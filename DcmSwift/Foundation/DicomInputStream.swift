//
//  DicomInputStream.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 10/06/2021.
//  Copyright © 2021 OPALE. All rights reserved.
//

import Foundation

public class DicomInputStream {
    var dataset:DataSet!
    var data:Data!
    var offset:Int = 0
    var hasBytesAvailable: Bool {
        get {
            return offset < data.count
        }
    }
    
    public init(dataset:DataSet, data:Data) {
        self.dataset    = dataset
        self.data       = data
    }
    
    
    // MARK: -
    public func read(length: Int) -> Data {
        if offset + length > data.count {
            return Data()
        }
        
        let chunk = data.subdata(in: offset..<(offset + length))
        
        offset += length
        
        return chunk
    }
    
    public func forward(by bytes: Int) {
        offset += bytes
    }
    
    public func backward(by bytes: Int) {
        offset -= bytes
    }
    
    
    // MARK: -
    public func readDataTag(order:DicomConstants.ByteOrder = .LittleEndian) -> DataTag? {
        let tagData = self.read(length: 4)
        
        if tagData.count < 4 {
            return nil
        }
        
        let tag = DataTag(withData:tagData, byteOrder:order)
                        
        return tag
    }
    
    
    public func readDataElement(
        dataset:DataSet?                    = nil,
        parent:DataElement?                 = nil,
        vrMethod:DicomConstants.VRMethod    = .Explicit,
        order:DicomConstants.ByteOrder      = .LittleEndian
    ) -> DataElement? {
        guard let tag = readDataTag(order: order) else {
            Logger.error("Cannot read tag at offset at \(self.offset)")
            
            return nil
        }
        
        let startOffset = offset
        
        var element = DataElement(withTag:tag, dataset: dataset, parent: parent)
        
        element.startOffset = startOffset
        element.byteOrder   = order
        element.vr          = readVR(element:element, vrMethod: vrMethod)
        element.length      = readLength(vrMethod: vrMethod, vr: element.vr, order: order)
        element.dataOffset  = offset
        
        // check for invalid
        if element.length > data.count {
            let message = "Fatal, cannot read length properly, decoded length at offset(\(offset-4)) overflows (\(element.length))"
            return readError(forLength: Int(element.length), element: element, message: message)
        }
                
        // read value data
        // if OB/OW but not in prefix header
        if tag.group != "0002" && (element.vr == .OW || element.vr == .OB) {
            if element.name == "PixelData" && element.length == -1 {
                guard let sequence = readPixelSequence(tag: tag, byteOrder: order) else {
                    Logger.error("Cannot read Pixel Sequence \(tag) at \(self.offset)")
                    return nil
                }

                sequence.parent         = element
                sequence.vr             = element.vr
                sequence.startOffset    = element.startOffset
                sequence.dataOffset     = element.dataOffset
                element                 = sequence

                // this +5 is very weird, but it works for some JPEGBaseline multiframe file
                // os = seqOffset + 5
                forward(by: 4)

            } else {
                element.data = readValue(length: Int(element.length))
            }
        }
        else if element.vr == .SQ {
            guard let sequence = readDataSequence(tag:element.tag, length: Int(element.length), byteOrder:order) else {
                Logger.error("Cannot read Sequence \(tag) at \(self.offset)")
                return nil
            }
            
            sequence.parent         = element
            sequence.vr             = element.vr
            sequence.startOffset    = element.startOffset
            sequence.dataOffset     = element.dataOffset
            element                 = sequence
        }
        else {
            // TODO: manage default value better ?
            element.data        = readValue(length: Int(element.length))
            element.endOffset   = offset
        }
        
        print("element \(element)")
                
        return element
    }
    
    
    private func readError(forLength length:Int, element: DataElement, message:String) -> DataElement {
        let v = ValidationResult(element, message: message, severity: .Fatal)
        
        dataset.internalValidations.append(v)
        dataset.isCorrupted = true
        
        Logger.error(message)
        
        return element
    }
    
    
    private func readVR(element:DataElement, vrMethod:DicomConstants.VRMethod = .Explicit) -> DicomConstants.VR {
        var vr:DicomConstants.VR = .UL
        
        if vrMethod == .Explicit {
            vr = DicomSpec.vr(for: read(length: 2).toString())
            
            // 0000H reserved VR bytes
            // http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_7.5.html
            if vr == .SQ {
                self.forward(by: 2)
            }
            // Table 7.1-1. Data Element with Explicit VR of OB, OW, OF, SQ, UT or UN
            // http://dicom.nema.org/Dicom/2013/output/chtml/part05/chapter_7.html
            else if vr == .OB ||
                    vr == .OW ||
                    vr == .OF ||
                    vr == .SQ ||
                    vr == .UT ||
                    vr == .UN {
                self.forward(by: 2)
            }
        }
        else {
            // if it's an implicit element group length
            // we set the VR as undefined
            if element.element == "0000" {
                vr = .UL
            }
            // else we take the VR from the spec
            else {
                // TODO: manage VR couples (ex: "OB/OW" in xml spec)
                vr = DicomSpec.shared.vrForTag(withCode:element.tag.code)
            }
        }
        
        return vr
    }
    
    private func readLength(
        vrMethod:DicomConstants.VRMethod = .Explicit,
        vr:DicomConstants.VR,
        order:DicomConstants.ByteOrder = .LittleEndian
    ) -> Int {
        var length:Int = 0
        
        if vrMethod == .Explicit {
            if vr == .SQ {
                let bytes:Data = read(length: 4)
                
                // undefined length sequence
                if bytes == Data([0xff, 0xff, 0xff, 0xff]) {
                    length = -1
                } else {
                    length = Int(bytes.toInt32(byteOrder: order))
                }

            } else if   vr == .OB ||
                        vr == .OW ||
                        vr == .OF ||
                        vr == .SQ ||
                        vr == .UT ||
                        vr == .UN {
                length = Int(read(length: 4).toInt32(byteOrder: order))
            } else {
                length = Int(read(length: 2).toInt16(byteOrder: order))
            }
        }
        else {
            // implicit length
            length = Int(read(length: 4).toInt32(byteOrder: order))
        }
        
        return length
    }
    

    
    private func readValue(length:Int ) -> Data? {
        // TODO: manage default value better ?
        if length > 0 && (offset + length < data.count) {
            return read(length: length)
        }
        
        return nil
    }
    
    

    private func readDataSequence(
        tag:DataTag,
        length:Int,
        byteOrder:DicomConstants.ByteOrder,
        parent: DataElement? = nil
    ) -> DataSequence? {
        let sequence:DataSequence = DataSequence(withTag:tag)
        var bytesRead = 0
                
        if length > 0 {
            // data items
            while (length > bytesRead) {
                let tag = DataTag(withData: read(length: 4), byteOrder: byteOrder)
                bytesRead += 4
                
                let itemLength = read(length: 4).toInt32(byteOrder: byteOrder)
                bytesRead += 4
                
                // CHECK FOR INVALID LENGTH
                if itemLength > data.count {
                    let message = "Fatal, cannot read length properly, decoded length at offset(\(offset-4)) overflows (\(itemLength))"
                    return readError(forLength: Int(itemLength), element: sequence, message: message) as? DataSequence
                }
                if itemLength < -1 {
                    let message = "Fatal, cannot read length properly, decoded length at offset(\(offset-4)) cannot be negative (\(itemLength))"
                    return readError(forLength: Int(itemLength), element: sequence, message: message) as? DataSequence
                }
                
                let item         = DataItem(withTag:tag, parent: sequence)
                item.length      = Int(itemLength)
                item.startOffset = offset - 12
                item.dataOffset  = offset
                sequence.items.append(item)
                
                // item data elements
                var itemBytesRead = 0
                
                while(itemLength > itemBytesRead) {
                    guard let newElement = readDataElement(dataset: self.dataset, parent: item, vrMethod: .Explicit, order: byteOrder) else {
                        Logger.debug("Cannot read element in sequence \(tag) at \(self.offset)")
                        return nil
                    }
                    
                    item.elements.append(newElement)
                                        
                    itemBytesRead   += newElement.length + 8
                    bytesRead       += newElement.length + 8
                }
                
                item.endOffset = offset
            }
        }
        // Undefined Length data items (length == FFFFFFFF)
        else if length == -1 {
            sequence.vrMethod = .Implicit
            
            var tag = DataTag(withData: read(length: 4), byteOrder: byteOrder)
            
            while(tag.code == "fffee000") {
                let subdata = read(length: 4)
                var itemLength:Int16 = 0
                
                let item            = DataItem(withTag:tag, parent: sequence)
                item.startOffset    = offset - 8
                item.dataOffset     = offset
                item.vrMethod       = .Implicit
                
                sequence.items.append(item)
                
                // Undefined Length data elements (ffffffff)
                if subdata == Data([0xff, 0xff, 0xff, 0xff]) {
                    var reachEnd = false
                    
                    while(reachEnd == false) {
                        let subtag = DataTag(withData: read(length: 4), byteOrder: byteOrder)
                        
                        if subtag.code != "fffee00d" {
                            guard let newElement = readDataElement(dataset: self.dataset, parent: item, vrMethod: .Explicit, order: byteOrder) else {
                                Logger.debug("Cannot read element in sequence \(tag) at \(self.offset)")
                                return nil
                            }
                                                        
                            item.elements.append(newElement)
                        } else {
                            reachEnd = true
                            forward(by: 8)
                        }
                    }
                    
                    if tag.code == "fffee0dd" {
                        forward(by: 4)
                    }
                    
                    if let t = readDataTag(order: byteOrder) {
                        tag = t
                    }
                }
                // Length defined data elements
                else {
                    itemLength  = subdata.toInt16(byteOrder: byteOrder)
                    item.length = Int(itemLength)
                    
                    var itemBytesRead = 0
                    while(itemLength > itemBytesRead) {
                        guard let newElement = readDataElement(dataset: self.dataset, parent: item, vrMethod: .Explicit, order: byteOrder) else {
                            Logger.debug("Cannot read element in sequence \(tag) at \(self.offset)")
                            return nil
                        }
                        
                        item.elements.append(newElement)
                        
                        itemBytesRead   += newElement.length + 4
                        bytesRead       += newElement.length + 4
                    }
                    
                    if let t = readDataTag(order: byteOrder) {
                        tag = t
                    }
                }
                
                item.endOffset = offset
            }
            
            forward(by: 4)
            
            // in order to return the good offset
            return sequence
        }
        // empty sequence
        else if length == 0 {
            // TODO: fix issue when a empty sequence is the element of an item
            //print("empty seq")
            //print(sequence)
        }
        
        sequence.endOffset = offset
                
        return sequence
    }
    
    
    private func readPixelSequence(tag:DataTag, byteOrder:DicomConstants.ByteOrder) -> PixelSequence? {
        let pixelSequence = PixelSequence(withTag: tag)
        
        // read item tag
        var itemTag = DataTag(withData: read(length: 4), byteOrder: byteOrder)
                
        while itemTag.code != "fffee0dd" {
            // read item
            let item            = DataItem(withTag: itemTag)
            item.startOffset    = offset - 4
            item.dataOffset     = offset
            item.vrMethod       = .Explicit
            
            pixelSequence.items.append(item)
            
            // read item length
            let itemLength = read(length: 4).toInt32(byteOrder: byteOrder)
                        
            // CHECK FOR INVALID LENGTH
            if itemLength > data.count {
                let message = "Fatal, cannot read length properly, decoded length at offset(\(offset-4)) overflows (\(itemLength))"
                return readError(forLength: Int(itemLength), element: pixelSequence, message: message) as? PixelSequence
            }
            if itemLength < -1 {
                let message = "Fatal, cannot read length properly, decoded length cannot be negative (\(itemLength))"
                return readError(forLength: Int(itemLength), element: pixelSequence, message: message) as? PixelSequence
            }
            
            item.length = Int(itemLength)
            
            if itemLength > 0 {
                item.data =  read(length: Int(itemLength))
            }
            
            // read next again
            if offset < data.count {
                itemTag = DataTag(withData: read(length: 4), byteOrder: byteOrder)
            }
        }
        
        return pixelSequence
    }
}
