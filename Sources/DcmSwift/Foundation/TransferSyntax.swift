//
//  File.swift
//  DcmSwift
//
//  Created by Rafael Warnault, OPALE on 23/06/2021.
//  Copyright © 2021 OPALE. All rights reserved.
//

import Foundation


public class TransferSyntax: CustomStringConvertible, Equatable {
    /**
     List of native Transfer Syntaxes
     */
    public static let transfersSyntaxes:[String] = [
        TransferSyntax.implicitVRLittleEndian,
        TransferSyntax.explicitVRLittleEndian,
        TransferSyntax.explicitVRBigEndian,
        TransferSyntax.deflatedExplicitVRLittleEndian
    ]
    
    
    /**
     List of compressed Transfer Syntaxes
     */
    public static let JPEGTransfersSyntaxes:[String] = [
        TransferSyntax.JPEGLossy8bit,
        TransferSyntax.JPEGLossy12bit,
        TransferSyntax.JPEGExtended,
        TransferSyntax.JPEGSpectralSelectionNonhierarchical6,
        TransferSyntax.JPEGSpectralSelectionNonhierarchical7,
        TransferSyntax.JPEGFullProgressionNonhierarchical10,
        TransferSyntax.JPEGFullProgressionNonhierarchical11,
        TransferSyntax.JPEGLosslessNonhierarchical,
        TransferSyntax.JPEGLossless15,
        TransferSyntax.JPEGExtended16,
        TransferSyntax.JPEGExtended17,
        TransferSyntax.JPEGSpectralSelectionHierarchical20,
        TransferSyntax.JPEGSpectralSelectionHierarchical21,
        TransferSyntax.JPEGFullProgressionHierarchical24,
        TransferSyntax.JPEGFullProgressionHierarchical25,
        TransferSyntax.JPEGLossless28,
        TransferSyntax.JPEGLossless29,
        TransferSyntax.JPEGLossless,
        TransferSyntax.JPEGLSLossless,
        TransferSyntax.JPEGLSLossy,
        TransferSyntax.JPEG2000LosslessOnly,
        TransferSyntax.JPEG2000,
        TransferSyntax.JPEG2000Part2Lossless,
        TransferSyntax.JPEG2000Part2,
        TransferSyntax.JPEGXLLossless,
        TransferSyntax.JPEGXLJPEGRecompression,
        TransferSyntax.JPEGXL
    ]
    
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
    public static let deflatedExplicitVRLittleEndian = "1.2.840.10008.1.2.1.99"

    /// JPIP Referenced Transfer Syntaxes (PS3.5 A.6, A.7, A.11, A.12): the
    /// Pixel Data is replaced by a Pixel Data Provider URL.
    public static let jpipReferenced = "1.2.840.10008.1.2.4.94"
    public static let jpipReferencedDeflate = "1.2.840.10008.1.2.4.95"
    public static let jpipHTJ2KReferenced = "1.2.840.10008.1.2.4.204"
    public static let jpipHTJ2KReferencedDeflate = "1.2.840.10008.1.2.4.205"
    public static let jpipReferencedSyntaxes: Set<String> = [
        jpipReferenced, jpipReferencedDeflate, jpipHTJ2KReferenced, jpipHTJ2KReferencedDeflate,
    ]

    /// Whether the whole data set of this Transfer Syntax is deflated after
    /// Explicit VR Little Endian encoding (PS3.5 A.5, A.7, A.12).
    public static func deflatesDataSet(_ uid: String) -> Bool {
        uid == deflatedExplicitVRLittleEndian || uid == jpipReferencedDeflate || uid == jpipHTJ2KReferencedDeflate
    }

    
    
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

    /// JPEG XL Lossless Image Compression.
    public static let JPEGXLLossless = "1.2.840.10008.1.2.4.110"

    /// JPEG XL JPEG Recompression.
    public static let JPEGXLJPEGRecompression = "1.2.840.10008.1.2.4.111"

    /// JPEG XL Image Compression.
    public static let JPEGXL = "1.2.840.10008.1.2.4.112"
    
    
    public var tsUID:String         = "1.2.840.10008.1.2.1"
    public var tsName:String        = DicomSpec.shared.nameForUID(withUID: "1.2.840.10008.1.2.1")
    
    var vrMethod:VRMethod           = .Explicit
    var byteOrder:ByteOrder         = .LittleEndian
    
    public init?(_ transferSyntax:String) {
        if !DicomSpec.shared.isKnown(transferSyntax: transferSyntax) {
            return nil
        }
        
        tsUID   = transferSyntax
        tsName  = DicomSpec.shared.nameForUID(withUID: tsUID)
        
        if transferSyntax == TransferSyntax.implicitVRLittleEndian {
            vrMethod    = .Implicit
            byteOrder   = .LittleEndian
        } else if transferSyntax == TransferSyntax.explicitVRBigEndian {
            vrMethod    = .Explicit
            byteOrder   = .BigEndian
        }
    }

    public var capability: TransferSyntaxCapability {
        DICOMCapabilities.transferSyntax(tsUID)
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
