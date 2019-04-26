
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
     Meta-data group identifier
     */
    public static let metaInformationGroup          = "0002"
    /**
     Group Length identifier (0000)
     */
    public static let lengthGroup                   = "0000"
    
    
    
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
    public static let implicitVRLittleEndian = "1.2.840.10008.1.2"
    /**
     Transfer Syntax : Explicit Value Representation, Little Endian
     */
    public static let explicitVRLittleEndian = "1.2.840.10008.1.2.1"
    /**
     Transfer Syntax : Explicit Value Representation, Big Endian
     */
    public static let explicitVRBigEndian = "1.2.840.10008.1.2.2"

    
    
    /**
     Transfer Syntax : JPEG Baseline (Process 1) Lossy JPEG 8-bit Image Compression
     */
    public static let JPEGLossy8bit = "1.2.840.10008.1.2.4.50"
    
    /**
     Transfer Syntax : JPEG Baseline (Processes 2 & 4) Lossy JPEG 12-bit Image Compression
     */
    public static let JPEGLossy12bit = "1.2.840.10008.1.2.4.51"
    
    /**
     Transfer Syntax : JPEG Extended (Processes 3 & 5) Retired
     */
    public static let JPEGExtended = "1.2.840.10008.1.2.4.52"
    
    /**
     Transfer Syntax : JPEG Spectral Selection, Nonhierarchical (Processes 6 & 8) Retired
     */
    public static let JPEGSpectralSelectionNonhierarchical6 = "1.2.840.10008.1.2.4.53"
    
    /**
     Transfer Syntax : JPEG Spectral Selection, Nonhierarchical (Processes 7 & 9) Retired
     */
    public static let JPEGSpectralSelectionNonhierarchical7 = "1.2.840.10008.1.2.4.54"
    
    /**
     Transfer Syntax : JPEG Full Progression, Nonhierarchical (Processes 10 & 12) Retired
     */
    public static let JPEGFullProgressionNonhierarchical10 = "1.2.840.10008.1.2.4.55"
    
    /**
     Transfer Syntax : JPEG Full Progression, Nonhierarchical (Processes 11 & 13) Retired
     */
    public static let JPEGFullProgressionNonhierarchical11 = "1.2.840.10008.1.2.4.56"
    
    /**
     Transfer Syntax : JPEG Lossless, Nonhierarchical (Processes 14)
     */
    public static let JPEGLosslessNonhierarchical = "1.2.840.10008.1.2.4.57"
    
    /**
     Transfer Syntax : JPEG Lossless, Nonhierarchical (Processes 15) Retired
     */
    public static let JPEGLossless15 = "1.2.840.10008.1.2.4.58"
    
    /**
     Transfer Syntax : JPEG Extended, Hierarchical (Processes 16 & 18) Retired
     */
    public static let JPEGExtended16 = "1.2.840.10008.1.2.4.59"
    
    /**
     Transfer Syntax : JPEG Extended, Hierarchical (Processes 17 & 19) Retired
     */
    public static let JPEGExtended17 = "1.2.840.10008.1.2.4.60"
    
    /**
     Transfer Syntax : JPEG Spectral Selection, Hierarchical (Processes 20 & 22) Retired
     */
    public static let JPEGSpectralSelectionHierarchical20 = "1.2.840.10008.1.2.4.61"
    
    /**
     Transfer Syntax : JPEG Spectral Selection, Hierarchical (Processes 21 & 23) Retired
     */
    public static let JPEGSpectralSelectionHierarchical21 = "1.2.840.10008.1.2.4.62"
    
    /**
     Transfer Syntax : JPEG Full Progression, Hierarchical (Processes 24 & 26) Retired
     */
    public static let JPEGFullProgressionHierarchical24 = "1.2.840.10008.1.2.4.63"
    
    /**
     Transfer Syntax : JPEG Full Progression, Hierarchical (Processes 25 & 27) Retired
     */
    public static let JPEGFullProgressionHierarchical25 = "1.2.840.10008.1.2.4.64"
    
    /**
     Transfer Syntax : JPEG Lossless, Nonhierarchical (Process 28) Retired
     */
    public static let JPEGLossless28 = "1.2.840.10008.1.2.4.65"
    
    /**
     Transfer Syntax : JPEG Lossless, Nonhierarchical (Process 29) Retired
     */
    public static let JPEGLossless29 = "1.2.840.10008.1.2.4.66"
    
    /**
     Transfer Syntax : JPEG Lossless, Nonhierarchical, First- Order Prediction
     */
    public static let JPEGLossless = "1.2.840.10008.1.2.4.70"
    
    /**
     Transfer Syntax : JPEG-LS Lossless Image Compression
     */
    public static let JPEGLSLossless = "1.2.840.10008.1.2.4.80"
    
    /**
     Transfer Syntax : JPEG-LS Lossy (Near- Lossless) Image Compression
     */
    public static let JPEGLSLossy = "1.2.840.10008.1.2.4.81"
    
    /**
     Transfer Syntax : JPEG 2000 Image Compression (Lossless Only)
     */
    public static let JPEG2000LosslessOnly = "1.2.840.10008.1.2.4.90"
    
    /**
     Transfer Syntax : JPEG 2000 Image Compression
     */
    public static let JPEG2000 = "1.2.840.10008.1.2.4.91"
    
    /**
     Transfer Syntax : JPEG 2000 Part 2 Multicomponent Image Compression (Lossless Only)
     */
    public static let JPEG2000Part2Lossless = "1.2.840.10008.1.2.4.92"
    
    /**
     Transfer Syntax : JPEG 2000 Part 2 Multicomponent Image Compression
     */
    public static let JPEG2000Part2 = "1.2.840.10008.1.2.4.93"
    
    
    
    /**
     List of supported Transfer Syntaxes
     */
    public static let transfersSyntaxes:[String] = [
        DicomConstants.implicitVRLittleEndian,
        DicomConstants.explicitVRLittleEndian,
        DicomConstants.explicitVRBigEndian
    ]
    
    
    /**
     List of JPEG Transfer syntax
     */
    public static let JPEGTransfersSyntaxes:[String] = [
        DicomConstants.JPEGLossy8bit,
        DicomConstants.JPEGLossy12bit,
        DicomConstants.JPEGExtended,
        DicomConstants.JPEGSpectralSelectionNonhierarchical6,
        DicomConstants.JPEGSpectralSelectionNonhierarchical7,
        DicomConstants.JPEGFullProgressionNonhierarchical10,
        DicomConstants.JPEGFullProgressionNonhierarchical11,
        DicomConstants.JPEGLosslessNonhierarchical,
        DicomConstants.JPEGLossless15,
        DicomConstants.JPEGExtended16,
        DicomConstants.JPEGExtended17,
        DicomConstants.JPEGSpectralSelectionHierarchical20,
        DicomConstants.JPEGSpectralSelectionHierarchical21,
        DicomConstants.JPEGFullProgressionHierarchical24,
        DicomConstants.JPEGFullProgressionHierarchical25,
        DicomConstants.JPEGLossless28,
        DicomConstants.JPEGLossless29,
        DicomConstants.JPEGLossless,
        DicomConstants.JPEGLSLossless,
        DicomConstants.JPEGLSLossy,
        DicomConstants.JPEG2000LosslessOnly,
        DicomConstants.JPEG2000,
        DicomConstants.JPEG2000Part2Lossless,
        DicomConstants.JPEG2000Part2
    ]
}



public func initLogger() {
    let console = ConsoleDestination()
    let file = FileDestination()
    
    let format = "$Dyyyy-MM-dd HH:mm:ss$d $L $M"
    
    file.format     = format
    console.format  = format
    
    if SwiftyBeaver.destinations.count == 0 {
        SwiftyBeaver.addDestination(console)
        SwiftyBeaver.addDestination(file)
    }
}
