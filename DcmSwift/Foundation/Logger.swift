//
//  Logger.swift
//  DcmSwift
//
//  Created by paul on 15/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation

/**
 This class is for printing log, either in the console or in a file.
 Log can have different type of severity, and different type of output as
 stated before.

 */
public class Logger {


    /**
     Enumeration for severity level
     */
    public enum LogLevel : Int {
        case FATAL   = 0
        case ERROR   = 1
        case WARNING = 2
        case INFO    = 3
        case NOTICE  = 4
        case DEBUG   = 5
        case VERBOSE = 6

        var description: String {
            switch self {
            case .FATAL:
                return "FATAL"
            case .NOTICE:
                return "NOTICE"
            case .INFO:
                return "INFO"
            case .VERBOSE:
                return "VERBOSE"
            case .DEBUG:
                return "DEBUG"
            case .WARNING:
                return "WARNING"
            case .ERROR:
                return "ERROR"
            }
        }
    }

    /**
     Enumeration for type of output
     - Stdout: console
     - File: file
    */
    public enum Output {
        case Stdout
        case File
    }


    public var fileName:String  = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    public var outputs:[Output] = [.Stdout]
    private static var shared   = Logger()
    private var maxLevel: Int = 5



    public static func notice(_ string:String, _ tag:String? = nil, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        if LogLevel.NOTICE.rawValue <= shared.maxLevel {
            shared.output(string: string, tag, file, function, line: line, severity: LogLevel.NOTICE)
        }
    }

    public static func info(_ string:String, _ tag:String? = nil, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        if LogLevel.INFO.rawValue <= shared.maxLevel {
            shared.output(string: string, tag, file, function, line: line, severity: LogLevel.INFO)
        }
    }

    public static func verbose(_ string:String, _ tag:String? = nil, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        if LogLevel.NOTICE.rawValue <= shared.maxLevel {
            shared.output(string: string, tag, file, function, line: line, severity: LogLevel.NOTICE)
        }
    }

    public static func debug(_ string:String, _ tag:String? = nil, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        if LogLevel.DEBUG.rawValue <= shared.maxLevel {
            shared.output(string: string, tag, file, function, line: line, severity: LogLevel.DEBUG)
        }
    }

    public static func warning(_ string:String, _ tag:String? = nil, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        if LogLevel.WARNING.rawValue <= shared.maxLevel {
            shared.output(string: string, tag, file, function, line: line, severity: LogLevel.WARNING)
        }
    }

    public static func error(_ string:String, _ tag:String? = nil, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        if LogLevel.ERROR.rawValue <= shared.maxLevel {
            shared.output(string: string, tag, file, function, line: line, severity: LogLevel.ERROR)
        }
    }

    public static func fatal(_ string:String, _ tag:String? = nil, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        if LogLevel.FATAL.rawValue <= shared.maxLevel {
            shared.output(string: string, tag, file, function, line: line, severity: LogLevel.FATAL)
        }
    }

    /**
     Format the output
     Adds a newline for writting in file
     - parameter string: the message to be sent
     - parameter tag: the tag to be printed; name of the target by default
     - parameter file: file where the log was called
     - parameter function: same
     - parameter line: same
     - parameter severity: level of severity of the log (see enum)

     */
    public func output(string:String, _ tag:String?, _ file: String = #file, _ function: String = #function, line: Int = #line, severity:LogLevel) {
        let date = Date()
        let df = DateFormatter()
        // formatting date
        df.dateFormat = "dd-MM-yyyy HH:mm:ss"
        // if tag is nil, tag is name of target
        let tagName:String = tag ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String

        /* DATE SEVERITY -> [TAG]        MESSAGE */
        let outputString:String = "\(df.string(from: date)) \(severity.description) -> [\(tagName)]\t \(string)"

        // managing different type of output (console or file)
        for output in outputs {
            switch output {
            case .Stdout:
                consoleLog(message: outputString)
            case .File:
                fileLog(message: outputString + "\n")
            }

        }
    }

    /**
     Prints to the console
     - parameter message: the log to be printed in the console

     */
    public func consoleLog(message:String) {
        print(message)
    }

    /**
     Write in file. Creates a file if the file doesn't exist. Append at
     the end of the file.
     - parameter message: the log to be written in the file

    */
    public func fileLog(message: String) {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = dir.appendingPathComponent(fileName)

            var isDirectory = ObjCBool(true)
            // if file doesn't exist we create it
            if !FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) {
                FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
            }

            do {
                if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
                    fileHandle.seekToEndOfFile()
                    let data:Data = message.data(using: String.Encoding.utf8, allowLossyConversion: false)!
                    fileHandle.write(data)
                } else {
                    try message.write(to: fileURL, atomically: false, encoding: .utf8)
                }
            }
            catch {/* error handling here */}
        }
    }


    /**
     Set the destination for output : file (with name of file), console.
     Default log file is dicom.log
     - parameter destinations: all the destinations where the logs are outputted

    */
    public static func setDestinations(_ destinations: [Output], filePath: String? = nil) {
        shared.outputs = destinations
        if let fileName:String = filePath {
            shared.fileName = fileName
        }
    }


    public static func setMaxLevel(_ at: LogLevel) {
        if 0 <= at.rawValue && at.rawValue <= 5 {
            shared.maxLevel = at.rawValue
        }
    }
}
