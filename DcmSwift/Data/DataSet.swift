//
//  Dataset.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 17/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation

public class DataSet: DicomObject {
    public var fileMetaInformationGroupLength:Int32 = 0
    public var transferSyntax:String                = DicomConstants.implicitVRLittleEndian
    public var vrMethod:DicomConstants.VRMethod     = .Implicit
    public var byteOrder:DicomConstants.ByteOrder   = .LittleEndian
    public var forceExplicit:Bool                   = false
    public var prefixHeader:Bool                    = true
    internal var isCorrupted:Bool                   = false
    
    public var metaInformationHeaderElements:[DataElement]  = []
    public var datasetElements:[DataElement]                = []
    public var allElements:[DataElement]                    = []
    
    public var internalValidations:[ValidationResult]       = []
    
    private var inputStream:DicomInputStream!
    private var data:Data!
    
    
    public override init() {
        prefixHeader = false
        
        
    }
    
    
    public init?(withData data:Data, readHeader:Bool = true) {
        self.data           = data
        self.prefixHeader   = readHeader
        self.inputStream    = DicomInputStream(data: data)
    }
    
    
    
    override public var description: String {
        var string = ""
        
        sortElements()
        
        for e in allElements {
            string += e.description + "\n"
        }
        
        return string
    }
    
    
    
    // MARK: - Public methods
    public func loadData(_ withData:Data? = nil) -> Bool {
        if withData != nil {
            data = withData
        }
        
        if prefixHeader {
            inputStream.forward(by: DicomConstants.dicomBytesOffset)
        }
                                
        // reset elements arrays
        metaInformationHeaderElements  = []
        datasetElements                = []
        allElements                    = []
        
        while(inputStream.hasBytesAvailable && !isCorrupted) {
            let newElement = readDataElement(stream: inputStream)

            if newElement.name == "FileMetaInformationGroupLength" {
                fileMetaInformationGroupLength = newElement.value as! Int32
            }
                        
            // determine transfer syntax
            if newElement.name == "TransferSyntaxUID" {
                transferSyntax = newElement.value as! String
                
                if transferSyntax == DicomConstants.implicitVRLittleEndian {
                    vrMethod  = .Implicit
                    byteOrder = .LittleEndian
                }
                else if transferSyntax == DicomConstants.explicitVRBigEndian {
                    vrMethod  = .Explicit
                    byteOrder = .BigEndian
                }
                else {
                    vrMethod  = .Explicit
                    byteOrder = .LittleEndian
                }
            }
            
            // append to sub-datasets
            if !isCorrupted {
                //Logger.debug(newElement)
                
                if newElement.group != DicomConstants.metaInformationGroup {
                    datasetElements.append(newElement)
                }
                else {
                    metaInformationHeaderElements.append(newElement)
                    
                }
                
                allElements.append(newElement)
            }
        }
        
        // be sure to sort all dataset elements by group, then element
        sortElements()
        
        return true
    }

    
    
    
    
     public override func toData(vrMethod inVrMethod:DicomConstants.VRMethod = .Explicit, byteOrder inByteOrder:DicomConstants.ByteOrder = .LittleEndian) -> Data {
        var newData = Data()
        
        var finalVR     = vrMethod
        var finalOrder  = byteOrder
        
        if vrMethod != inVrMethod {
            finalVR = inVrMethod
        }
        if byteOrder != inByteOrder {
            finalOrder = inByteOrder
        }
        
        if prefixHeader {
            // write 128 bytes preamble
            newData.append(Data(repeating: 0x00, count: 128))
            
            // write DICM magic word
            newData.append(DicomConstants.dicomMagicWord.data(using: .utf8)!)
        }
        
        // be sure element are sorted properly before write
        sortElements()
        
        // append meta header elements as binary data
        for element in allElements {
            //print(type(of: element))
            newData.append(write(dataElement: element, vrMethod:finalVR, byteOrder:finalOrder))
        }
        
        return newData
    }
    
    
    public func DIMSEData(vrMethod inVrMethod:DicomConstants.VRMethod = .Explicit, byteOrder inByteOrder:DicomConstants.ByteOrder = .LittleEndian) -> Data {
        var data = Data()
        
        var finalVR     = vrMethod
        var finalOrder  = byteOrder
        
        if vrMethod != inVrMethod {
            finalVR = inVrMethod
        }
        if byteOrder != inByteOrder {
            finalOrder = inByteOrder
        }
        
        sortElements()
        
        for element in datasetElements {
            data.append(element.toData(vrMethod: finalVR, byteOrder: finalOrder))
        }
        
        return data
    }

    
    
    public override func toXML() -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        
        xml += "<NativeDicomModel xml:space=\"preserve\">"
        
        for element in allElements {
            xml += element.toXML()
        }
        
        xml += "</NativeDicomModel>"
        
        return xml
    }
    
    
    override public func toJSONArray() -> Any {
        var json:[String:[String:Any]] = [:]
        
        sortElements()
        
        for element in allElements {
            
            var val:Any = ""
            
            if element.isMultiple {
                val = element.values.map { $0.value == "" ? "null" : $0.value }
            }
            else {
                if  element.vr == .OB ||
                    element.vr == .OD ||
                    element.vr == .OF ||
                    element.vr == .OW ||
                    element.vr == .UN {
                    if (element.data != nil) {
                        val = element.data.base64EncodedString()
                        
                    } else {
                        val = ""
                    }
                }
                else {
                    val = "\(element.value)"
                }
            }
            
            json[element.tagCode().uppercased()] = [
                "vr": "\(element.vr)",
                "value": val
            ]
        }
        
        return json
    }
    
    
    
    public func value(forTag tag:String ) -> Any? {
        for el in allElements {
            if el.name == tag {
                return el.value
            }
        }
        return nil
    }
    
    
    public func string(forTag tag:String ) -> String? {
        for el in allElements {
            if el.name == tag {
                return (el.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
    
    
    public func integer32(forTag tag:String ) -> Int32? {
        for el in allElements {
            if el.name == tag {
                if let v = el.value as? Int32 {
                    return v
                }
            }
        }
        return nil
    }
    
    
    public func integer16(forTag tag:String ) -> Int16? {
        for el in allElements {
            if el.name == tag {
                if let v = el.value as? Int16 {
                    return v
                }
            }
        }
        return 0
    }
    
    
    public func date(forTag tag:String ) -> Date? {
        for el in allElements {
            if el.name == tag {
                if let str = el.value as? String {
                    return Date(dicomDate: str)
                }
            }
        }
        return nil
    }
    
    
    public func datetime(forTag tag:String ) -> Date? {
        for el in allElements {
            if el.name == tag {
                if let str = el.value as? String {
                    return Date(dicomDateTime: str)
                }
            }
        }
        return nil
    }
    
    
    public func time(forTag tag:String ) -> Date? {
        for el in allElements {
            if el.name == tag {
                if let str = el.value as? String {
                    return Date(dicomTime: str)
                }
            }
        }
        return nil
    }
    
    
    
    
    public func set(value:Any, toElement element:DataElement) -> Bool {
        if isCorrupted {
            return false
        }
        
        let ret = element.setValue(value)
        
        recalculateOffsets()
        
        return ret
    }
    
    
    public func set(value:Any, forTagName name:String) -> DataElement? {
        if isCorrupted {
            return nil
        }
        
        // element already exists in dataset
        if let element = element(forTagName: name) {
            return set(value: value, toElement: element) ? element : nil
        }
        
        // element does not already exist in dataset
        if let element = DataElement(withTagName: name, dataset: self) {

            if element.setValue(value) {
                allElements.append(element)
                
                if (element.group == "0002") {
                    metaInformationHeaderElements.append(element)
                } else {
                    datasetElements.append(element)
                }
                
                sortElements()
                recalculateOffsets()
                
                return element
            }
        }
        
        return nil
    }
    
    
    
    public func hasElement(forTagName name:String) -> Bool {
        return element(forTagName: name) != nil
    }
    
    
    
    public func element(forTagName name:String) -> DataElement? {
        for el in allElements {
            if el.name == name {
                return el
            }
        }
        return nil
    }
    
    
    
    public func remove(dataElement element:DataElement) -> DataElement {
        if let index = allElements.firstIndex(where: {$0 === element}) {
            allElements.remove(at: index)
        }
        if let index = metaInformationHeaderElements.firstIndex(where: {$0 === element}) {
            metaInformationHeaderElements.remove(at: index)
        }
        if let index = datasetElements.firstIndex(where: {$0 === element}) {
            datasetElements.remove(at: index)
        }
        return element
    }
    

    
    
    
    
    public func write(
        atPath path:String,
        vrMethod inVrMethod:DicomConstants.VRMethod? = nil,
        byteOrder inByteOrder:DicomConstants.ByteOrder? = nil
    ) -> Bool {
        var finalVR     = vrMethod
        var finalOrder  = byteOrder
        
        if let inVR = inVrMethod {
            finalVR = inVR
        }
        if let inOrder = inByteOrder {
            finalOrder = inOrder
        }
        
        let data = toData(vrMethod: finalVR, byteOrder: finalOrder)
        
        // overwrite file
        if FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                Swift.print("Error : Cannot overwrite file at path : \(path)")
                return false
            }
        }
        
        // write file to FS        
        return FileManager.default.createFile(atPath: path, contents: data, attributes: nil)
    }
}

// MARK: - Private DataSet methods
extension DataSet {
    private func recalculateOffsets() {
//        if let f = allElements.first {
//            var offset = f.startOffset
//
//            for e in allElements {
//                e.startOffset = offset
//                e.dataOffset = offset + 4
//
//                if e.vr == .OB {
//                    e.endOffset = offset + 10 + e.length
//                } else {
//                    e.endOffset = offset + 8 + e.length
//                }
//
//                offset = e.endOffset
//            }
//        }
    }
    
    
    
    
    private func sortElements() {
        allElements = allElements.sorted(by: { (a, b) -> Bool in
            if a.group != b.group {
                return a.group < b.group
            }
            return a.element < b.element
        })
        
        metaInformationHeaderElements = metaInformationHeaderElements.sorted(by: { (a, b) -> Bool in
            if a.group != b.group {
                return a.group < b.group
            }
            return a.element < b.element
        })
        
        datasetElements = datasetElements.sorted(by: { (a, b) -> Bool in
            if a.group != b.group {
                return a.group < b.group
            }
            return a.element < b.element
        })
    }
    
    
    
    
    
    
    private func readDataElement(stream:DicomInputStream) -> DataElement {
        var order:DicomConstants.ByteOrder          = .LittleEndian
        var localVRMethod:DicomConstants.VRMethod   = .Explicit
        var length:Int                              = 0
                
        // set local byte order to enforce Little Endian for Prefix Header elements
        if byteOrder == .BigEndian && stream.offset >= fileMetaInformationGroupLength+144 {
            order = .BigEndian
        } else {
            order = .LittleEndian
        }

        if prefixHeader {
            // set local VR Method to enforce Explicit for Prefix Header elements
            if vrMethod == .Implicit && stream.offset >= fileMetaInformationGroupLength+144 {
                localVRMethod = .Implicit
            } else {
                localVRMethod = .Explicit
            }
        } else {
            // force implicit if no header (truncated DICOM file, ACR-NEMA, etc)
            localVRMethod = .Implicit
        }
        
        if forceExplicit {
            localVRMethod = .Explicit
        }
        
        // read tag
        let tag = stream.readDataTag(order: order)!
                    
        // create new data element
        var element:DataElement = DataElement(withTag:tag, dataset: self)
        element.startOffset = stream.offset
        element.byteOrder   = order

        // read VR
        if localVRMethod == .Explicit {
            element.vr = DicomSpec.vr(for: stream.read(length: 2).toString())
            
            // 0000H reserved VR bytes
            // http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_7.5.html
            if element.vr == .SQ {
                stream.forward(by: 2)
            }
            // Table 7.1-1. Data Element with Explicit VR of OB, OW, OF, SQ, UT or UN
            // http://dicom.nema.org/Dicom/2013/output/chtml/part05/chapter_7.html
            else if element.vr == .OB ||
                    element.vr == .OW ||
                    element.vr == .OF ||
                    element.vr == .SQ ||
                    element.vr == .UT ||
                    element.vr == .UN {
                stream.forward(by: 2)
            }
        }
        else {
            // if it's an implicit element group length
            // we set the VR as undefined
            if element.element == "0000" {
                element.vr = .UL
            }
            // else we take the VR from the spec
            else {
                // TODO: manage VR couples (ex: "OB/OW" in xml spec)
                element.vr = DicomSpec.shared.vrForTag(withCode:element.tag.code)
            }
        }

        // read length
        if localVRMethod == .Explicit {
            if element.vr == .SQ {
                let bytes:Data = stream.read(length: 4)
                
                if bytes == Data([0xff, 0xff, 0xff, 0xff]) {
                    length = -1
                } else {
                    length = Int(bytes.toInt32(byteOrder: order))
                    //stream.forward(by: 4)
                }
            } else if   element.vr == .OB ||
                        element.vr == .OW ||
                        element.vr == .OF ||
                        element.vr == .SQ ||
                        element.vr == .UT ||
                        element.vr == .UN {
                length = Int(stream.read(length: 4).toInt32(byteOrder: order))
            } else {
                length = Int(stream.read(length: 2).toInt16(byteOrder: order))
            }
        }
        else {
            // implicit length
            length = Int(stream.read(length: 4).toInt32(byteOrder: order))
        }
                                
        // CHECK FOR INVALID LENGTH
        if length > data.count {
            let message = "Fatal, cannot read \(tag) length properly, decoded length at offset(\(stream.offset-4)) overflows (\(length))"
            return readError(forLength: Int(length), element: element, message: message)
        }
        
//        if length <= -1 {
//            let message = "Fatal, cannot read length properly, decoded length at offset(\(os-4)) cannot be negative (\(length))"
//            return readError(forLength: Int(length), element: element, message: message)
//        }
        
        // MISSING VR FOR IMPLICIT ELEMENT
        // TODO: if VR is implicit, do we need to use the correpsonding tag VR ?
        element.dataOffset = stream.offset
        
        // read value data
        if element.vr == .OW || element.vr == .OB {
            if element.name == "PixelData" && length == -1 {
                let sequence = readPixelSequence(tag: tag, stream: stream, byteOrder: order)
                sequence.parent         = element
                sequence.vr             = element.vr
                sequence.startOffset    = element.startOffset
                sequence.dataOffset     = element.dataOffset
                element                 = sequence
                
                stream.forward(by: 4)
            }
            else {
                element.data = stream.read(length: Int(length))
            }
        }
        else if element.vr == .SQ {
            let sequence = readDataSequence(tag:element.tag, stream: stream, length: Int(length), byteOrder:order)
            sequence.parent         = element
            sequence.vr             = element.vr
            sequence.startOffset    = element.startOffset
            sequence.dataOffset     = element.dataOffset
            element                 = sequence
            
            if sequence.vrMethod == .Implicit {
                length = 0
            }
        }
        else {
            // TODO: manage default value better ?
            if length > 0 && (stream.offset + length < data.count) {
                element.data = stream.read(length: Int(length))
            }
        }
                
        element.length = Int(length)
        element.endOffset = stream.offset
        
        return element
    }
    
    
    
    private func readError(forLength length:Int, element: DataElement, message:String) -> DataElement {
        let v = ValidationResult(element, message: message, severity: .Fatal)
        
        internalValidations.append(v)
        isCorrupted = true
        
        Logger.error(message)
        
        return element
    }
    
    
    
    
    private func readDataSequence(
        tag: DataTag,
        stream: DicomInputStream,
        length: Int,
        byteOrder: DicomConstants.ByteOrder
    ) -> DataSequence {
        let sequence:DataSequence = DataSequence(withTag:tag)
        var bytesRead = 0
        var hasEnded = false
        
        if length > 0 {
            // data items
            while (!hasEnded && length > bytesRead && stream.hasBytesAvailable) {
                let tag = stream.readDataTag(order: byteOrder)!
                bytesRead += 4
                
                let itemLength = stream.read(length: 4).toInt32(byteOrder: byteOrder)
                bytesRead += 4
                
                // CHECK FOR INVALID LENGTH
                if itemLength > data.count {
                    let message = "Fatal, cannot read length properly, decoded length at offset(\(stream.offset-4)) overflows (\(itemLength))"
                    return readError(forLength: Int(itemLength), element: sequence, message: message) as! DataSequence
                }
                if itemLength < -1 {
                    let message = "Fatal, cannot read length properly, decoded length at offset(\(stream.offset-4)) cannot be negative (\(itemLength))"
                    return readError(forLength: Int(itemLength), element: sequence, message: message) as! DataSequence
                }

                let item         = DataItem(withTag:tag, parent: sequence)
                item.length      = Int(itemLength)
                item.startOffset = stream.offset - 12
                item.dataOffset  = stream.offset
                sequence.items.append(item)
                                
                // item data elements
                var itemBytesRead = 0
                
                while(itemLength > itemBytesRead && stream.hasBytesAvailable) {
                    let newElement = readDataElement(stream: stream)
                                        
                    newElement.parent = item
                    
                    item.elements.append(newElement)
                    
//                    var read = 0
//
//                    if newElement.data != nil {
//                        read = newElement.data.count
//                    }
                    
                    itemBytesRead   += newElement.endOffset - newElement.startOffset
                    bytesRead       += newElement.endOffset - newElement.startOffset
                    
                    // we check the next tag for fffe,e000 ItemDelimitationItem
                    let nextTag = stream.readDataTag(order: byteOrder)
                    
                    if !(nextTag != nil) || nextTag!.code == "fffee0dd" {
                        stream.forward(by: 4)
                        
                        hasEnded = true
                        
                        break
                    }
                    else if nextTag!.code == "fffee000" {
                        stream.backward(by: 4)

                        break
                    }
                    else {
                        // if the next tag is not an item delimiter,
                        // so we forward the stream offset
                        // before reading the next DataElement
                        stream.backward(by: 4)
                    }
                }
                
                item.endOffset = stream.offset
            }
        }
        // Undefined Length data items (length == FFFFFFFF)
        else if length == -1 {
            sequence.vrMethod = .Implicit
            
            var tag = stream.readDataTag(order: byteOrder)!
            
            while(tag.code == "fffee000" && stream.hasBytesAvailable) {
                let subdata = stream.read(length: 4)
                var itemLength:Int16 = 0
                                
                let item            = DataItem(withTag:tag, parent: sequence)
                item.startOffset    = stream.offset - 8
                item.dataOffset     = stream.offset
                item.vrMethod       = .Implicit
                
                sequence.items.append(item)
                
                // Undefined Length data elements (ffffffff)
                if subdata == Data([0xff, 0xff, 0xff, 0xff]) {
                    var reachEnd = false
                    
                    while(reachEnd == false && stream.hasBytesAvailable) {
                        let subtag = stream.readDataTag(order: byteOrder)!
                        
                        if subtag.code != "fffee00d" {
                            let newElement = readDataElement(stream: stream)
                            newElement.parent = item
                            
                            item.elements.append(newElement)
                        } else {
                            reachEnd = true
                            stream.offset += 8
                        }
                    }
                    
                    if tag.code == "fffee0dd" {
                        stream.offset += 8
                    }
                    
                    tag = stream.readDataTag(order: byteOrder)!
                }
                // Length defined data elements
                else {
                    itemLength  = subdata.toInt16(byteOrder: byteOrder)
                    item.length = Int(itemLength)
                    
                    var itemBytesRead = 0
                    while(itemLength > itemBytesRead && stream.hasBytesAvailable) {
                        let newElement = readDataElement(stream: stream)
                        newElement.parent = item
                        item.elements.append(newElement)
                        
                        itemBytesRead += newElement.endOffset - stream.offset
                        bytesRead += newElement.endOffset - stream.offset
                    }
                    
                    if let t = stream.readDataTag(order: byteOrder) {
                        tag = t
                    } else {
                        return sequence
                    }
                }
                
                item.endOffset = stream.offset
            }
            
            stream.offset += 4
            
            // in order to return the good offset
            return sequence
        }
            
        // empty sequence
        else if length == 0 {
            // TODO: fix issue when a empty sequence is the element of an item
        }
                        
        return sequence
    }
    
    
    
    
    private func readPixelSequence(tag:DataTag, stream:DicomInputStream, byteOrder:DicomConstants.ByteOrder) -> PixelSequence {
        let pixelSequence = PixelSequence(withTag: tag)
        
        // read item tag
        var itemTag = stream.readDataTag(order: byteOrder)!
                
        while itemTag.code != "fffee0dd" {
            // read item
            let item            = DataItem(withTag: itemTag)
            item.startOffset    = stream.offset - 4
            item.dataOffset     = stream.offset
            item.vrMethod       = .Explicit
            
            pixelSequence.items.append(item)
            
            // read item length
            let itemLength = stream.read(length: 4).toInt32(byteOrder: byteOrder)
                        
            // CHECK FOR INVALID LENGTH
            if itemLength > data.count {
                let message = "Fatal, cannot read length properly, decoded length at offset(\(stream.offset-4)) overflows (\(itemLength))"
                return readError(forLength: Int(itemLength), element: pixelSequence, message: message) as! PixelSequence
            }
            if itemLength < -1 {
                let message = "Fatal, cannot read length properly, decoded length cannot be negative (\(itemLength))"
                return readError(forLength: Int(itemLength), element: pixelSequence, message: message) as! PixelSequence
            }
            
            item.length = Int(itemLength)
            
            if itemLength > 0 {
                item.data = stream.read(length: Int(itemLength))
            }
            
            // read next again
            if stream.offset < stream.data.count {
                itemTag = stream.readDataTag(order: byteOrder)!
            }
        }
        
        return pixelSequence
    }
    
    
    
    
    
    private func write(dataElement element:DataElement, vrMethod:DicomConstants.VRMethod = .Explicit, byteOrder:DicomConstants.ByteOrder = .LittleEndian) -> Data {
        var data = Data()
        var localVRMethod:DicomConstants.VRMethod = .Explicit
        var order:DicomConstants.ByteOrder = .LittleEndian
        
        // set local byte order to enforce Little Endian for Prefix Header elements
        if byteOrder == .BigEndian && element.endOffset > fileMetaInformationGroupLength+144 {
            order = .BigEndian
        }
        
        if prefixHeader {
            // set local VR Method to enforce Explicit for Prefix Header elements
            if vrMethod == .Implicit && element.endOffset > fileMetaInformationGroupLength+144 {
                localVRMethod = .Implicit
            }
        } else {
            // force implicit if no header (always implicit, truncated DICOM file, ACR-NEMA, etc)
            localVRMethod = .Implicit
        }
        
        // write tag code
        data.append(element.toData(vrMethod: localVRMethod, byteOrder: order))
        
        return data
    }
}
