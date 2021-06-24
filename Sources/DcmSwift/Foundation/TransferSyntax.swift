//
//  File.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 23/06/2021.
//  Copyright © 2021 Read-Write.fr. All rights reserved.
//

import Foundation


public class TransferSyntax: CustomStringConvertible, Equatable {
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
    
    public var tsUID:String                     = "1.2.840.10008.1.2.1"
    public var tsName:String                    = DicomSpec.shared.nameForUID(withUID: "1.2.840.10008.1.2.1")
    
    var vrMethod:VRMethod        = .Explicit
    var byteOrder:ByteOrder      = .LittleEndian
    
    public init?(_ transferSyntax:String) {
        if !DicomSpec.shared.isSupported(transferSyntax: transferSyntax) {
            return nil
        }
        
        tsUID   = transferSyntax
        tsName  = DicomSpec.shared.nameForUID(withUID: tsUID)
        
        if transferSyntax == TransferSyntax.implicitVRLittleEndian {
            vrMethod    = .Implicit
            byteOrder   = .LittleEndian
        }
    }
    
    public static func == (lhs: TransferSyntax, rhs: TransferSyntax) -> Bool {
        return lhs.tsUID == rhs.tsUID
    }
    
    public static func == (lhs: TransferSyntax, rhs: String) -> Bool {
        return lhs.tsUID == rhs
    }
    
    public static func == (lhs: String, rhs: TransferSyntax) -> Bool {
        return lhs == rhs.tsUID
    }
    
    public var description: String {
        return "\(tsName) (\(tsUID))"
    }
}
