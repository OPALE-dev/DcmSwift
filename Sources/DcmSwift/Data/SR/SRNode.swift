//
//  File.swift
//  
//
//  Created by Rafael Warnault on 05/07/2021.
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


public class SRMeasuredValue: SRNode {
    public var measurementUnitsCode:SRCode?
    
    public override init(withItem item: DataItem, parent: SRNode?) {
        super.init(withItem: item, parent: parent)
        
        if let ms = item.element(withName: "MeasurementUnitsCodeSequence") as? DataSequence {
            if let code = SRCode(withSequence: ms) {
                measurementUnitsCode = code
            }
        }
        
        if let numericValue = item.element(withName: "NumericValue")?.value as? String {
            value = numericValue
        }
    }
    
    public override var description: String {
        get {
            var str = ""
            
            // value
            str.indent(level: level)
            str += "\u{021B3} Value: \(value)\n"

            if let cv = measurementUnitsCode?.codeValue {
                str.indent(level: level)
                str += "\u{021B3} Measurement Units: \(cv)"
            }

            return str
        }
    }
}


public class SRNode: CustomStringConvertible {
    public var parent:SRNode?
    public var nodes:[SRNode] = []
    public var valueType:ValueType?
    public var relationshipType:RelationshipType?
    public var value:Any = ""
    
    public var conceptName:SRCode?
    public var concept:SRCode?
    public var measuredValues:[SRMeasuredValue] = []
    
    public var level:Int = 1
    
    public var description: String {
        get {
            var str = ""
            
            str.indent(level: level)
            
            // node
            str += "* \(relationshipType != nil ? relationshipType!.rawValue : "") -> \(valueType != nil ? valueType!.rawValue : "") (\(level))"
            
            // concept name
            if let cn = conceptName {
                str += "\n"
                
                str.indent(level: level)
                
                str += "\u{021B3} Concept Name: \(cn)"
            }
            
            // concept
            if let c = concept {
                str += "\n"
                str.indent(level: level)
                str += "\u{021B3} Concept: \(c)"
            }
            
            // value
            str += "\n"
            str.indent(level: level)
            str += "\u{021B3} Value: \(value)\n"
            
            // measured values
            for m in measuredValues {
                str += "\(m)\n"
            }
                        
            // children
            for n in nodes {
                str += "\(n)\n"
            }
            
            str += "\n"
            
            return str
        }
    }
    
    public func print(inString:String) -> String {
        var result = inString
                
        result += "\n\(description)"
        
        return result
    }
    
    
    public init(withItem item: DataItem, parent:SRNode?) {
        if let irt = item.element(withName: "RelationshipType")?.value as? String,
           let ivt = item.element(withName: "ValueType")?.value as? String,
           let irtt = RelationshipType(rawValue: irt.trimmingCharacters(in: .whitespacesAndNewlines)),
           let ivtt = ValueType(rawValue: ivt.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            self.valueType = ivtt
            self.relationshipType = irtt
        }
        
        if let p = parent {
            self.parent = p
            
            // upgrade level
            self.level += p.level
        }
    }
    
    public init(valueType:ValueType, relationshipType:RelationshipType, parent:SRNode?) {
        self.valueType = valueType
        self.relationshipType = relationshipType
        
        if let p = parent {
            self.parent = p
            
            // upgrade level
            self.level += p.level
        }
    }
    
    public func setConceptName(withSequence sequence:DataSequence) {
        self.conceptName = SRCode(withSequence: sequence)
    }
    
    public func setConcept(withSequence sequence:DataSequence) {
        self.concept = SRCode(withSequence: sequence)
    }
    
    public func add(child:SRNode) {
        self.nodes.append(child)
    }
}
