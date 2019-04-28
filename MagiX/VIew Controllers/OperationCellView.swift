//
//  OperationCellView.swift
//  MagiX
//
//  Created by Rafael Warnault on 28/04/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa

class OperationCellView: NSTableCellView {
    @IBOutlet weak var progressBar: NSProgressIndicator!
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    
}
