//
//  DicomOutputSTream.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 23/06/2021.
//  Copyright © 2021 Read-Write.fr. All rights reserved.
//

import Foundation

public class DicomOutputStream {
    var outputStream:OutputStream!
    
    public init(filePath:String) {
        outputStream = OutputStream(toFileAtPath: filePath, append: false)
    }
    
    public init(url:URL) {
        outputStream = OutputStream(url: url, append: false)
    }
    
    public func writeDataset(_ dataset:DataSet, transferSyntax:String) -> Bool {
        
        return false
    }
}
