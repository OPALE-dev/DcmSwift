//
//  DocumentController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 11/11/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Cocoa

class DocumentController: NSDocumentController {
    override func newDocument(_ sender: Any?) {
        
    }

    
    override func responds(to aSelector: Selector!) -> Bool {
        
        if #available(OSX 10.12, *) {
            if aSelector == #selector(NSResponder.newWindowForTab(_:)) {
                return false
            }
        }
        
        return super.responds(to: aSelector)
    }
}
