//
//  DicomInputStream.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 10/06/2021.
//  Copyright © 2021 OPALE. All rights reserved.
//

import Foundation

public class DicomInputStream: OffsetInputStream {
    private var dataset:DataSet!
    
    public var hasPreamble:Bool         = false
    public var vrMethod:VRMethod        = .Explicit
    public var byteOrder:ByteOrder      = .LittleEndian
    
    /**
     Init a DicomInputStream with a file path
     */
    public override init(filePath:String) {
        super.init(filePath: filePath)
        dataset = DataSet()
    }
    
    /**
    Init a DicomInputStream with a file URL
    */
    public override init(url:URL) {
        super.init(url: url)
        dataset = DataSet()
    }
    
    /**
    Init a DicomInputStream with a Data object
    */
    public override init(data:Data) {
        super.init(data: data)
        dataset = DataSet()
    }
    
    
    // MARK: -
    /**
     Reads a data set from the stream.
     
     - Parameters:
        - headerOnly: only read the header. Default is set to false
        - withoutPixelData: avoid reading the pixel data
     - Throws: StreamError.notDicomFile, StreamError.cannotReadStream
     - Returns: the `DataSet` read from the stream
     */
    public func readDataset(headerOnly:Bool = false, withoutPixelData:Bool = false, enforceVR:Bool = true) throws -> DataSet? {
        if stream == nil {
            throw StreamError.cannotOpenStream(message: "Cannot open stream, init failed")
        }
                
        self.open()
        
        
        do {
            // try to read 128 00H + DCIM magic world
            let preambleData = try read(length: 132)
            
            // no DCIM preamble found
            if preambleData.toHex().lowercased() != DicomConstants.dicomPreamble.lowercased() {
                // print("no DCIM preamble found, try to read dataset anyway")
                hasPreamble = false
                
            } else {
                // try to read DCIM magic word
                let magicData = preambleData.dropFirst(128)// else {
                //    throw StreamError.cannotReadStream(message: "Cannot read DICOM magic bytes (DICM)")
                //}
                
                guard let magicWord = String(bytes: magicData, encoding: .ascii),
                      magicWord == DicomConstants.dicomMagicWord else {
                    throw StreamError.notDicomFile(message: "Not a DICOM file, no DICM magic bytes found")
                }
                
                hasPreamble = true
            }
        } catch {
            throw StreamError.cannotReadStream(message: "Cannot read DICOM magic bytes (DICM)")
        }
        

        
        // enforce vr Method
        if hasPreamble {
            // we kill the 00000000 not-a-tag read earlier
            // tag = nil
            // we will parse the DICOM meta Info header as Explicit VR
            vrMethod = .Explicit
        } else {
            if enforceVR == true {
                // except for old ACR-NEMA file
                dataset.transferSyntax = TransferSyntax(TransferSyntax.implicitVRLittleEndian)
                vrMethod = .Implicit
            }
            
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
        
        self.close()
        
        return dataset
    }
    


    
    // MARK: -
    /**
     Tries to reads a `DataTag` with a given byte order
     
     - Parameter order: the byte order to read the stream to
     - Returns: the `DataTag` read from the stream, or `nil` on failure
     */
    private func readDataTag(order:ByteOrder = .LittleEndian) -> DataTag? {
        return DataTag(withStream: self, byteOrder:order)
    }
    
    /**
     Tries to reads a Value Representation
     
     If the data element has an explicit VR, the stream can read the VR. If the VR is implicit, it
     means the stream does not contains the VR, but we can catch the VR with the data element tag, that's
     why the data element is provided in the parameters
     
     - Parameters:
        - element: the data element to get the tag (and thus the vr)
        - vrMethod: is the VR explicit (written in the data) or implicit (not written in the data) ?
     - Returns: the value representation of the element, or nil
     */
    private func readVR(element:DataElement, vrMethod:VRMethod = .Explicit) throws -> VR.VR {
        var vr:VR.VR? = nil
        
        if vrMethod == .Explicit {
            let data = try self.read(length: 2)// else {
            //    return nil
            //}
            
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
                _ = try read(length: 2)
            }
        }
        
        return vr!
    }
    
    /**
     Reads the length of a data element
     
     - Parameters:
        - vrMethod: is the VR explicit (written in the data) or implicit (not written in the data) ?
        - vr: the VR of the data element the length belongs to
        - order: the byte order of the length bytes
     - Returns: the length of a data element
     */
    private func readLength(
        vrMethod:VRMethod = .Explicit,
        vr:VR.VR,
        order:ByteOrder = .LittleEndian
    ) throws -> Int {
        var length:Int = 0
                        
        if vrMethod == .Explicit {
            if vr == .SQ {
                let bytes:Data = try read(length: 4)
                
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
                length = Int(try read(length: 4).toInt32(byteOrder: order))
            } else {
                length = Int(try read(length: 2).toInt16(byteOrder: order))
            }
        }
        else {
            // read implicit VR length
            length = try Int(read(length: 4).toInt32(byteOrder: order))
        }
                
        return length
    }
    

    /**
     Tries to read a value of a `DataElement`.
     
     - Parameter length: the length of the value
     - Returns: The value as `Data`
     */
    private func readValue(length:Int) throws -> Data {
        //if length > 0 && (offset + length <= total) {
            return try read(length: length)
        //}
        
        //return nil
    }
    
    
    
    private func readError(forLength length:Int, element: DataElement, message:String) -> DataElement {
        let v = ValidationResult(element, message: message, severity: .Fatal)
                
        dataset.internalValidations.append(v)
        dataset.isCorrupted = true
        
        Logger.error(message)
        
        return element
    }
    
    
    /**
     Tries to read a data element from the stream
     
     - Parameters:
        - dataset:
        - parent:
        - vrMethod:
        - order:
        - inTag:
     - Returns: the data element read on success, or nil on failure
     */
    private func readDataElement(
        dataset:DataSet?                    = nil,
        parent:DataElement?                 = nil,
        vrMethod:VRMethod    = .Explicit,
        order:ByteOrder      = .LittleEndian,
        inTag:DataTag?                      = nil
    ) throws -> DataElement? {
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
        
        let vr = try readVR(element:element, vrMethod: element.vrMethod)// else {
        //    Logger.error("Cannot read VR at offset at \(offset)")
        //    return nil
        //}
        
        element.vr              = vr
        element.lengthOffset    = offset
        element.length          = try readLength(vrMethod: element.vrMethod, vr: element.vr, order: element.byteOrder)
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
                let sequence = try readPixelSequence(tag: tag, byteOrder: order)// else {
                //    Logger.error("Cannot read Pixel Sequence \(tag) at \(offset)")
                //    return nil
                //}
                
                sequence.parent         = element
                sequence.vr             = element.vr
                sequence.startOffset    = element.startOffset
                sequence.dataOffset     = element.dataOffset
                sequence.lengthOffset   = element.lengthOffset
                sequence.vrOffset       = element.vrOffset
                element                 = sequence

                // dead bytes
                try forward(by: 4)

            } else {
                element.data = try readValue(length: Int(element.length))
            }
        }
        else if element.vr == .SQ {
            guard let sequence = try readDataSequence(tag:element.tag, length: Int(element.length), byteOrder:order) else {
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
            element.data = try readValue(length: Int(element.length))
        }
        
        element.endOffset = offset
        
        //print("element \(element)")
                        
        return element
    }
    
    
    
    /**
     Tries to read a sequence (SQ) from the stream
     
     - Remark: why provide the length when the parent data element has it ? same for the tag, same for the byte order
     
     - Parameters:
        - tag: the tag of the sequence
        - length: length of the sequence
        - byteOrder: byte order of the sequence
        - parent: the data element containing the sequence
     - Returns: the data sequence read
     */
    private func readDataSequence(
        tag:DataTag,
        length:Int,
        byteOrder:ByteOrder,
        parent: DataElement? = nil
    ) throws -> DataSequence? {
        let sequence:DataSequence = DataSequence(withTag:tag, parent: parent)
        var bytesRead = 0
                
        if length > 0 {
            // data items
            while (length > bytesRead) {
                let tag = DataTag(withData: try read(length: 4), byteOrder: byteOrder)
                bytesRead += 4

                let itemLength = try read(length: 4).toInt32(byteOrder: byteOrder)
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
                        let itemTag = DataTag(withData: try read(length: 4), byteOrder: byteOrder)
                                                    
                        if itemTag.code == "fffee00d" {
                            try forward(by: 4)
                            break
                        }
                                                
                        guard let newElement = try readDataElement(dataset: self.dataset, parent: item, vrMethod: vrMethod, order: byteOrder, inTag: itemTag) else {
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
                        
                        guard let newElement = try readDataElement(dataset: self.dataset, parent: item, vrMethod: vrMethod, order: byteOrder) else {
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
                let tag = DataTag(withData: try read(length: 4), byteOrder: byteOrder)
                
                // break sequence loop
                if tag.code == "fffee0dd" {
                    try forward(by: 4)
                    break
                }
                else if tag.code == "fffee000" {
                    let item            = DataItem(withTag:tag, parent: sequence)
                    
                    // read item length
                    let itemLength      = Int(try read(length: 4).toInt32(byteOrder: byteOrder))
                    item.length         = itemLength
                    item.startOffset    = offset - 8
                    item.dataOffset     = offset
                    item.vrMethod       = .Implicit
                    sequence.items.append(item)
                                        
                    // undefined length item
                    if item.length == -1 {
                        while true {
                            let itemTag = DataTag(withData: try read(length: 4), byteOrder: byteOrder)
                                                        
                            if itemTag.code == "fffee00d" {
                                try forward(by: 4)
                                break
                            }
                                                        
                            guard let newElement = try readDataElement(dataset: self.dataset, parent: item, vrMethod: vrMethod, order: byteOrder, inTag: itemTag) else {
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
                            
                            guard let newElement = try readDataElement(dataset: self.dataset, parent: item, vrMethod: vrMethod, order: byteOrder) else {
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
                    try forward(by: 4)
                    break
                }
            }
        }
        
        sequence.endOffset = offset
                
        return sequence
    }
    
    
    // Unused by now..
    /// Returns nil
    private func readItem(
        length:Int,
        byteOrder:ByteOrder,
        parent: DataElement? = nil
    ) -> DataItem? {
        return nil
    }
    
    
    /**
     Tries to read a pixel sequence from a stream.
     
     - Remark: why provide the tag, knowing the pixel data always have the same tag, which is (fffee,0dd)
     
     - Parameters:
        - tag: the tag of the pixel sequence
        - byteOrder: how to read the pixel data
     - Returns: the pixel sequence read
     */
    private func readPixelSequence(tag:DataTag, byteOrder:ByteOrder) throws -> PixelSequence {
        let pixelSequence = PixelSequence(withTag: tag)
        
        // read item tag
        var itemTag = DataTag(withData: try read(length: 4), byteOrder: byteOrder)
                
        while itemTag.code != "fffee0dd" {
            // create item
            let item            = DataItem(withTag: itemTag)
            item.startOffset    = offset - 4
            item.dataOffset     = offset
            item.vrMethod       = .Explicit
            
            // read item length
            let itemLength = try read(length: 4).toInt32(byteOrder: byteOrder)
                                    
            // check for invalid lengths
            if itemLength > total {
                let message = "Fatal, cannot read PixelSequence item length properly, decoded length at offset(\(offset-4)) overflows (\(itemLength))"
                return readError(forLength: Int(itemLength), element: pixelSequence, message: message) as! PixelSequence
            }
            
            item.length = Int(itemLength)
            
            if itemLength > 0 {
                item.data = try read(length: Int(itemLength))
            }
            
            if itemLength < -1 {
                break
            }
            
            pixelSequence.items.append(item)
            
            // read next again
            if offset < total {
                itemTag = DataTag(withData: try read(length: 4), byteOrder: byteOrder)
            }
        }
        
        return pixelSequence
    }
}
