//
//  ReleaseRP.swift
//  DcmSwift
//
//  Created by Rafael Warnault on 03/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation


public class ReleaseRP: PDUMessage {
    public override func messageName() -> String {
        return "A-RELEASE-RSP"
    }
    
}
