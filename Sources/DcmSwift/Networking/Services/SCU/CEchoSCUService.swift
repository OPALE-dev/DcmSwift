//
//  File.swift
//  
//
//  Created by Rafael Warnault on 23/07/2021.
//

import Foundation


public class CEchoSCUService: DicomService {
    public override var commandField:CommandField {
        .C_ECHO_RQ
    }
    
    
    public override var abstractSyntaxes:[String] {
        [DicomConstants.verificationSOP]
    }
}
