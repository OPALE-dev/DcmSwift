//
//  DataSequence.swift
//  DICOM Test
//
//  Created by Rafael Warnault on 18/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
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
}
