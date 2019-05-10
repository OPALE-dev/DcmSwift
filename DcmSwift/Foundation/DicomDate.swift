//
//  DicomDate.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 26/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation



/**
 This extention implements helpers to manage DICOM date and time
 related values. It mainly provides implementation for the three following
 DICOM Value Representation:
 
 - DA: Date
 - TM: Time
 - DT: DateTime
 
 The implementation manages both DICOM 3.0 and ACR-NEMA 2.0 formats and
 helpers to combine DA and TM VRs in a single Swift Date object.
 
 http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_6.2.html
 
 */
extension Date {
    /**
     Format DICOM Date
     
     - parameter dicomDate: DICOM date string (DA)
     - returns: Date object or nil if formatting fails
     
     */
    public init?(dicomDate:String) {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"// DICOM 3.0 format

        // 8 or 10 bytes fixed
        if dicomDate.count != 8 && dicomDate.count != 10 {
            print("Wrong length of string")
            return nil
        }

        // ACR-NEMA 2.0 format
        if dicomDate.count == 10 {// 10 bytes fixed (2 periods)
            df.dateFormat = "yyyy.MM.dd"
        }

        if let date = df.date(from: dicomDate) {
            self.init(timeInterval:0, since:date)
        }
        else {
            return nil
        }
    }
    
    
    /**
     Format DICOM Time
     Must be between 2 and 12 characters
     
     - parameter dicomTime: DICOM time string (TM)
     - returns: Date object or nil if formatting fails
     
     */
    public init?(dicomTime:String) {
        let df      = DateFormatter()
        var format  = "HHmmss.SSSSS"// DICOM 3.0 format

        // ACR-NEMA 2.0 format
        if dicomTime.contains(":") {
            format = "HH:mm:ss.SSSSS"
        }
        else if dicomTime.count % 2 == 1 {
            print("Length of DICOM Time cannot be odd")
            return nil
        }

        // The date string will truncate the format string
        // thanks to the length of the string
        let remainingFormat = String(format.prefix(dicomTime.count))

        df.dateFormat = String(remainingFormat)
        df.locale = .current
        if let dt = df.date(from: dicomTime) {
            self.init(timeInterval:0, since:dt)
        }
        else {
            return nil
        }
    }
    
    
    
    /**
     Combine DICOM Date & Time
     
     - parameter dicomDate: DICOM date string (DA)
     - parameter dicomTime: DICOM time string (TM)
     - returns: Date object or nil if formatting fails
     
     */
    public init?(dicomDate:String, dicomTime:String) {
        var dateTime:Date? = nil
        
        if let date = Date(dicomDate: dicomDate) {
            print(date)
            if let time = Date(dicomTime: dicomTime) {
                print(time)
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
    

    /**
     Format DICOM DateTime
     Must be between 4 and 25 characters
     
     - parameter dicomDateTime: DICOM datetime string (DT)
     - returns: Date object or nil if formatting fails
     
     */
    public init?(dicomDateTime:String) {
        var dateTime:Date? = nil

        if dicomDateTime.count >= 20 {
            if dicomDateTime.count == 20 {
                let ds = String(dicomDateTime.prefix(6))
                let ts = String(dicomDateTime.suffix(12))
                
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
        }
        
        return nil
    }
    

    /**
     Format Date to DICOM Date as string (DA)
     
     - returns: String object representing the Date as a DICOM date string
     
     */
    public func dicomDateString() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        return df.string(from: self)
    }
    
    
    /**
     Format Date to DICOM Time as string (TM)
     
     - returns: String object representing the Date as a DICOM time string
     
     */
    public func dicomTimeString() -> String {
        let df = DateFormatter()
        df.dateFormat = "HHmmss.SSSSS"
        return df.string(from: self)
    }
    


    /**
     Format Date to DICOM DateTime as string (DT)

     - returns: String object representing the Date as a DICOM datetime string

     */
    public func dicomDateTimeString() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMddHHmmss.SSSSS"
        return df.string(from: self)
    }




    
    /**
     Combines two Date objects, one for date, the other for the time
     
     - returns: Date object or nil if formatting fails
     
     */
    private static func combineDateWithTime(date: Date, time: Date) -> Date? {
        let calendar = NSCalendar.current
        
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        
        var mergedComponments       = DateComponents()
        mergedComponments.year      = dateComponents.year!
        mergedComponments.month     = dateComponents.month!
        mergedComponments.day       = dateComponents.day!
        mergedComponments.hour      = timeComponents.hour!
        mergedComponments.minute    = timeComponents.minute!
        mergedComponments.second    = timeComponents.second!
        
        return calendar.date(from: mergedComponments)
    }
}



/**
 This class represents Date Ranges used by the DICOM standard (mostly for C-FIND query)
 
 DICOM standard definition:
 
 ftp://dicom.nema.org/MEDICAL/dicom/2015b/output/chtml/part04/sect_C.2.2.2.5.html
 
 */
public class DateRange : CustomStringConvertible {
    /**
     This enumeration identify DICOM Date Range sub-operation
     on date and time VR.
     
     - priorDate: A string of the form "- <date1>" shall match all occurrences of dates prior to and including <date1>
     - afterDate: A string of the form "<date1> -" shall match all occurrences of <date1> and subsequent dates
     - betweenDate: A string of the form "<date1> - <date2>", where <date1> is less or equal to <date2>, shall match all occurrences of dates that fall between <date1> and <date2> inclusive
     
     - priorTime: A string of the form "- <time1>" shall match all occurrences of times prior to and including <time1>
     - aftrerTime: A string of the form "<time1> -" shall match all occurrences of <time1> and subsequent times
     - betweenTime: A string of the form "<time1> - <time2>", where <time1> is less or equal to <time2>, shall match all occurrences of times that fall between <time1> and <time2> inclusive
     
     - priorDateTime: A string of the form "- <datetime1>" shall match all moments in time prior to and including <datetime1>
     - aftrerDateTime: A string of the form "<datetime1> -" shall match all moments in time subsequent to and including <datetime1>
     - betweenDateTime: A string of the form "<datetime1> - <datetime2>", where <datetime1> is less or equal to <datetime2>, shall match all moments in time that fall between <datetime1> and <datetime2> inclusive
     
     */
    public enum DateRangeType {
        case priorDate
        case afterDate
        case betweenDate
        
        case priorTime
        case afterTime
        case betweenTime
        
        // TODO: implement DateTime
        case priorDateTime
        case afterDateTime
        case betweenDateTime
    }

    public enum DateRange {
        case prior
        case after
        case between
    }

    public enum TimeRange {
        case prior
        case after
        case between
    }

    public enum DateTimeRange {
        case prior
        case after
        case between
    }
    
    
    public var startDate:Date?
    public var endDate:Date?

    public var startTime:Date?
    public var endTime:Date?

    public var startDateTime:Date?
    public var endDateTime:Date?
    
    public var rangeType:DateRangeType = .betweenDate

    public var rangeDate:DateRange = .between
    public var rangeTime:TimeRange = .between
    public var rangeDateTime:DateTimeRange = .between
    
    /**
     Create a DICOM Date Range
     
     - parameter startDate: Date object, required for both .after and .between
     - parameter endDate: Date object, required for both .prior and .between
     - parameter rangeDate: DateRange
     - returns: DateRange object
     
     */
    public init(startDate:Date?, endDate:Date?, rangeDate:DateRange) {
        self.startDate  = startDate
        self.endDate    = endDate
        self.rangeDate  = rangeDate
    }
    
    /**
     Create a DICOM Time Range
     
     - parameter startTime: Date object, required for both .after and .between
     - parameter endTime: Date object, required for both .prior and .between
     - parameter rangeType: TimeRange
     - returns: DateRange object
     
     */
    public init(startTime:Date?, endTime:Date?, rangeTime:TimeRange) {
        self.startTime  = startTime
        self.endTime    = endTime
        self.rangeTime  = rangeTime
    }

    /**
     Create a DICOM DateTime Range

     - parameter startDateTime: Date object, required for both .after and .between
     - parameter endDateTime: Date object, required for both .prior and .between
     - parameter rangeDateTime: DateTimeRange
     - returns: DateRange object

     */
    public init(startDateTime:Date?, endDateTime:Date?, rangeDateTime:DateTimeRange) {
        self.startDateTime  = startDateTime
        self.endDateTime    = endDateTime
        self.rangeDateTime  = rangeDateTime
    }










    /**
     Create a DICOM Date Range for DICOM date strings
     
     - parameter dicomStartDate: DICOM Date string, required for both .afterDate and .betweenDate
     - parameter dicomEndDate: DICOM Date string, required for both .priorDate and .betweenDate
     - parameter rangeType: DateRangeType
     - returns: DateRange object
     
     DICOM Date string will be automatically formatted to Date objects
     
     */
    public convenience init?(dicomStartDate:String?, dicomEndDate:String?, rangeType:DateRange) {
        guard let dsd = dicomStartDate, let sd = Date(dicomDate: dsd) else {
            Swift.print("Invalid DICOM start date")
            return nil
        }

        guard let ded = dicomEndDate, let ed = Date(dicomDate: ded) else {
            Swift.print("Invalid DICOM end date")
            return nil
        }
        
        self.init(startDate: sd, endDate: ed, rangeDate:rangeType)
    }
    
    
    /**
     Create a DICOM Time Range for DICOM time strings
     
     - parameter dicomStartTime: DICOM Date string, required for both .afterTime and .betweenTime
     - parameter dicomEndTime: DICOM Date string, required for both .priorTime and .betweenTime
     - parameter rangeType: DateRangeType
     - returns: DateRange object
     
     DICOM Time string will be automatically formatted to Date objects
     
     */
    public convenience init?(dicomStartTime:String?, dicomEndTime:String?, rangeType:TimeRange) {
        guard let dst = dicomStartTime, let st = Date(dicomTime: dst) else {
            Swift.print("Invalid DICOM start time")
            return nil
        }
        
        guard let det = dicomEndTime, let et = Date(dicomTime: det) else {
            Swift.print("Invalid DICOM end date")
            return nil
        }
        
        self.init(startTime: st, endTime: et, rangeTime:rangeType)
    }


    /**
     Create a DICOM DateTime Range for DICOM datetime strings

     - parameter dicomStartTime: DICOM Date string, required for both .afterTime and .betweenTime
     - parameter dicomEndTime: DICOM Date string, required for both .priorTime and .betweenTime
     - parameter rangeType: DateRangeType
     - returns: DateRange object

     DICOM Time string will be automatically formatted to Date objects

     */
    public convenience init?(dicomStartDateTime:String?, dicomEndDateTime:String?, rangeType:DateTimeRange) {
        guard let dst = dicomStartDateTime, let st = Date(dicomDateTime: dst) else {
            Swift.print("Invalid DICOM start time")
            return nil
        }

        guard let det = dicomEndDateTime, let et = Date(dicomTime: det) else {
            Swift.print("Invalid DICOM end date")
            return nil
        }

        self.init(startDateTime: st, endDateTime: et, rangeDateTime:rangeType)
    }


    
    /**
     Create a DICOM Date Range from DICOM Date Range String
     */
    public convenience init?(dicomDateRange:String) {
        let components  = dicomDateRange.split(separator: "-")
        var rangeType   = DateRange.prior
        
        var startDate:String? = nil
        var endDate:String?   = nil
        
        // before/after range
        if components.count == 1 {
            // before range
            if dicomDateRange.first == "-" {
                rangeType = .prior
                endDate   = String(components[0])
            }
            // after range
            else if dicomDateRange.last == "-" {
                rangeType = .after
                startDate = String(components[0])
            }
        // between range
        } else if components.count == 2 {
            startDate   = String(components[0])
            endDate     = String(components[1])
            rangeType   = .between
        } else {
            Swift.print("Invalid DICOM Date Range")
            return nil
        }
        
        self.init(dicomStartDate: startDate, dicomEndDate: endDate, rangeType:rangeType)
    }
    
    
    /**
     Create a DICOM Time Range from DICOM Time Range String
     */
    public convenience init?(dicomTimeRange:String) {
        let components  = dicomTimeRange.split(separator: "-")
        var rangeType   = TimeRange.prior
        
        var startTime:String? = nil
        var endTime:String?   = nil
        
        // before/after range
        if components.count == 1 {
            // before range
            if dicomTimeRange.first == "-" {
                rangeType = .prior
                endTime   = String(components[0])
            }
                // after range
            else if dicomTimeRange.last == "-" {
                rangeType = .after
                startTime = String(components[0])
            }
            // between range
        } else if components.count == 2 {
            startTime   = String(components[0])
            endTime     = String(components[1])
            rangeType   = .between
        } else {
            Swift.print("Invalid DICOM Date Range")
            return nil
        }
        
        self.init(dicomStartTime: startTime, dicomEndTime: endTime, rangeType:rangeType)
    }
    



    /**
     Create a DICOM DateTime Range from DICOM DateTime Range String
     */
    public convenience init?(dicomDateTimeRange:String) {
        let components  = dicomDateTimeRange.split(separator: "-")
        var rangeType   = DateTimeRange.prior

        var startTime:String? = nil
        var endTime:String?   = nil

        // before/after range
        if components.count == 1 {
            // before range
            if dicomDateTimeRange.first == "-" {
                rangeType = .prior
                endTime   = String(components[0])
            }
                // after range
            else if dicomDateTimeRange.last == "-" {
                rangeType = .after
                startTime = String(components[0])
            }
            // between range
        } else if components.count == 2 {
            startTime   = String(components[0])
            endTime     = String(components[1])
            rangeType   = .between
        } else {
            Swift.print("Invalid DICOM Date Range")
            return nil
        }

        self.init(dicomStartDateTime: startTime, dicomEndDateTime: endTime, rangeType:rangeType)
    }








    
    /**
     A string description of the Date range
     */
    public var description: String {
        var string = ""
        
        switch self.rangeType {
        case .priorDate:
            string = "-\(self.endDate!.dicomDateString())"
            
        case .afterDate:
            string = "\(self.startDate!.dicomDateString())-"
            
        case .betweenDate:
            string = "\(self.startDate!.dicomDateString())-\(self.endDate!.dicomDateString())"
            
        case .priorTime:
            string = "-\(self.endTime!.dicomTimeString())"
            
        case .afterTime:
            string = "\(self.startTime!.dicomTimeString())-"
            
        case .betweenTime:
            string = "\(self.startTime!.dicomTimeString())-\(self.endTime!.dicomTimeString())"
            
        case .priorDateTime:
            string = "-\(self.endDateTime!.dicomDateTimeString())"
        case .afterDateTime:
            string = "NOT IMPLEMENTED!"
        case .betweenDateTime:
            string = "NOT IMPLEMENTED!"
        }
        
        return string
    }
}



// https://stackoverflow.com/questions/44009804/swift-3-how-to-get-date-for-tomorrow-and-yesterday-take-care-special-case-ne
extension Date {
    public static var yesterday: Date { return Date().dayBefore }
    public static var tomorrow:  Date { return Date().dayAfter }
    public var dayBefore: Date {
        return Calendar.current.date(byAdding: .day, value: -1, to: noon)!
    }
    public var dayAfter: Date {
        return Calendar.current.date(byAdding: .day, value: 1, to: noon)!
    }
    public var noon: Date {
        return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: self)!
    }
    public var month: Int {
        return Calendar.current.component(.month,  from: self)
    }
    public var isLastDayOfMonth: Bool {
        return dayAfter.month != month
    }
}

//enum WrongLength: Error {
//    case runtimeError(String)
//}
