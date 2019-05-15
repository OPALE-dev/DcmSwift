//
//  Logger.swift
//  DcmSwift
//
//  Created by paul on 15/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation

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
    */
    public enum Output {
        case Stdout
        case File
    }


    public var fileName:String = "/"
    public var outputs:[Output] = [.Stdout]
    private static var shared = Logger()



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
     */
    public func output(string:String, _ file: String = #file, _ function: String = #function, line: Int = #line, severity:LogLevel) {
        let date = Date()
        let df = DateFormatter()
        // formatting date
        df.dateFormat = "dd-MM-yyyy HH:mm:ss"
        let outputString:String = "\(df.string(from: date)) \(severity.rawValue) \t -> \(string)"

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
     Print to the console
     */
    public func consoleLog(message:String) {
        print(message)
    }

    /**
     Write in file
    */
    public func fileLog(message: String) {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = dir.appendingPathComponent(fileName)

            var isDirectory = ObjCBool(true)
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
     Set the destination for output : file (with name of file), console
    */
    public static func setDestinations(_ destinations: [Output], filePath: String = "/") {
        shared.outputs = destinations
        shared.fileName = filePath
    }
}
