//
//  File.swift
//  
//
//  Created by Rafael Warnault, OPALE on 05/07/2021.
//

import Foundation


public enum ValueType:String {
    case Text               = "TEXT"                // DICOM Value Type: TEXT
    case Code               = "CODE"                // DICOM Value Type: CODE
    case Num                = "NUM"                 // DICOM Value Type: NUM
    case DateTime           = "DATETIME"            // DICOM Value Type: DATETIME
    case Date               = "DATE"                // DICOM Value Type: DATE
    case Time               = "TIME"                // DICOM Value Type: TIME
    case UIDRef             = "UIDREF"              // DICOM Value Type: UIDREF
    case PName              = "PNAME"               // DICOM Value Type: PNAME
    case SCoord             = "SCOORD"              // DICOM Value Type: SCOORD
    case SCoord3D           = "SCOORD3D"            // DICOM Value Type: SCOORD3D
    case TCoord             = "TCOORD"              // DICOM Value Type: TCOORD
    case Composite          = "COMPOSITE"           // DICOM Value Type: COMPOSITE
    case Image              = "IMAGE"               // DICOM Value Type: IMAGE
    case Waveform           = "WAVEFORM"            // DICOM Value Type: WAVEFORM
    case Container          = "CONTAINER"           // DICOM Value Type: CONTAINER
}



public enum RelationshipType:String {
    case root               = "ROOT"                // Internal root of the nodes
    case contains           = "CONTAINS"            // DICOM Relationship Type: CONTAINS
    case hasObsContext      = "HAS OBS CONTEXT"     // DICOM Relationship Type: HAS OBS CONTEXT
    case hasAcqContext      = "HAS ACQ CONTEXT"     // DICOM Relationship Type: HAS ACQ CONTEXT
    case hasConceptMod      = "HAS CONCEPT MOD"     // DICOM Relationship Type: HAS CONCEPT MOD
    case hasProperties      = "HAS PROPERTIES"      // DICOM Relationship Type: HAS PROPERTIES
    case inferredFrom       = "INFERRED FROM"       // DICOM Relationship Type: INFERRED FROM
    case selectedFrom       = "SELECTED FROM"       // DICOM Relationship Type: SELECTED FROM
}



public class SRNode: CustomStringConvertible {
    public var parent:SRNode?
    public var nodes:[SRNode] = []
    public var level:Int = 1
    
    public init(parent:SRNode?) {
        if let p = parent {
            self.parent = p
            
            // upgrade level
            self.level += p.level
        }
    }
    
    public var description: String {
        get {
            ""
        }
    }
}
