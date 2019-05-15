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
        var format  = "HHmmss.SSSSSS"// DICOM 3.0 format

        // ACR-NEMA 2.0 format
        if dicomTime.contains(":") {
            format = "HH:mm:ss.SSSSSS"
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
        df.dateFormat = "HHmmss.SSSSSS"
        return df.string(from: self)
    }
    


    /**
     Format Date to DICOM DateTime as string (DT)

     - returns: String object representing the Date as a DICOM datetime string

     */
    public func dicomDateTimeString() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMddHHmmss.SSSSSS"
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
     
     - prior: A string of the form "- <date1>" shall match all occurrences of dates prior to and including <date1>
     - after: A string of the form "<date1> -" shall match all occurrences of <date1> and subsequent dates
     - between: A string of the form "<date1> - <date2>", where <date1> is less or equal to <date2>, shall match all occurrences of dates that fall between <date1> and <date2> inclusive

     */

    public enum Range {
        case prior
        case after
        case between
    }

    public var start:Date?
    public var end:Date?
    public var range:Range = .between
    public var type:DicomConstants.VR = .DA


    /**
     Create a DICOM Range for any type of Date (DA, TM, DT)

     - parameter start: Date object, required for both .after and .between
     - parameter end: Date object, required for both .prior and .between
     - parameter range: Range
     - parameter type: type of date
     - returns: DateRange object

     */
    public init(start:Date?, end:Date?, range:Range, type:DicomConstants.VR) {
        self.start  = start
        self.end    = end
        self.range  = range
        self.type   = type
    }

    /**
     Create a DICOM Date Range for DICOM date strings
     
     - parameter dicomStartDate: DICOM Date string, required for both .afterDate and .betweenDate
     - parameter dicomEndDate: DICOM Date string, required for both .priorDate and .betweenDate
     - parameter rangeType: DateRangeType: priorDate, afterDate, betweenDate
     - returns: DateRange object
     
     DICOM Date string will be automatically formatted to Date objects

     */
    public convenience init?(dicomStart:String?, dicomEnd:String?, range:Range, type:DicomConstants.VR) {
        guard let dsd = dicomStart, let sd = Date(dicomDate: dsd) else {
            Swift.print("Invalid DICOM start date")
            return nil
        }

        guard let ded = dicomEnd, let ed = Date(dicomDate: ded) else {
            Swift.print("Invalid DICOM end date")
            return nil
        }

        self.init(start: sd, end: ed, range: range, type: type)
    }

    /**
     Create a DICOM Date Range from DICOM Date Range String
     */
    public convenience init?(dicomRange:String, type: DicomConstants.VR) {
        let components  = dicomRange.split(separator: "-")
        var rangeType   = Range.prior

        var startDate:String? = nil
        var endDate:String?   = nil

        // before/after range
        if components.count == 1 {
            // before range
            if dicomRange.first == "-" {
                rangeType = .prior
                endDate   = String(components[0])
            }
                // after range
            else if dicomRange.last == "-" {
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

        self.init(dicomStart: startDate, dicomEnd: endDate, range: rangeType, type: type)
    }

    /**
     A string description of the Date range
     */
    public var description: String {
        var string = ""
        switch self.type {
        case .DA:
            switch self.range {

            case .prior:
                string = "-\(self.end!.dicomDateString())"

            case .after:
                string = "\(self.start!.dicomDateString())-"

            case .between:
                string = "\(self.start!.dicomDateString())-\(self.end!.dicomDateString())"
            }
        case .TM:
            switch self.range {

            case .prior:
                string = "-\(self.end!.dicomTimeString())"

            case .after:
                string = "\(self.start!.dicomTimeString())-"

            case .between:
                string = "\(self.start!.dicomTimeString())-\(self.end!.dicomTimeString())"
            }
        case .DT:
            switch self.range {

            case .prior:
                string = "-\(self.end!.dicomDateTimeString())"

            case .after:
                string = "\(self.start!.dicomDateTimeString())-"

            case .between:
                string = "\(self.start!.dicomDateTimeString())-\(self.end!.dicomDateTimeString())"
            }
        default:
            string = ""
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
