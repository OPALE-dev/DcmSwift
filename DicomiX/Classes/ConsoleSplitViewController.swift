//
//  ConsoleSplitViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 25/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Cocoa

class ConsoleSplitViewController: NSSplitViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
            if let _ = representedObject as? DicomDocument {
                for vc in self.children {
                    vc.representedObject = representedObject
                    
                    self.hideConsole(self)
                }
            }
        }
    }
    
    
    
    
    @IBAction func expandAll(_ sender: Any) {
        if let vc:DatasetViewController = self.children[0] as? DatasetViewController {
            vc.expandAll(sender)
        }
    }
    
    
    @IBAction func collapseAll(_ sender: Any) {
        if let vc:DatasetViewController = self.children[0] as? DatasetViewController {
            vc.collapseAll(sender)
        }
    }
    
    @IBAction func removeElement(_ sender: Any) {
        if let vc:DatasetViewController = self.children[0] as? DatasetViewController {
            vc.removeElement(sender)
        }
    }
    
    
    @IBAction func updateValueFormat(_ sender: Any) {
        if let vc:DatasetViewController = self.children[0] as? DatasetViewController {
            vc.updateValueFormat(sender)
        }
    }
    
    
    
    @IBAction func showConsole(_ sender: Any) {
        let rightView = self.splitView.subviews[1]
        
        if self.splitView.isSubviewCollapsed(rightView) {
            self.splitView.setPosition(self.view.frame.size.width-436, ofDividerAt: 0)
            rightView.isHidden = false
        }
    }
    
    @IBAction func hideConsole(_ sender: Any) {
        let rightView = self.splitView.subviews[1]
        
        if !self.splitView.isSubviewCollapsed(rightView) {
            self.splitView.setPosition(self.view.frame.size.width, ofDividerAt: 0)
            rightView.isHidden = true
        }
    }
    
    
    @IBAction func showValidation(_ sender: Any) {
        if let vc:DatasetViewController = self.children[0] as? DatasetViewController {
            vc.showValidation(sender)
        }
    }
    
    @IBAction func hideValidation(_ sender: Any) {
        if let vc:DatasetViewController = self.children[0] as? DatasetViewController {
            vc.hideValidation(sender)
        }
    }
    
    
    @IBAction func search(_ sender: Any) {
        if let vc:DatasetViewController = self.children[0] as? DatasetViewController {
            vc.search(sender)
        }
    }
    
    
    
    
    
    
    override func splitViewDidResizeSubviews(_ notification: Notification) {
        let consoleView = self.splitView.subviews[1]
        
        if self.splitView.isSubviewCollapsed(consoleView) {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "consoleSplitViewCollapsed"), object: self)
        } else {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "consoleSplitViewExpanded"), object: self)
        }
    }
}
