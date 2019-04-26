//
//  DicomDate.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 26/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation






extension Date {
    public init?(dicomDate:String) {
        var date:Date?  = nil
        let df          = DateFormatter()
        
        if dicomDate.count == 8 {
            df.dateFormat   = "yyyyMMdd"
            if let d = df.date(from: dicomDate) {
                date = d
            }
        }
        else if dicomDate.count == 10 {
            df.dateFormat   = "yyyy.MM.dd"
            date            = df.date(from: dicomDate)!
        }
        else {
            return nil
        }
        if let dt = date {
            self.init(timeInterval:0, since:dt)
        } else {
            return nil
        }
    }
    
    
    public init?(dicomTime:String) {
        let df      = DateFormatter()
        var date    = Date()
        
        if dicomTime.contains(":") {
            if dicomTime.count == 8 {
                df.dateFormat = "HH:mm:ss"
                date = df.date(from: dicomTime)!
            } else {
                return nil
            }
        }
        else {
            if dicomTime.count == 6 {
                df.dateFormat = "HHmmss"
                df.locale = .current
                if let d = df.date(from: dicomTime) {
                    date = d
                }
            } else {
                return nil
            }
        }
    
        self.init(timeInterval:0, since:date)
    }
    
    
    public init?(dicomDate:String, dicomTime:String) {
        var dateTime:Date? = nil
        
        if let date = Date(dicomDate: dicomDate) {
            if let time = Date(dicomTime: dicomTime) {
                if let dt = Date.combineDateWithTime(date: date, time: time) {
                    dateTime = dt
                }
            }
        }
        if let dt = dateTime {
            self.init(timeInterval:0, since:dt)
        } else {
            return nil
        }
    }
    

    public init?(dicomDateTime:String) {
        var dateTime:Date? = nil
        
        
        if dicomDateTime.count >= 14 {
            if dicomDateTime.count == 14 {
                let ds = String(dicomDateTime.prefix(6))
                let ts = String(dicomDateTime.suffix(4))
                
                if let date = Date(dicomDate: ds) {
                    if let time = Date(dicomTime: ts) {
                        if let dt = Date.combineDateWithTime(date: date, time: time) {
                            dateTime = dt
                        }
                    }
                }
            }
        }
        
        if let dt = dateTime {
            self.init(timeInterval:0, since:dt)
        } else {
            return nil
        }
    }
    

    public func dicomDateString() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        return df.string(from: self)
    }
    
    public func dicomTimeString() -> String {
        let df = DateFormatter()
        df.dateFormat = "HHmmss"
        return df.string(from: self)
    }
    
    
    
    private static func combineDateWithTime(date: Date, time: Date) -> Date? {
        let calendar = NSCalendar.current
        
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        
        var mergedComponments = DateComponents()
        mergedComponments.year = dateComponents.year!
        mergedComponments.month = dateComponents.month!
        mergedComponments.day = dateComponents.day!
        mergedComponments.hour = timeComponents.hour!
        mergedComponments.minute = timeComponents.minute!
        mergedComponments.second = timeComponents.second!
        
        return calendar.date(from: mergedComponments)
    }
}



public class DateRange : CustomStringConvertible {
    public enum DateRangeType {
        case priorDate
        case aftrerDate
        case betweenDate
        case priorTime
        case aftrerTime
        case betweenTime
    }
    
    
    public var startDate:Date?
    public var endDate:Date?

    public var startTime:Date?
    public var endTime:Date?
    
    public var rangeType:DateRangeType = .betweenDate
    
    
    public init(startDate:Date?, endDate:Date?, rangeType:DateRangeType) {
        self.startDate  = startDate
        self.endDate    = endDate
        self.rangeType  = rangeType
    }
    
    
    public init(startTime:Date?, endTime:Date?, rangeType:DateRangeType) {
        self.startTime  = startTime
        self.endTime    = endTime
        self.rangeType  = rangeType
    }
    
    
    public convenience init?(dicomStartDate:String?, dicomEndDate:String?, rangeType:DateRangeType) {
        guard let dsd = dicomStartDate, let sd = Date(dicomDate: dsd) else {
            Swift.print("Invalid DICOM start date")
            return nil
        }

        guard let ded = dicomEndDate, let ed = Date(dicomDate: ded) else {
            Swift.print("Invalid DICOM end date")
            return nil
        }
        
        self.init(startDate: sd, endDate: ed, rangeType:rangeType)
    }
    
    
    public convenience init?(dicomStartTime:String?, dicomEndTime:String?, rangeType:DateRangeType) {
        guard let dst = dicomStartTime, let st = Date(dicomTime: dst) else {
            Swift.print("Invalid DICOM start time")
            return nil
        }
        
        guard let det = dicomEndTime, let et = Date(dicomTime: det) else {
            Swift.print("Invalid DICOM end date")
            return nil
        }
        
        self.init(startTime: st, endTime: et, rangeType:rangeType)
    }
    
    
    public convenience init?(dicomDateRange:String) {
        let components  = dicomDateRange.split(separator: "-")
        var rangeType   = DateRangeType.priorDate
        
        var startDate:String? = nil
        var endDate:String?   = nil
        
        // before/after range
        if components.count == 1 {
            // before range
            if dicomDateRange.first == "-" {
                rangeType = .priorDate
                endDate = String(components[0])
            }
            // after range
            else if dicomDateRange.last == "-" {
                rangeType = .aftrerDate
                startDate   = String(components[0])
            }
        // between range
        } else if components.count == 2 {
            startDate   = String(components[0])
            endDate     = String(components[1])
            rangeType   = .betweenDate
        } else {
            Swift.print("Invalid DICOM Date Range")
            return nil
        }
        
        self.init(dicomStartDate: startDate, dicomEndDate: endDate, rangeType:rangeType)
    }
    
    
    public convenience init?(dicomTimeRange:String) {
        let components  = dicomTimeRange.split(separator: "-")
        var rangeType   = DateRangeType.priorTime
        
        var startTime:String? = nil
        var endTime:String?   = nil
        
        // before/after range
        if components.count == 1 {
            // before range
            if dicomTimeRange.first == "-" {
                rangeType = .priorTime
                endTime = String(components[0])
            }
                // after range
            else if dicomTimeRange.last == "-" {
                rangeType = .aftrerTime
                startTime   = String(components[0])
            }
            // between range
        } else if components.count == 2 {
            startTime   = String(components[0])
            endTime     = String(components[1])
            rangeType   = .betweenTime
        } else {
            Swift.print("Invalid DICOM Date Range")
            return nil
        }
        
        self.init(dicomStartTime: startTime, dicomEndTime: endTime, rangeType:rangeType)
    }
    
    
    
    /**
     A string description of the Date range
     */
    public var description: String {
        var string = ""
        
        switch self.rangeType {
        case .priorDate:
            string = "-\(self.endDate!.dicomDateString())"
            
        case .aftrerDate:
            string = "\(self.startDate!.dicomDateString())-"
            
        case .betweenDate:
            string = "\(self.startDate!.dicomDateString())-\(self.endDate!.dicomDateString())"
            
        case .priorTime:
            string = "-\(self.endTime!.dicomTimeString())"
            
        case .aftrerTime:
            string = "\(self.startTime!.dicomTimeString())-"
            
        case .betweenTime:
            string = "\(self.startTime!.dicomTimeString())-\(self.endTime!.dicomTimeString())"
            
        }
        
        return string
    }
}
