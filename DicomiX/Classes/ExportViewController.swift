//
//  ExportViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 07/11/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Cocoa


class ExportViewController: NSViewController {
    @IBOutlet var myStackView: NSStackView!
    
    var oldSelection: Int = 0
    var newSelection: Int = 0
    var buttons: [NSButton]?
    var tabViewDelegate: NSTabViewController?
    
    
    // MARK: - View methods
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        buttons = (myStackView.arrangedSubviews as! [NSButton])
    }
    
    
    
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        // Once on load
        tabViewDelegate = segue.destinationController as?  NSTabViewController
    }
    
    
    
    // MARK: - IBAction
    @IBAction func selectedButton(_ sender: NSButton) {
        newSelection = sender.tag
        tabViewDelegate?.selectedTabViewItemIndex = newSelection
        
        buttons![oldSelection].state = .off
        sender.state = .on
        
        oldSelection = newSelection
    }
}
