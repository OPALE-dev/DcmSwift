//
//  ExportDICOMViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 26/03/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift

class ExportDICOMViewController: NSViewController {
    @IBOutlet var syntaxesPopUpButton: NSPopUpButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        self.loadSyntaxes()
    }
    
    
    private func loadSyntaxes() {
        syntaxesPopUpButton.removeAllItems()
        
//        syntaxesPopUpButton.addItem(withTitle: "As Original")
//        syntaxesPopUpButton.menu?.addItem(NSMenuItem.separator())
        for ts in DicomConstants.transfersSyntaxes {
            let title = "\(DicomSpec.shared.nameForUID(withUID: ts)) (\(ts))"
            if let item = syntaxesPopUpButton.menu?.addItem(withTitle: title, action: nil, keyEquivalent: "") {
                item.representedObject = ts
            }
        }
    }
}

