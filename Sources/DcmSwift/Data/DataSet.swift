//
//  Dataset.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 17/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation

public class DataSet: DicomObject {
    public var transferSyntax:TransferSyntax!
    public var fileMetaInformationGroupLength       = 0
    public var vrMethod:VRMethod                    = .Explicit
    public var byteOrder:ByteOrder                  = .LittleEndian
    public var forceExplicit:Bool                   = false
    public var hasPreamble:Bool                     = false
    public var isCorrupted:Bool                     = false
    
    public var metaInformationHeaderElements:[DataElement]  = []
    public var datasetElements:[DataElement]                = []
    public var allElements:[DataElement]                    = []
    
    public var internalValidations:[ValidationResult]       = []
    
    
    public override init() {
        transferSyntax = TransferSyntax(TransferSyntax.explicitVRLittleEndian)
    }
            
    
    public override var description: String {
        var string = ""
        
        sortElements()
        
        
        if metaInformationHeaderElements.count > 0 {
            string += "# Dicom-Meta-Information-Header\n"
            string += "# Used TransferSyntax: \(VRMethod.Explicit)\n"
        }
        
        for e in metaInformationHeaderElements {
            string += e.description + "\n"
        }
        
        string += "\n"
        string += "# Dicom-Dataset\n"
        string += "# Used TransferSyntax: \(self.transferSyntax?.tsName ?? "Unknow")\n"
        for e in datasetElements {
            string += e.description + "\n"
        }
        
        return string
    }
    
    
    
    // MARK: - Public methods
    public override func toData(vrMethod inVrMethod:VRMethod? = .Explicit, byteOrder inByteOrder:ByteOrder? = .LittleEndian) -> Data {
        var newData     = Data()
        
        // be sure element are sorted properly before write
        sortElements()

        // append meta header elements as binary data
        for element in allElements {
            var finalVR     = element.vrMethod
            var finalOrder  = element.byteOrder

            if inVrMethod != nil && finalVR != inVrMethod {
                finalVR = inVrMethod!
            }
            if inByteOrder != nil && finalOrder != inByteOrder {
                finalOrder = inByteOrder!
            }
            
            if hasPreamble {
                if element.group == "0002" {
                    finalVR = .Explicit
                    finalOrder = .LittleEndian
                }
            }
            
            newData.append(write(dataElement: element, vrMethod:finalVR, byteOrder:finalOrder))
        }

        return newData
    }
    
    
    public func DIMSEData(vrMethod inVrMethod:VRMethod = .Explicit, byteOrder inByteOrder:ByteOrder = .LittleEndian) -> Data {
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
                if let date = el.value as? Date {
                    return date
                } else if let str = el.value as? String {
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
    
    
    public func remove(elementForTagName name:String) -> DataElement? {
        guard let el = self.element(forTagName: name) else {
            return nil
        }
        
        return remove(dataElement: el)
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
    

    
    public func add(element:DataElement) {
        if element.group != DicomConstants.metaInformationGroup {
            datasetElements.append(element)
        }
        else {
            metaInformationHeaderElements.append(element)
        }
        
        allElements.append(element)
    }
    
    
    public func write(
        atPath path:String,
        vrMethod inVrMethod:VRMethod? = nil,
        byteOrder inByteOrder:ByteOrder? = nil
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
    
    
    
    
    public func sortElements() {
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
    private func write(dataElement element:DataElement, vrMethod:VRMethod = .Explicit, byteOrder:ByteOrder = .LittleEndian) -> Data {
        var data = Data()
        
        // write tag code
        data.append(element.toData(vrMethod: vrMethod, byteOrder: byteOrder))
        
        return data
    }
}
