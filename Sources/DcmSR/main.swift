//
//  File.swift
//
//
//  Created by Rafael Warnault, OPALE on 25/06/2021.
//

import Foundation
import DcmSwift
import ArgumentParser

/**
 DcmSR is a tool to extract DICOM SR data
 
 Usage:
 
     OVERVIEW: A tool to extract DICOM SR data

     USAGE: dcm-sr <subcommand>

     OPTIONS:
       -h, --help              Show help information.

     SUBCOMMANDS:
       dump (default)          Print the DICOM SR Tree
       html                    Convert DICOM SR to HTML

       See 'dcm-sr help <subcommand>' for detailed help.
 
 */
struct DcmSR: ParsableCommand {
    static var configuration = CommandConfiguration(
            abstract: "A tool to extract DICOM SR data",
            subcommands: [Dump.self, Html.self],
            defaultSubcommand: Dump.self)
    
    struct Options: ParsableArguments {
        @Argument(help: "Path of DICOM SR input file ")
        var dicomPath: String
    }
}

extension DcmSR {
    struct Dump: ParsableCommand {
        static var configuration
            = CommandConfiguration(abstract: "Print the DICOM SR Tree")

        @OptionGroup var options: DcmSR.Options

        mutating func run() throws {
            if let dicomFile = DicomFile(forPath: options.dicomPath) {
                if let doc = dicomFile.structuredReportDocument {
                    print(doc)
                }
            }
        }
    }

    struct Html: ParsableCommand {
        static var configuration
            = CommandConfiguration(abstract: "Convert DICOM SR to HTML")

        @OptionGroup var options: DcmSR.Options
        
        @Argument(help: "Path of HTML output file ")
        var htmlPath: String

        mutating func run() throws {
            if let dicomFile = DicomFile(forPath: options.dicomPath) {
                if let doc = dicomFile.structuredReportDocument {
                    let html = doc.html
                    
                    print(html)
                    
                    try? html.write(to: URL(fileURLWithPath: htmlPath), atomically: true, encoding: .utf8)
                }
            }
        }
    }
}

DcmSR.main()
