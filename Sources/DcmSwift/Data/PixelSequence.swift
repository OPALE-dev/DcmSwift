//
//  PixelData.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 30/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation



class PixelSequence: DataSequence {
    enum PixelEncoding {
        case Native
        case Encapsulated
    }
    
    
    public override func toData(vrMethod inVrMethod:VRMethod = .Explicit, byteOrder inByteOrder:ByteOrder = .LittleEndian) -> Data {
        var data = Data()
        
        // item data first because we need to know the length
        var itemsData = Data()
        // write items
        for item in self.items {
            // write item tag
            itemsData.append(item.tag.data)
            
            // write item length
            var intLength = UInt32(item.length)
            let lengthData = Data(bytes: &intLength, count: 4)
            itemsData.append(lengthData)
            
            // write item value
            if intLength > 0 {
                //print(item.data)
                itemsData.append(item.data)
            }
//            
//            // write pixel Sequence Delimiter Item
//            let dtag = DataTag(withGroup: "fffe", element: "e00d")
//            itemsData.append(dtag.data)
//            itemsData.append(Data(repeating: 0x00, count: 4))
        }
        
        
        // write tag code
        //print("self.tag : (\(self.tag.group),\(self.tag.element))")
        //data.append(self.tag.data(withByteOrder: inByteOrder))
        data.append(contentsOf: [0xE0, 0x7f, 0x10, 0x00])
        
        // write VR (only explicit)
        if inVrMethod == .Explicit  {
            let vrString = "\(self.vr)"
            let vrData = vrString.data(using: .ascii)
            data.append(vrData!)
            
            data.append(contentsOf: [0x00, 0x00, 0xff, 0xff, 0xff, 0xff])
            
//            if self.vr == .SQ {
//                data.append(Data(repeating: 0x00, count: 2))
//            }
//            else if self.vr == .OB ||
//                self.vr == .OW ||
//                self.vr == .OF ||
//                self.vr == .SQ ||
//                self.vr == .UT ||
//                self.vr == .UN {
//                data.append(Data(repeating: 0x00, count: 2))
//            }
        }
        
        
        
        
        // write length (no length for pixel sequence, only 0xffffffff ?
//        // http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_A.4.html)
//        let itemsLength = UInt32(itemsData.count + 4)
//        var convertedNumber = inByteOrder == .LittleEndian ?
//            itemsLength.littleEndian : itemsLength.bigEndian
//
//        let lengthData = Data(bytes: &convertedNumber, count: 4)
//        data.append(lengthData)
        //data.append(Data(repeating: 0xff, count: 4))
        
        
        // append items
        data.append(itemsData)
        
        
        // write pixel Sequence Delimiter Item
        tag = DataTag(withGroup: "fffe", element: "e0dd")
        data.append(tag.data)
        data.append(Data(repeating: 0x00, count: 4))
        
        return data
    }
}
