//
//  PixelData.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 30/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation


/**
 A class used to handle multiframe Pixel Sequence
 
 http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_A.4.html
 http://dicom.nema.org/medical/Dicom/2018d/output/chtml/part03/sect_C.7.6.3.html
 */
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
            itemsData.append(item.tag.data(withByteOrder: inByteOrder))
            
            // write item length
            let intLength = UInt32(item.length)
            itemsData.append(uint32: intLength, bigEndian: inByteOrder == .BigEndian)
            
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
        data.append(self.tag.data(withByteOrder: inByteOrder))
        
        // write VR (only explicit)
        if inVrMethod == .Explicit  {
            let vrString = "\(self.vr)"
            let vrData = vrString.data(using: .ascii)
            data.append(vrData!)
            
            data.append(byte: 0x00, count: 2)
            data.append(byte: 0xff, count: 4)
            
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
        let delimiterTag = DataTag(withGroup: "fffe", element: "e0dd", byteOrder: inByteOrder)
        data.append(delimiterTag.data(withByteOrder: inByteOrder))
        data.append(byte: 0x00, count: 4)

        return data
    }
}
