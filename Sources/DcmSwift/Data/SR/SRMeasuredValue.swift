//
//  SRMeasuredValue.swift
//  
//
//  Created by Rafael Warnault, OPALE on 06/07/2021.
//

import Foundation


public class SRMeasuredValue: SRItemNode {
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
