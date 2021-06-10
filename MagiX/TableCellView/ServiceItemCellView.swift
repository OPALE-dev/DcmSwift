//
//  ServiceItemCellView.swift
//  MagiX
//
//  Created by Rafael Warnault on 19/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Cocoa

class ServiceItemCellView: NSTableCellView {
    @IBOutlet weak var checkboxButton: NSButton!
    
    
    public var serviceItem:ServiceItem? {
        didSet {
            if let item = serviceItem {
                self.checkboxButton.state = item.enabled ? .on : .off
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    
}
