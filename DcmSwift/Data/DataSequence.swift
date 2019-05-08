//
//  DataSequence.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 18/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation



public class DataSequence: DataElement {
    public var items:[DataItem] = []
    
    override public var description: String {
        var string = super.description + "\n"
        
        for item in self.items {
            string += "  > " + item.description + "\n"
            for se in item.elements {
                string += "    > " + se.description + "\n"
            }
        }
        
        return string
    }
    
    
    
    
    override public func toJSONArray() -> Any {
        var itemsArray:[Any] = []
        
        for item in self.items {
            itemsArray.append(item.toJSONArray())
        }
        
        let json:[String:Any] = [
            "\(self.tagCode().uppercased())":
                [
                    "vr": "\(self.vr)",
                    "value": itemsArray
            ]
        ]
        
        return json
    }

    
    public override func toData(vrMethod inVrMethod:DicomConstants.VRMethod = .Explicit, byteOrder inByteOrder:DicomConstants.ByteOrder = .LittleEndian) -> Data {
        var data = Data()
        
        for item in self.items {
            // write item tag
            data.append(item.tag.data)
            
            // write item length
            if inVrMethod == .Explicit && item.length != -1 {
                var intLength = UInt32(item.length)
                let lengthData = Data(bytes: &intLength, count: 4)
                data.append(lengthData)
            }
            
            // write item sub-elements
            for element in item.elements {
                data.append(element.toData(vrMethod: inVrMethod, byteOrder: inByteOrder))
            }
            
            // write item delimiter
            if inVrMethod == .Implicit {
                let tag = DataTag(withGroup: "fffe", element: "e00d")
                data.append(tag.data)
                data.append(Data(repeating: 0x00, count: 4))
            }
        }
        
        // write sequence delimiter
        if inVrMethod == .Implicit {
            let tag = DataTag(withGroup: "fffe", element: "e0dd")
            data.append(tag.data)
            data.append(Data(repeating: 0x00, count: 4))
        }
        
        return data
    }
}
