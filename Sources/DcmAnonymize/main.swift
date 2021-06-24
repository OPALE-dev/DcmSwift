//
//  File.swift
//  
//
//  Created by Rafael Warnault on 23/06/2021.
//

import Foundation
import DcmSwift
import ArgumentParser

struct DcmAnonymize: ParsableCommand {
    @Argument(help: "Path of DICOM file to anonymize")
    var sourcePath: String
    
    @Argument(help: "Path to save the anonymized DICOM file")
    var destPath: String

    mutating func run() throws {
        guard let anonymizer = Anonymizer(path: sourcePath) else {
            Logger.error("Cannot create anonymizer for file: \(sourcePath)")

            DcmAnonymize.exit(withError: nil)
        }

        if !anonymizer.anonymize(to: destPath) {
            Logger.error("Cannot write anonymized file \(destPath)")

            DcmAnonymize.exit(withError: nil)
        }
        
        Logger.info("Anonymization succeeded")
    }
}

DcmAnonymize.main()

