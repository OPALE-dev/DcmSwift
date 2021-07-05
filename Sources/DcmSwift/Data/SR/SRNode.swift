//
//  File.swift
//  
//
//  Created by Rafael Warnault on 05/07/2021.
//

import Foundation

public enum RelationshipType {
    case root               // Internal root of the nodes
    case contains           // DICOM Relationship Type: CONTAINS
    case hasObsContext      // DICOM Relationship Type: HAS OBS CONTEXT
    case hasAcqContext      // DICOM Relationship Type: HAS ACQ CONTEXT
    case hasConceptMod      // DICOM Relationship Type: HAS CONCEPT MOD
    case hasProperties      // DICOM Relationship Type: HAS PROPERTIES
    case inferredFrom       // DICOM Relationship Type: INFERRED FROM
    case selectedFrom       // DICOM Relationship Type: SELECTED FROM
}

public class SRNode {
    public var parent:SRNode?
    public var nodes:[SRNode] = []
    public var relationshipType:RelationshipType
    
    init(parent:SRNode?, relationshipType:RelationshipType) {
        self.relationshipType = relationshipType
        
        if let p = parent {
            self.parent = p
        }
    }
    
    public func add(node:SRNode) {
        self.nodes.append(node)
    }
}
