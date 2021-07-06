//
//  SRItemNode.swift
//  
//
//  Created by Rafael Warnault, OPALE on 06/07/2021.
//

import Foundation
import Html


public class SRItemNode: SRNode {
    public var relationshipType:RelationshipType?
    public var valueType:ValueType?
    public var value:Any = ""
    
    public var conceptName:SRCode?
    public var concept:SRCode?
    public var imageReferencedSOPSequence:DataSequence?
    public var measuredValues:[SRMeasuredValue] = []
    
    public init(withItem item: DataItem, parent:SRNode?) {
        if let irt = item.element(withName: "RelationshipType")?.value as? String,
           let ivt = item.element(withName: "ValueType")?.value as? String,
           let irtt = RelationshipType(rawValue: irt.trimmingCharacters(in: .whitespacesAndNewlines)),
           let ivtt = ValueType(rawValue: ivt.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            self.valueType = ivtt
            self.relationshipType = irtt
        }
        
        super.init(parent: parent)
    }
    
    
    public init(valueType:ValueType, relationshipType:RelationshipType, parent:SRNode?) {
        self.valueType = valueType
        self.relationshipType = relationshipType
        
        super.init(parent: parent)
    }
    
    
    
    // MARK: -
    public func setConceptName(withSequence sequence:DataSequence) {
        self.conceptName = SRCode(withSequence: sequence)
    }
    
    public func setConcept(withSequence sequence:DataSequence) {
        self.concept = SRCode(withSequence: sequence)
    }
    
    public func add(child:SRNode) {
        self.nodes.append(child)
    }

    
    // MARK: -
    var htmlNode:Node {
        get {
            var ns:[Node] = []

            for n in nodes {
                if let itemNode = n as? SRItemNode {
                    ns.append(itemNode.htmlNode)
                }
            }
                
            var div = Node.div()
            var label:Node = Node.b(Node.text("\(conceptName != nil ? conceptName!.codeMeaning! : ""): "))
            
            if valueType == .Image {
                if let it = imageReferencedSOPSequence?.items.first,
                   let referencedSOPClassUID = it.element(withName: "ReferencedSOPClassUID")?.value as? String {
                    label = Node.b(Node.text("\(DicomSpec.shared.nameForUID(withUID: referencedSOPClassUID)): "))
                }
            }
            else if valueType == .Container {
                label = Node.element("h\(level)", [(key: "style", value: "margin-left: \(level)0px")], Node.text("\(conceptName != nil ? conceptName!.codeMeaning! : ""): "))

            } else {
                
            }
            
            var p = Node.p(attributes: [.style(unsafe: "margin-left: \(level)0px")], label, Node.text("\(value)"))
            
            for n in ns {
                p.append(n)
            }
            
            div.append(p)
            
            return div
        }
    }
    
    var html:String {
        render(htmlNode)
    }
    
    public override var description: String {
        get {
            var str = ""
            
            str.indent(level: level)
            
            // node
            str += "* \(relationshipType != nil ? relationshipType!.rawValue : "") -> \(valueType != nil ? valueType!.rawValue : "") (\(level))"
            
            // concept name
            if let cn = conceptName {
                str += "\n"
                
                str.indent(level: level + 1)
                
                str += "\u{021B3} Concept Name: \(cn)"
            }
            
            // concept
            if let c = concept {
                str += "\n"
                str.indent(level: level + 1)
                str += "\u{021B3} Concept: \(c)"
            }
            
            // value
            str += "\n"
            str.indent(level: level + 1)
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
}
