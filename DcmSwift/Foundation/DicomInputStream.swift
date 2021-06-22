//
//  DicomInputStream.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 10/06/2021.
//  Copyright © 2021 OPALE. All rights reserved.
//

import Foundation

public class DicomInputStream {
    private var dataset:DataSet!
    
    public var hasPreamble:Bool = false    
    public var vrMethod:DicomConstants.VRMethod     = .Explicit
    public var byteOrder:DicomConstants.ByteOrder   = .LittleEndian
    
    var stream:InputStream!
    var offset = 0
    var total  = 0
    
    var hasBytesAvailable: Bool {
        get {
            return stream.hasBytesAvailable
        }
    }
    
    public init(filePath:String) {
        dataset = DataSet()
        stream  = InputStream(fileAtPath: filePath)
        total   = Int(DicomFile.fileSize(path: filePath))
    }
    
    public init(url:URL) {
        dataset = DataSet()
        stream  = InputStream(url: url)
        total   = Int(DicomFile.fileSize(path: url.path))
    }
    
    public init(data:Data) {
        dataset = DataSet()
        stream  = InputStream(data: data)
        total   = data.count
    }
    
    
    // MARK: -
    public func readDataset(headerOnly:Bool = false, withoutPixelData:Bool = false) -> DataSet? {
        stream.open()
        
        // Read first tag : if first tag is 0000,0000 try to read
        // preamble (128 bytes), then DICM magic word (4 bytes).
        //
        // Else if the read tag is a valid DICOM tag,
        // we try to process the file from offset 0.
        var tag = readDataTag(order: byteOrder)
        
        if tag == nil {
            Logger.error("Cannot read 4 first bytes")
            return nil
        }
                
        // read DICOM preamble
        if tag!.code == "00000000" {
            // only the remaining bytes, we already read 4
            _ = read(length: 124)
            
            // read the magic word
            let magic = read(length: 4)
            
            if let  magicWord = String(bytes: magic, encoding: .ascii),
                    magicWord != "DICM" {
                Logger.error("Not a DICOM file, abort")
                return nil
            }
                    
            hasPreamble = true
        }
        
        if hasPreamble {
            // we kill the 00000000 fake tag read earlier
            tag = nil
            // we will parse the DICOM meta Info header as Explicit VR
            vrMethod = .Explicit
        } else {
            // for old ACR-NEMA file
            vrMethod = .Implicit
        }
                
        while(stream.hasBytesAvailable && offset < total && !dataset.isCorrupted) {
            if let newElement = readDataElement(dataset: dataset, parent: nil, vrMethod: vrMethod, order: byteOrder) {
                // header only option
                if headerOnly && newElement.tag.group != "0002" {
                    break
                }
                
                // without pixel data option
                if !headerOnly && withoutPixelData && newElement.tagCode() == "7fe00010" {
                    break
                }
                
                // grab the file Meta Information Group Length
                // theorically used to determine the end of the Meta Info Header
                // but we rely on 0002 group to really check this for now
                if newElement.name == "FileMetaInformationGroupLength" {
                    dataset.fileMetaInformationGroupLength = Int(newElement.value as! Int32)
                }
                
                // determine transfer syntax
                if newElement.name == "TransferSyntaxUID" {
                    dataset.transferSyntax = newElement.value as! String
                    
                    if dataset.transferSyntax == DicomConstants.implicitVRLittleEndian {
                        vrMethod  = .Implicit
                        byteOrder = .LittleEndian
                    }
                    else if dataset.transferSyntax == DicomConstants.explicitVRBigEndian {
                        vrMethod  = .Explicit
                        byteOrder = .BigEndian
                    }
                    else {
                        vrMethod  = .Explicit
                        byteOrder = .LittleEndian
                    }
                }
                                            
                // append to sub-datasets
                if !dataset.isCorrupted {
                    //Logger.debug(newElement)
                    
                    if newElement.group != DicomConstants.metaInformationGroup {
                        dataset.datasetElements.append(newElement)
                    }
                    else {
                        dataset.metaInformationHeaderElements.append(newElement)
                        
                    }
                    
                    dataset.allElements.append(newElement)
                }
            }
        }
        
        dataset.sortElements()
        
        stream.close()
        
        return dataset
    }

    
    private func forward(by bytes: Int) {
        // read into the void...
        _ = read(length: bytes)
        
        // maintain a local offset
        offset += bytes
    }
    
    
    private func read(length:Int) -> Data {
        var data = Data()
        
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: length)
        
        let read = stream.read(buffer, maxLength: length)
        
        data.append(buffer, count: read)
        
        offset += read
        
        buffer.deallocate()
        
        return data
    }
    
    
    // MARK: -
    private func readDataElement(
        dataset:DataSet?                    = nil,
        parent:DataElement?                 = nil,
        vrMethod:DicomConstants.VRMethod    = .Explicit,
        order:DicomConstants.ByteOrder      = .LittleEndian,
        inTag:DataTag?                      = nil
    ) -> DataElement? {
        let startOffset = offset
        
        // if no tag given, we try to read the tag
        guard let tag = inTag ?? readDataTag(order: order) else {
            Logger.error("Cannot read tag at offset at \(self.offset)")
            
            return nil
        }
                
        // ignore delimitation items
        if tag.code == "fffee0dd" {
            return nil
        }
        else if tag.code == "fffee00d" {
            return nil
        }
                                
        var element = DataElement(withTag:tag, dataset: dataset, parent: parent)
        
        element.startOffset = startOffset
        element.vrMethod    = element.group == "0002" ? .Explicit : vrMethod
        element.byteOrder   = element.group == "0002" ? .LittleEndian : order
        element.vr          = readVR(element:element, vrMethod: element.vrMethod)
        element.length      = readLength(vrMethod: element.vrMethod, vr: element.vr, order: element.byteOrder)
        element.dataOffset  = offset
        
        
        // check for invalid
        if element.length > total {
            let message = "Fatal, cannot read length properly, decoded \(tag) length at offset(\(offset-4)) overflows (\(element.length))"
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
            element.data = readValue(length: Int(element.length))
        }
        
        element.endOffset = offset
        
        //print("\(offset) element \(element.vrMethod) \(element)")
                        
        return element
    }
    
    
    
    // MARK: -
    private func readDataTag(order:DicomConstants.ByteOrder = .LittleEndian) -> DataTag? {
        let tagData = self.read(length: 4)
        
        if tagData.count < 4 {
            return nil
        }
        
        return DataTag(withData:tagData, byteOrder:order)
    }
    
    
    
    private func readError(forLength length:Int, element: DataElement, message:String) -> DataElement {
        let v = ValidationResult(element, message: message, severity: .Fatal)
        
        dataset.internalValidations.append(v)
        dataset.isCorrupted = true
        
        Logger.error(message)
        
        return element
    }
    
    
    private func readVR(element:DataElement, vrMethod:DicomConstants.VRMethod = .Explicit) -> DicomConstants.VR {
        var vr:DicomConstants.VR? = nil
        
        if vrMethod == .Explicit {
            vr = DicomSpec.vr(for: read(length: 2).toString())
        }
        else {
            vr = DicomSpec.shared.vrForTag(withCode: element.tagCode())
        }
        
        if element.element == "0000" {
            vr = .UL
        }
        
        if vr == nil {
            vr = .UN
        }
        
        if     vr == .SQ ||
               vr == .OB ||
               vr == .OW ||
               vr == .OF ||
               vr == .SQ ||
               vr == .UT ||
               vr == .UN {
            // read 2 empty bytes
            if vrMethod == .Explicit {
                _ = read(length: 2)
            }
        }
        
        return vr!
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
        if length > 0 && (offset + length <= total) {
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
        let sequence:DataSequence = DataSequence(withTag:tag, parent: parent)
        var bytesRead = 0
                
        if length > 0 {
            // data items
            while (length > bytesRead) {
                let tag = DataTag(withData: read(length: 4), byteOrder: byteOrder)
                bytesRead += 4

                let itemLength = read(length: 4).toInt32(byteOrder: byteOrder)
                bytesRead += 4

                // CHECK FOR INVALID LENGTH
                if itemLength > total {
                    let message = "Fatal, cannot read length properly, decoded \(tag) length at offset(\(offset-4)) overflows (\(itemLength))"
                    return readError(forLength: Int(itemLength), element: sequence, message: message) as? DataSequence
                }
                if itemLength < -1 {
                    let message = "Fatal, cannot read length properly, decoded \(tag) length at offset(\(offset-4)) cannot be negative (\(itemLength))"
                    return readError(forLength: Int(itemLength), element: sequence, message: message) as? DataSequence
                }

                let item         = DataItem(withTag:tag, parent: sequence)
                item.length      = Int(itemLength)
                item.startOffset = offset - 12
                item.dataOffset  = offset
                sequence.items.append(item)
                
                if item.length == -1 {
                    while true {
                        let itemTag = DataTag(withData: read(length: 4), byteOrder: byteOrder)
                                                    
                        if itemTag.code == "fffee00d" {
                            forward(by: 4)
                            break
                        }
                                                
                        guard let newElement = readDataElement(dataset: self.dataset, parent: item, vrMethod: .Explicit, order: byteOrder, inTag: itemTag) else {
                            Logger.debug("Cannot read element in sequence \(tag) at \(self.offset)")
                            return nil
                        }
                        
                        item.elements.append(newElement)
                    }
                    
                    item.endOffset = offset
                } else {
                    // item data elements
                    var itemBytesRead = 0
                    
                    while(itemLength > itemBytesRead) {
                        let oldOffset = offset
                        
                        guard let newElement = readDataElement(dataset: self.dataset, parent: item, vrMethod: .Explicit, order: byteOrder) else {
                            Logger.debug("Cannot read element in sequence \(tag) at \(self.offset)")
                            return nil
                        }

                        item.elements.append(newElement)

                        itemBytesRead   += offset - oldOffset
                        bytesRead       += offset - oldOffset
                    }

                    item.endOffset = offset
                }
            }
        }
        // Undefined Length data items (length == FFFFFFFF)
        else if length == -1 {
            sequence.vrMethod = .Implicit
                                    
            // undefined length sequence loop
            while true {
                let tag = DataTag(withData: read(length: 4), byteOrder: byteOrder)
                
                // break sequence loop
                if tag.code == "fffee0dd" {
                    forward(by: 4)
                    break
                }
                else if tag.code == "fffee000" {
                    let item            = DataItem(withTag:tag, parent: sequence)
                    
                    // read item length
                    let itemLength      = Int(read(length: 4).toInt32(byteOrder: byteOrder))
                    item.length         = itemLength
                    item.startOffset    = offset - 8
                    item.dataOffset     = offset
                    item.vrMethod       = .Implicit
                    sequence.items.append(item)
                                        
                    // undefined length item
                    if item.length == -1 {
                        while true {
                            let itemTag = DataTag(withData: read(length: 4), byteOrder: byteOrder)
                                                        
                            if itemTag.code == "fffee00d" {
                                forward(by: 4)
                                break
                            }
                                                        
                            guard let newElement = readDataElement(dataset: self.dataset, parent: item, vrMethod: .Explicit, order: byteOrder, inTag: itemTag) else {
                                Logger.debug("Cannot read element in sequence \(tag) at \(self.offset)")
                                return nil
                            }
                            
                            item.elements.append(newElement)
                        }
                        
                        item.endOffset = offset
                    } else {
                        var itemBytesRead = 0
                        
                        while(itemLength > itemBytesRead) {
                            let oldOffset = offset
                            
                            guard let newElement = readDataElement(dataset: self.dataset, parent: item, vrMethod: .Explicit, order: byteOrder) else {
                                Logger.debug("Cannot read element in sequence \(tag) at \(self.offset)")
                                return nil
                            }

                            item.elements.append(newElement)

                            itemBytesRead += offset - oldOffset
                        }

                        item.endOffset = offset
                    }
                }
                else if tag.code == "fffee00d" {
                    forward(by: 4)
                    break
                }
            }
        }
        
        sequence.endOffset = offset
                
        return sequence
    }
    
    
    
    private func readItem(
        length:Int,
        byteOrder:DicomConstants.ByteOrder,
        parent: DataElement? = nil
    ) -> DataItem? {
        return nil
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
            if itemLength > total {
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
            if offset < total {
                itemTag = DataTag(withData: read(length: 4), byteOrder: byteOrder)
            }
        }
        
        return pixelSequence
    }
}
