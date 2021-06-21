//
//  Dataset.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 17/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation

public class DataSet: DicomObject {
    public var fileMetaInformationGroupLength       = 0
    public var transferSyntax:String                = DicomConstants.implicitVRLittleEndian
    public var vrMethod:DicomConstants.VRMethod     = .Explicit
    public var byteOrder:DicomConstants.ByteOrder   = .LittleEndian
    public var forceExplicit:Bool                   = false
    public var hasPreamble:Bool                     = true
    internal var isCorrupted:Bool                   = false
    
    public var metaInformationHeaderElements:[DataElement]  = []
    public var datasetElements:[DataElement]                = []
    public var allElements:[DataElement]                    = []
    
    public var internalValidations:[ValidationResult]       = []
    
    private var data:Data!
    private var stream:DicomInputStream!
    
    public override init() {
        hasPreamble = false
    }
    
    
    public init?(withData data:Data, hasPreamble:Bool = true) {
        self.data           = data
        self.hasPreamble    = hasPreamble
    }
    
    
    
    override public var description: String {
        var string = ""
        
        sortElements()
        
        string += "# Dicom-Meta-Information-Header\n"
        string += "# Used TransferSyntax: \(DicomConstants.VRMethod.Explicit)\n"
        for e in metaInformationHeaderElements {
            string += e.description + "\n"
        }
        string += "\n"
        string += "# Dicom-Meta-Information-Header\n"
        string += "# Used TransferSyntax: \(self.transferSyntax)\n"
        for e in datasetElements {
            string += e.description + "\n"
        }
        
        return string
    }
    
    
    
    // MARK: - Public methods
    public func loadData(_ withData:Data? = nil, _ withPreamble:Bool = true) -> Bool {
        var offset = 0
        
        if hasPreamble {
            offset = DicomConstants.dicomBytesOffset
        } else {
            vrMethod  = .Implicit
        }
                
        if withData != nil {
            data = withData
        }
        
        stream = DicomInputStream(dataset: self, data: data)
        stream.forward(by: offset)
        
        // reset elements arrays
        metaInformationHeaderElements  = []
        datasetElements                = []
        allElements                    = []
        
        while(stream.hasBytesAvailable && !isCorrupted) {
            if let newElement = stream.readDataElement(dataset: self, parent: nil, vrMethod: vrMethod, order: byteOrder) {
                if newElement.name == "FileMetaInformationGroupLength" {
                    fileMetaInformationGroupLength = Int(newElement.value as! Int32)
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
        
        if hasPreamble {
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
                }
                else {
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
    
    
    
    
    
    
    
    // MARK : -
    private func write(dataElement element:DataElement, vrMethod:DicomConstants.VRMethod = .Explicit, byteOrder:DicomConstants.ByteOrder = .LittleEndian) -> Data {
        var data = Data()
        var localVRMethod:DicomConstants.VRMethod = .Explicit
        var order:DicomConstants.ByteOrder = .LittleEndian
        
        // set local byte order to enforce Little Endian for Prefix Header elements
        if byteOrder == .BigEndian && element.endOffset > fileMetaInformationGroupLength+144 {
            order = .BigEndian
        }
        
        if hasPreamble {
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
