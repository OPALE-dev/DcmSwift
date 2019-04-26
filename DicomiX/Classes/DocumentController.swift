//
//  DocumentController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 11/11/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Cocoa

class DocumentController: NSDocumentController {
    public static var canOpenUntitledDocument = false
    
    
    override func newDocument(_ sender: Any?) {
        // do nothing here
    }
    
    
    override func openDocument(_ sender: Any?) {
        if !DocumentController.canOpenUntitledDocument { return }
        
        super.openDocument(sender)
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
