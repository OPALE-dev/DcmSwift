//
//  DicomService.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 19/03/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation

public class DicomService: NSObject {
    public var localAET:String = "DCMSWIFT"
    
    
    public init(localAET:String) {
        self.localAET = localAET
    }
}
