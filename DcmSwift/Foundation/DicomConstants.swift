
//
//  Dcm.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 21/03/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation
import SwiftyBeaver

/**
 * This struct declares a few constants related to the DICOM protocol
 */
public struct DicomConstants {
    /**
     The standard bytes offset used at start of DICOM files (not all).
     The `DICM` magic word used to identify the file type starts at offset 132.
     */
    public static let dicomBytesOffset              = 132
    
    /**
     The DICOM magic word.
     */
    public static let dicomMagicWord                = "DICM"
    
    /**
     Standard DICOM Application Context Name.
     */
    public static let applicationContextName        = "1.2.840.10008.3.1.1.1"
    
    /**
     Verification SOP Class
     */
    public static let verificationSOP               = "1.2.840.10008.1.1"
    public static let ultrasoundImageStorageSOP     = "1.2.840.10008.5.1.4.1.1.6.1"
    
    
    /**
     Transfer Syntax : Implicit Value Representation, Little Endian
     */
    public static let implicitVRLittleEndian        = "1.2.840.10008.1.2"
    /**
     Transfer Syntax : Explicit Value Representation, Little Endian
     */
    public static let explicitVRLittleEndian        = "1.2.840.10008.1.2.1"
    /**
     Transfer Syntax : Explicit Value Representation, Big Endian
     */
    public static let explicitVRBigEndian           = "1.2.840.10008.1.2.2"
    
    /**
     Meta-data group identifier
     */
    public static let metaInformationGroup          = "0002"
    /**
     Group Length identifier (0000)
     */
    public static let lengthGroup                   = "0000"
    
    /**
     List of supported Transfer Syntaxes
     */
    public static let transfersSyntaxes:[String] = [
        DicomConstants.implicitVRLittleEndian,
        DicomConstants.explicitVRLittleEndian,
        DicomConstants.explicitVRBigEndian
    ]
}


public func initLogger() {
    let console = ConsoleDestination()
    console.format = "$DHH:mm:ss$d $N:$l\t$L $M"
//    console.levelString.verbose     = "💜"
//    console.levelString.debug       = "🧡"
//    console.levelString.info        = "💙"
//    console.levelString.warning     = "💛"
//    console.levelString.error       = "❤️"
    
    if SwiftyBeaver.destinations.count == 0 {
        SwiftyBeaver.addDestination(console)
    }
}
