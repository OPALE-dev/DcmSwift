//
//  AppDicomError.swift
//  MagiX
//
//  Created by Rafael Warnault on 04/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Cocoa
import DcmSwift

public extension DicomError {
    public func alert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "\(self.errorLevel!)"
        alert.informativeText = self.errorMeaning
        
        if self.errorLevel == .notice {
            alert.alertStyle = .informational
        }
        else if self.errorLevel == .warning {
            alert.alertStyle = .warning
        }
        else if self.errorLevel == .error {
            alert.alertStyle = .critical
        }
        else {
            alert.alertStyle = .critical
        }
        
        alert.addButton(withTitle: "OK")
        return alert
    }
}
