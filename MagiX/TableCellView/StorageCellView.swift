//
//  StorageCellView.swift
//  MagiX
//
//  Created by Rafael Warnault on 19/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa

class StorageCellView: NSTableCellView {
    @IBOutlet weak var typeField: NSTextField!
    @IBOutlet weak var pathField: NSTextField!

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Drawing code here.
    }
    
    
}
