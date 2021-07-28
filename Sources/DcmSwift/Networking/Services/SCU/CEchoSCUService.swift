//
//  File.swift
//  
//
//  Created by Rafael Warnault, OPALE on 23/07/2021.
//

import Foundation


public class CEchoSCUService: ServiceClassUser {
    public override var commandField:CommandField {
        .C_ECHO_RQ
    }
    
    
    public override var abstractSyntaxes:[String] {
        [DicomConstants.verificationSOP]
    }
}
