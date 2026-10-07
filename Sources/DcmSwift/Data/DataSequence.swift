//
//  DataSequence.swift
//  DICOM Test
//
//  Created by Rafael Warnault, OPALE on 18/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation


/**
 `DataSequence` is a specific type of `DataElement` with the ability of nesting n `DataItem` objects.
 Each `DataItem` object can have n `DataElement` objects.
 
 http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_7.5.html
 */
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
    

    
    public override func toData(vrMethod inVrMethod:VRMethod = .Explicit, byteOrder inByteOrder:ByteOrder = .LittleEndian) -> Data {
        var data = Data()
        
        // write tag code
        //print("self.tag : (\(self.tag.group),\(self.tag.element))")
        data.append(self.tag.data(withByteOrder: inByteOrder))
                
        // write VR (only explicit)
        if inVrMethod == .Explicit  {
            let vrString = "\(self.vr)"
            let vrData = vrString.data(using: .ascii)
            data.append(vrData!)
                        
            if self.vr == .SQ {
                data.append(byte: 0x00, count: 2)
            }
            else if self.vr == .OB ||
                self.vr == .OW ||
                self.vr == .OF ||
                self.vr == .OL ||
                self.vr == .OV ||
                self.vr == .SQ ||
                self.vr == .SV ||
                self.vr == .UC ||
                self.vr == .UT ||
                self.vr == .UN ||
                self.vr == .UR ||
                self.vr == .UV {
                data.append(byte: 0x00, count: 2)
            }
        }
        
        
        // Items are serialized first: defined lengths must describe the
        // target encoding, which may differ from the one the sequence was
        // read from (e.g. Implicit to Explicit VR changes header sizes).
        let itemsData = encodedItems(vrMethod: inVrMethod, byteOrder: inByteOrder)

        // write length
        if self.vr == .SQ {
            if self.length == -1 {
                data.append(byte: 0xff, count: 4)
            } else {
                data.append(uint32: UInt32(itemsData.count), bigEndian: inByteOrder == .BigEndian)
            }
        }
        else if self.vr == .OB ||
            self.vr == .OW ||
            self.vr == .OF ||
            self.vr == .OL ||
            self.vr == .OV ||
            self.vr == .SV ||
            self.vr == .UC ||
            self.vr == .UT ||
            self.vr == .UN ||
            self.vr == .UR ||
            self.vr == .UV {
            if self.length >= 0 {
                let intLength = UInt32(self.length)
                var convertedNumber = inByteOrder == .LittleEndian ?
                    intLength.littleEndian : intLength.bigEndian
                
                let lengthData = Data(bytes: &convertedNumber, count: 4)
                data.append(lengthData)
            }
                // negative length indicate sequence here
            else if self.length == -1 {
                // if OB/OW is a Pixel Sequence
                if let _ = self as? PixelSequence {
                    data.append(byte: 0xff, count: 4)
                }
            }
        }
        else {
            if inVrMethod == .Explicit {
                // we only take care of endianneess with Explicit
                let intLength = UInt16(self.length)
                var convertedNumber = inByteOrder == .LittleEndian ?
                    intLength.littleEndian : intLength.bigEndian
                
                withUnsafePointer(to: &convertedNumber) {
                    data.append(UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self), count: 2)
                }
            }
            else if inVrMethod == .Implicit {
                data.append(uint32: UInt32(bitPattern: Int32(self.length)), bigEndian: inByteOrder == .BigEndian)
            }
        }
        
        data.append(itemsData)

        // write sequence delimiter
        if length == -1 {
            let tag = DataTag(withGroup: "fffe", element: "e0dd", byteOrder: inByteOrder)
            data.append(tag.data(withByteOrder: inByteOrder))
            data.append(byte: 0x00, count: 4)
        }
        
        return data
    }

    /// The encoded Items, each with its length measured in the target
    /// encoding, or undefined with an Item Delimitation Item.
    private func encodedItems(vrMethod: VRMethod, byteOrder: ByteOrder) -> Data {
        var data = Data()
        for item in items {
            var content = Data()
            for element in item.elements {
                content.append(element.toData(vrMethod: vrMethod, byteOrder: byteOrder))
            }
            data.append(item.tag.data(withByteOrder: byteOrder))
            if item.length == -1 {
                data.append(byte: 0xff, count: 4)
                data.append(content)
                let tag = DataTag(withGroup: "fffe", element: "e00d", byteOrder: byteOrder)
                data.append(tag.data(withByteOrder: byteOrder))
                data.append(byte: 0x00, count: 4)
            } else {
                data.append(uint32: UInt32(content.count), bigEndian: byteOrder == .BigEndian)
                data.append(content)
            }
        }
        return data
    }
}
