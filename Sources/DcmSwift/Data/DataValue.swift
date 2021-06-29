//
//  DataValue.swift
//  
//
//  Created by Rafael Warnault, OPALE on 28/06/2021.
//

import Foundation

/**
 A class mostly used to handle multiple-values Data Element (array of value separated by `\`)
 */
public class DataValue {
    public var value:String    = ""
    public var index:Int       = 0
    
    init(_ val:String, atIndex index:Int = 0) {
        self.value = val
        self.index = index
    }
}
