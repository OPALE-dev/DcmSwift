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
    public enum LogLevel : String {
        case Notice  = "NOTICE"
        case Info    = "INFO"
        case Verbose = "VERBOSE"
        case Debug   = "DEBUG"
        case Warning = "WARNING"
        case Error   = "ERROR"
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


    public var fileName:String  = "dicom.log"
    public var outputs:[Output] = [.Stdout]
    private static var shared   = Logger()



    public static func notice(_ string:String, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        shared.output(string: string, file, function, line: line, severity: LogLevel.Notice)
    }

    public static func info(_ string:String, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        shared.output(string: string, file, function, line: line, severity: LogLevel.Info)
    }

    public static func verbose(_ string:String, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        shared.output(string: string, file, function, line: line, severity: LogLevel.Notice)
    }

    public static func debug(_ string:String, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        shared.output(string: string, file, function, line: line, severity: LogLevel.Debug)
    }

    public static func warning(_ string:String, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        shared.output(string: string, file, function, line: line, severity: LogLevel.Warning)
    }

    public static func error(_ string:String, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        shared.output(string: string, file, function, line: line, severity: LogLevel.Error)
    }


    /**
     Format the output
     Adds a newline for writting in file
     - parameter string: the message to be sent
     - parameter file: file where the log was called
     - parameter function: same
     - parameter line: same
     - parameter severity: level of severity of the log (see enum)

     */
    public func output(string:String, _ file: String = #file, _ function: String = #function, line: Int = #line, severity:LogLevel) {
        let date = Date()
        let df = DateFormatter()
        // formatting date
        df.dateFormat = "dd-MM-yyyy HH:mm:ss"
        /* DATE SEVERITY MESSAGE */
        let outputString:String = "\(df.string(from: date)) \(severity.rawValue) \t \(string)"

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
    public static func setDestinations(_ destinations: [Output], filePath: String = "dicom.log") {
        shared.outputs = destinations
        shared.fileName = filePath
    }
}
