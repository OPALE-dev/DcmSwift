//
//  DataItem.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 18/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Foundation


public class DataItem: DataElement {
    public var elements:[DataElement]   = []
    
    override public var name:String {
        return "Item"
    }
    
    
    
    override public func toJSON() -> String {
        var val = super.toJSON()
        
        if self.elements.count > 0 {
            val = val + ", " + elements.map { $0.toJSON() }.joined(separator: ", ")
        }
        
        return val
    }
}
