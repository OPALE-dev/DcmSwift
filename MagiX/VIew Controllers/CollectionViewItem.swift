//
//  CollectionViewItem.swift
//  MagiX
//
//  Created by Rafael Warnault on 27/04/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift

class CollectionViewItem: NSCollectionViewItem {
    @IBOutlet weak var modalityLabel: NSTextField!
    @IBOutlet weak var instancesCountLabel: NSTextField!
    
    var image: NSImage? {
        didSet {
            guard isViewLoaded else { return }
            if let image = image {
                imageView?.image = image
                //textField?.stringValue = imageFile.fileName
            } else {
                imageView?.image = nil
                textField?.stringValue = ""
            }
        }
        
    }
    

    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        
        self.imageView?.wantsLayer = true
        self.imageView?.layer?.backgroundColor = NSColor.black.cgColor
        
        view.layer?.borderWidth = 0.0
        view.layer?.borderColor = NSColor.white.cgColor
        
        self.setHighlight(selected: false)
    }
    
    func setHighlight(selected: Bool) {
        view.layer?.borderWidth = selected ? 2.0 : 0.0
    }
}
