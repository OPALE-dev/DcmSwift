//
//  PixelData.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 30/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Foundation



class PixelSequence: DataSequence {
    enum PixelEncoding {
        case Native
        case Encapsulated
    }
    
    
    public override func toData(vrMethod inVrMethod:DicomSpec.VRMethod = .Explicit, byteOrder inByteOrder:DicomSpec.ByteOrder = .LittleEndian) -> Data {
            
        var data = Data()
        
        // write SQ tag
        var tag = DataTag(withGroup: "7fe0", element: "0010")
        data.append(tag.data)
        
        // write SQ VR
        let vrString = "\(self.vr)"
        data.append(vrString.data(using: .utf8)!)
        data.append(Data(repeating: 0x00, count: 2))
        
        // length ?
        data.append(Data(repeating: 0xff, count: 4))
        
        // write items
        for item in self.items {
            // write item tag
            data.append(item.tag.data)
            
            // write item length
            var intLength = UInt32(item.length)
            let lengthData = Data(bytes: &intLength, count: 4)
            data.append(lengthData)
            
            // write item value
            if intLength > 0 {
                //print(item.data)
                data.append(item.data)
            }
        }
        
        // write pixel Sequence Delimiter Item
        tag = DataTag(withGroup: "fffe", element: "e0dd")
        data.append(tag.data)
        data.append(Data(repeating: 0x00, count: 4))
        
        return data
    }
}
