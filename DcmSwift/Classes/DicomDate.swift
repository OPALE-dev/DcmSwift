//
//  DicomDate.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 26/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Foundation


import Foundation


extension Date {
    public init?(dicomDate:String) {
        let df      = DateFormatter()
        var date    = Date()
        
        if dicomDate.characters.count == 8 {
            df.dateFormat   = "yyyyMMdd"
            date            = df.date(from: dicomDate)!
        }
        else if dicomDate.characters.count == 10 {
            df.dateFormat   = "yyyy.MM.dd"
            date            = df.date(from: dicomDate)!
        }
        else {
            return nil
        }
        self.init(timeInterval:0, since:date)
    }
    
    
    public init?(dicomDate:String, dicomTime:String) {
        // HH:mm:ss
        self.init()
    }
    

    public func dicomDateString() -> String {
        return ""
    }
    
    public func dicomTimeString() -> String {
        return ""
    }
}
