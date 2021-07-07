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
    
    public var hasPreamble:Bool         = false
    public var vrMethod:VRMethod        = .Explicit
    public var byteOrder:ByteOrder      = .LittleEndian
    
    var stream:InputStream!
    /// A copy of the original stream used if we need to reset the read offset
    var backstream:InputStream!
    
    var offset = 0
    var total  = 0
    
    /**
     Init a DicomInputStream with a file path
     */
    public init(filePath:String) {
        dataset     = DataSet()
        stream      = InputStream(fileAtPath: filePath)
        backstream  = InputStream(fileAtPath: filePath)
        total       = Int(DicomFile.fileSize(path: filePath))
    }
    
    /**
    Init a DicomInputStream with a file URL
    */
    public init(url:URL) {
        dataset     = DataSet()
        stream      = InputStream(url: url)
        backstream  = InputStream(url: url)
        total       = Int(DicomFile.fileSize(path: url.path))
    }
    
    /**
    Init a DicomInputStream with a Data object
    */
    public init(data:Data) {
        dataset     = DataSet()
        stream      = InputStream(data: data)
        backstream  = InputStream(data: data)
        total       = data.count
    }
    
    
    // MARK: -
    public func readDataset(headerOnly:Bool = false, withoutPixelData:Bool = false) throws -> DataSet? {
        if stream == nil {
            throw StreamError.cannotOpenStream(message: "Cannot open stream, init failed")
        }
                
        stream.open()
        
        // try to read 128 00H + DCIM magic world
        let preambleData = read(length: 132)
        
        // no DCIM preamble found
        if preambleData == nil || preambleData?.toHex().lowercased() != DicomConstants.dicomPreamble.lowercased() {
            print("no DCIM preamble found, try to read dataset anyway")
        } else {
            // try to read DCIM magic word
            guard let magicData = preambleData?.dropFirst(128) else {
                throw StreamError.cannotReadStream(message: "Cannot read DICOM magic bytes (DICM)")
            }
            
            guard let magicWord = String(bytes: magicData, encoding: .ascii),
                  magicWord == DicomConstants.dicomMagicWord else {
                throw StreamError.notDicomFile(message: "Not a DICOM file, no DICM magic bytes found")
            }
            
            hasPreamble = true
        }
        
//        var tag = readDataTag(order: byteOrder)
//
//        if tag == nil {
//            throw StreamError.cannotReadStream(message: "Cannot read 4 first bytes, file is empty?")
//        }
//
//        // read DICOM preamble if exists
//        if tag!.group != "0008" {
//            // only the remaining bytes, we already read 4
//            _ = read(length: 124)
//
//            // read & check the magic word
//            guard let magic = read(length: 4) else {
//                throw StreamError.cannotReadStream(message: "Cannot read DICOM magic bytes (DICM)")
//            }
//
//            if let  magicWord  = String(bytes: magic, encoding: .ascii),
//                    magicWord != "DICM" {
//                throw StreamError.notDicomFile(message: "Not a DICOM file, no DICM magic bytes found")
//            }
//
//            hasPreamble = true
//        }
        
        // enforce vr Method
        if hasPreamble {
            // we kill the 00000000 not-a-tag read earlier
            // tag = nil
            // we will parse the DICOM meta Info header as Explicit VR
            vrMethod = .Explicit
        } else {
            // except for old ACR-NEMA file
            dataset.transferSyntax = TransferSyntax(TransferSyntax.implicitVRLittleEndian)
            vrMethod = .Implicit
            
            // reset stream and offset using backstream
            backstream.open()
            
            stream = backstream
            offset = 0
        }
                
        // preambule processing is done
        dataset.hasPreamble = hasPreamble
        dataset.vrMethod = vrMethod
        dataset.byteOrder = byteOrder
    
        // read elements to fill the dataset
        while(stream.hasBytesAvailable && offset < total && !dataset.isCorrupted) {
            var order = byteOrder
            
            // always read Meta Info Header as Little Endian
            if dataset.fileMetaInformationGroupLength + DicomConstants.dicomBytesOffset >= offset {
                order = .LittleEndian
            }
            
            if let newElement = readDataElement(dataset: dataset, parent: nil, vrMethod: vrMethod, order: order) {
                // header only option
                if headerOnly && newElement.tag.group != DicomConstants.metaInformationGroup {
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
                
                // determine file transfer syntax (used later to read the actual dataset part of the DICOM attributes)
                if newElement.name == "TransferSyntaxUID" {
                    vrMethod  = .Explicit
                    byteOrder = .LittleEndian
                    
                    if let ts = newElement.value as? String {
                        dataset.transferSyntax = TransferSyntax(ts)
                        
                        if dataset.transferSyntax.tsUID == TransferSyntax.implicitVRLittleEndian {
                            vrMethod  = .Implicit
                            byteOrder = .LittleEndian
                        }
                        else if dataset.transferSyntax.tsUID == TransferSyntax.explicitVRBigEndian {
                            vrMethod  = .Explicit
                            byteOrder = .BigEndian
                        }
                    }
                    
                    // update the dataset properties
                    dataset.vrMethod = vrMethod
                    dataset.byteOrder = byteOrder
                }
                                                            
                // append element to sub-datasets, if everything is OK
                if !dataset.isCorrupted {
                    dataset.add(element: newElement)
                    
                } else {
                    throw StreamError.datasetIsCorrupted(message: "Dataset is corrupted")
                }
            }
        }
        
        dataset.sortElements()
        
        backstream.close()
        stream.close()
        
        return dataset
    }
    


    
    private func forward(by bytes: Int) {
        // read into the void...
        _ = read(length: bytes)
    }
    
    
    internal func read(length:Int) -> Data? {
        // allocate memory buffer with given length
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: length)
        
        // fill the buffer by reading bytes with given length
        let read = stream.read(buffer, maxLength: length)
        
        if read < 0 || read < length {
            Logger.warning("Cannot read \(length) bytes")
            return nil
        }
        
        // create a Data object with filled buffer
        let data = Data(bytes: buffer, count: length)
        
        // maintain local offset
        offset += read
        
        // clean the memory
        buffer.deallocate()
        
        return data
    }

    
    
    // MARK: -
    private func readDataTag(order:ByteOrder = .LittleEndian) -> DataTag? {
        return DataTag(withStream: self, byteOrder:order)
    }
    
    
    private func readVR(element:DataElement, vrMethod:VRMethod = .Explicit) -> VR.VR? {
        var vr:VR.VR? = nil
        
        if vrMethod == .Explicit {
            guard let data = self.read(length: 2) else {
                return nil
            }
            
            vr = DicomSpec.vr(for: data.toString())
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
        vrMethod:VRMethod = .Explicit,
        vr:VR.VR,
        order:ByteOrder = .LittleEndian
    ) -> Int {
        var length:Int = 0
                        
        if vrMethod == .Explicit {
            if vr == .SQ {
                let bytes:Data = read(length: 4)!
                
                // undefined length check
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
                length = Int(read(length: 4)!.toInt32(byteOrder: order))
            } else {
                length = Int(read(length: 2)!.toInt16(byteOrder: order))
            }
        }
        else {
            // read implicit VR length
            length = Int(read(length: 4)!.toInt32(byteOrder: order))
        }
                
        return length
    }
    

    
    private func readValue(length:Int ) -> Data? {
        if length > 0 && (offset + length <= total) {
            return read(length: length)
        }
        
        return nil
    }
    
    
    
    private func readError(forLength length:Int, element: DataElement, message:String) -> DataElement {
        let v = ValidationResult(element, message: message, severity: .Fatal)
                
        dataset.internalValidations.append(v)
        dataset.isCorrupted = true
        
        Logger.error(message)
        
        return element
    }
    
    
    
    private func readDataElement(
        dataset:DataSet?                    = nil,
        parent:DataElement?                 = nil,
        vrMethod:VRMethod    = .Explicit,
        order:ByteOrder      = .LittleEndian,
        inTag:DataTag?                      = nil
    ) -> DataElement? {
        let startOffset = offset
        
        // we try to read the tag only if no `inTag` given
        guard let tag = inTag ?? readDataTag(order: order) else {
            Logger.error("Cannot read tag at offset at \(offset)")
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
        
        element.startOffset     = startOffset
        
        // enforce Explicit for group 0002 (Meta Info Header)
        element.vrMethod        = element.group == "0002" ? .Explicit : vrMethod
        
        // enforce Little Endian for group 0002 (Meta Info Header)
        element.byteOrder       = element.group == "0002" ? .LittleEndian : order
        element.vrOffset        = offset
        
        guard let vr = readVR(element:element, vrMethod: element.vrMethod) else {
            Logger.error("Cannot read VR at offset at \(offset)")
            return nil
        }
        
        element.vr              = vr
        element.lengthOffset    = offset
        element.length          = readLength(vrMethod: element.vrMethod, vr: element.vr, order: element.byteOrder)
        element.dataOffset      = offset
        
        
        // check for invalid length
        if element.length > total {
            let message = "Fatal, cannot read length properly, decoded \(tag) length at offset(\(offset-4)) overflows (\(element.length))"
            return readError(forLength: Int(element.length), element: element, message: message)
        }
        
        // read value data
        // if OB/OW but not in prefix header
        if tag.group != "0002" && (element.vr == .OW || element.vr == .OB) {
            if element.name == "PixelData" && element.length == -1 {
                guard let sequence = readPixelSequence(tag: tag, byteOrder: order) else {
                    Logger.error("Cannot read Pixel Sequence \(tag) at \(offset)")
                    return nil
                }
                
                sequence.parent         = element
                sequence.vr             = element.vr
                sequence.startOffset    = element.startOffset
                sequence.dataOffset     = element.dataOffset
                sequence.lengthOffset   = element.lengthOffset
                sequence.vrOffset       = element.vrOffset
                element                 = sequence

                // dead bytes
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
            sequence.vrMethod       = element.vrMethod
            sequence.startOffset    = element.startOffset
            sequence.dataOffset     = element.dataOffset
            sequence.lengthOffset   = element.lengthOffset
            sequence.vrOffset       = element.vrOffset
            sequence.length         = element.length
            element                 = sequence
        }
        else {
            element.data = readValue(length: Int(element.length))
        }
        
        element.endOffset = offset
        
        //print("element \(element)")
                        
        return element
    }
    
    
    
    
    private func readDataSequence(
        tag:DataTag,
        length:Int,
        byteOrder:ByteOrder,
        parent: DataElement? = nil
    ) -> DataSequence? {
        let sequence:DataSequence = DataSequence(withTag:tag, parent: parent)
        var bytesRead = 0
                
        if length > 0 {
            // data items
            while (length > bytesRead) {
                let tag = DataTag(withData: read(length: 4)!, byteOrder: byteOrder)
                bytesRead += 4

                let itemLength = read(length: 4)!.toInt32(byteOrder: byteOrder)
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
                        let itemTag = DataTag(withData: read(length: 4)!, byteOrder: byteOrder)
                                                    
                        if itemTag.code == "fffee00d" {
                            forward(by: 4)
                            break
                        }
                                                
                        guard let newElement = readDataElement(dataset: self.dataset, parent: item, vrMethod: vrMethod, order: byteOrder, inTag: itemTag) else {
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
                        
                        guard let newElement = readDataElement(dataset: self.dataset, parent: item, vrMethod: vrMethod, order: byteOrder) else {
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
                let tag = DataTag(withData: read(length: 4)!, byteOrder: byteOrder)
                
                // break sequence loop
                if tag.code == "fffee0dd" {
                    forward(by: 4)
                    break
                }
                else if tag.code == "fffee000" {
                    let item            = DataItem(withTag:tag, parent: sequence)
                    
                    // read item length
                    let itemLength      = Int(read(length: 4)!.toInt32(byteOrder: byteOrder))
                    item.length         = itemLength
                    item.startOffset    = offset - 8
                    item.dataOffset     = offset
                    item.vrMethod       = .Implicit
                    sequence.items.append(item)
                                        
                    // undefined length item
                    if item.length == -1 {
                        while true {
                            let itemTag = DataTag(withData: read(length: 4)!, byteOrder: byteOrder)
                                                        
                            if itemTag.code == "fffee00d" {
                                forward(by: 4)
                                break
                            }
                                                        
                            guard let newElement = readDataElement(dataset: self.dataset, parent: item, vrMethod: vrMethod, order: byteOrder, inTag: itemTag) else {
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
                            
                            guard let newElement = readDataElement(dataset: self.dataset, parent: item, vrMethod: vrMethod, order: byteOrder) else {
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
    
    
    // Unused by now..
    private func readItem(
        length:Int,
        byteOrder:ByteOrder,
        parent: DataElement? = nil
    ) -> DataItem? {
        return nil
    }
    
    
    
    private func readPixelSequence(tag:DataTag, byteOrder:ByteOrder) -> PixelSequence? {
        let pixelSequence = PixelSequence(withTag: tag)
        
        // read item tag
        var itemTag = DataTag(withData: read(length: 4)!, byteOrder: byteOrder)
                
        while itemTag.code != "fffee0dd" {
            // create item
            let item            = DataItem(withTag: itemTag)
            item.startOffset    = offset - 4
            item.dataOffset     = offset
            item.vrMethod       = .Explicit
            
            // read item length
            let itemLength = read(length: 4)!.toInt32(byteOrder: byteOrder)
                                    
            // check for invalid lengths
            if itemLength > total {
                let message = "Fatal, cannot read PixelSequence item length properly, decoded length at offset(\(offset-4)) overflows (\(itemLength))"
                return readError(forLength: Int(itemLength), element: pixelSequence, message: message) as? PixelSequence
            }
            
            item.length = Int(itemLength)
            
            if itemLength > 0 {
                item.data = read(length: Int(itemLength))
            }
            
            if itemLength < -1 {
                break
            }
            
            pixelSequence.items.append(item)
            
            // read next again
            if offset < total {
                itemTag = DataTag(withData: read(length: 4)!, byteOrder: byteOrder)
            }
        }
        
        return pixelSequence
    }
}
