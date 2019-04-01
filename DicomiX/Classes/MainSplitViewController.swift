//
//  SplitViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 25/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Cocoa


extension NSTextView {
    func appendString(string:String) {
        self.string += string
        self.scrollRangeToVisible(NSRange(location:self.string.count, length: 0))
    }
}



class MainSplitViewController: NSSplitViewController {

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
                }
            }
        }
    }
    
    
    
    
    
    // MARK: - IBAction
    @IBAction func expandAll(_ sender: Any) {
        if let vc:ConsoleSplitViewController = self.children[1] as? ConsoleSplitViewController {
            vc.expandAll(sender)
        }
    }
    
    
    @IBAction func collapseAll(_ sender: Any) {
        if let vc:ConsoleSplitViewController = self.children[1] as? ConsoleSplitViewController {
            vc.collapseAll(sender)
        }
    }
    
    
    @IBAction func removeElement(_ sender: Any) {
        if let vc:ConsoleSplitViewController = self.children[1] as? ConsoleSplitViewController {
            vc.removeElement(sender)
        }
    }
    
    
    @IBAction func toggleHexData(_ sender: Any) {
        if let vc:ConsoleSplitViewController = self.children[1] as? ConsoleSplitViewController {
            vc.toggleHexData(sender)
        }
    }
    
    
    

  
    @IBAction func search(_ sender: Any) {
        if let vc:ConsoleSplitViewController = self.children[1] as? ConsoleSplitViewController {
            vc.search(sender)
        }
    }
    
    
    
    
    
    
    @IBAction func showInspector(_ sender: Any) {
        let rightView = self.splitView.subviews[2]
        
        // if self.splitView.isSubviewCollapsed(rightView) {
            self.splitView.setPosition(self.view.frame.size.width-280, ofDividerAt: 1)
            rightView.isHidden = false
        // }
    }
    
    @IBAction func hideInspector(_ sender: Any) {
        let rightView = self.splitView.subviews[2]
        
        // if !self.splitView.isSubviewCollapsed(rightView) {
            self.splitView.setPosition(self.view.frame.size.width, ofDividerAt: 1)
            rightView.isHidden = true
        // }
    }
    
    
    
    @IBAction func showConsole(_ sender: Any) {
        if let vc:ConsoleSplitViewController = self.children[1] as? ConsoleSplitViewController {
            vc.showConsole(sender)
        }
    }
    
    @IBAction func hideConsole(_ sender: Any) {
        if let vc:ConsoleSplitViewController = self.children[1] as? ConsoleSplitViewController {
            vc.hideConsole(sender)
        }
    }
    
    
    
    @IBAction func showValidation(_ sender: Any) {
        if let vc:ConsoleSplitViewController = self.children[1] as? ConsoleSplitViewController {
            vc.showValidation(sender)
        }
    }
    
    @IBAction func hideValidation(_ sender: Any) {
        if let vc:ConsoleSplitViewController = self.children[1] as? ConsoleSplitViewController {
            vc.hideValidation(sender)
        }
    }
    
    
    
    override func splitViewDidResizeSubviews(_ notification: Notification) {
        let sidebarView = self.splitView.subviews[0]
        let inspectorView = self.splitView.subviews[2]
        
        if self.splitView.isSubviewCollapsed(sidebarView) {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "sidebarSplitViewCollapsed"), object: self)
        } else {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "sidebarSplitViewExpanded"), object: self)
        }
        
        if self.splitView.isSubviewCollapsed(inspectorView) {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "inspectorSplitViewCollapsed"), object: self)
        } else {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "inspectorSplitViewExpanded"), object: self)
        }
    }
}
