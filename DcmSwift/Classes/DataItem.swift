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
    
//    override init() {
//        super.init()        
//    }
}
