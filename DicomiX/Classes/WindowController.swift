//
//  WindowController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 24/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift


class WindowController: NSWindowController, NSToolbarDelegate {
    @IBOutlet weak var splitViewController:MainSplitViewController!
    @IBOutlet weak var viewsSegmentedControl:NSSegmentedControl!
    @IBOutlet weak var addRemoveSegmentedControl:NSSegmentedControl!
    
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        window?.titleVisibility = .hidden
        
        self.splitViewController = self.contentViewController as? MainSplitViewController
        self.hideSidebar(self)
        
        // Observe splitviews state
        NotificationCenter.default.addObserver(self, selector: #selector(sidebarSplitViewCollapsed(notification:)), name: NSNotification.Name(rawValue: "sidebarSplitViewCollapsed"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sidebarSplitViewExpanded(notification:)), name: NSNotification.Name(rawValue: "sidebarSplitViewExpanded"), object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(inspectorSplitViewCollapsed(notification:)), name: NSNotification.Name(rawValue: "inspectorSplitViewCollapsed"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(inspectorSplitViewExpanded(notification:)), name: NSNotification.Name(rawValue: "inspectorSplitViewExpanded"), object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(validationSplitViewCollapsed(notification:)), name: NSNotification.Name(rawValue: "validationSplitViewCollapsed"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(validationSplitViewExpanded(notification:)), name: NSNotification.Name(rawValue: "validationSplitViewExpanded"), object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(consoleSplitViewCollapsed(notification:)), name: NSNotification.Name(rawValue: "consoleSplitViewCollapsed"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(consoleSplitViewExpanded(notification:)), name: NSNotification.Name(rawValue: "consoleSplitViewExpanded"), object: nil)
        
        // Observe selected element changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(elementSelectionDidChange(notification:) ) ,
            name: .elementSelectionDidChange,
            object: nil)
    }
    

    
    
    // MARK: - Notifications
    @objc func sidebarSplitViewCollapsed(notification:Notification) {
        viewsSegmentedControl.setSelected(false, forSegment: 0)
    }
    
    @objc func sidebarSplitViewExpanded(notification:Notification) {
        viewsSegmentedControl.setSelected(true, forSegment: 0)
    }
    
    @objc func validationSplitViewCollapsed(notification:Notification) {
        viewsSegmentedControl.setSelected(false, forSegment: 1)
    }
    
    @objc func validationSplitViewExpanded(notification:Notification) {
        viewsSegmentedControl.setSelected(true, forSegment: 1)
    }
    
    @objc func consoleSplitViewCollapsed(notification:Notification) {
        viewsSegmentedControl.setSelected(false, forSegment: 2)
    }
    
    @objc func consoleSplitViewExpanded(notification:Notification) {
        viewsSegmentedControl.setSelected(true, forSegment: 2)
    }
    
    @objc func inspectorSplitViewCollapsed(notification:Notification) {
        viewsSegmentedControl.setSelected(false, forSegment: 3)
    }
    
    @objc func inspectorSplitViewExpanded(notification:Notification) {
        viewsSegmentedControl.setSelected(true, forSegment: 3)
    }
    
    @objc func elementSelectionDidChange(notification:Notification) {
        if (notification.object as? Array<Any>) != nil {
            addRemoveSegmentedControl.setEnabled(true, forSegment: 1)
        } else {
            addRemoveSegmentedControl.setEnabled(false, forSegment: 1)
        }
    }
    
    
    
    // MARK: - IBAction
    @IBAction func expandCollapse(_ sender: Any) {
        if let sc = sender as? NSSegmentedControl {
            if sc.selectedSegment == 1 {
                self.splitViewController.expandAll(sender)
            }
            else if sc.selectedSegment == 0 {
                self.splitViewController.collapseAll(sender)
            }
        }
        
    }
    
    @IBAction func addRemove(_ sender: Any) {
        if let sc = sender as? NSSegmentedControl {
            if sc.selectedSegment == 0 {
                print("add")
                // Add
                self.performSegue(withIdentifier: "ShowAddElement", sender: self)
            }
            else if sc.selectedSegment == 1 {
                // Remove
                let alert = NSAlert()
                alert.messageText = "Remove Data Element"
                alert.informativeText = "Are you sure you want to remove this data element from the dataset?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Yes")
                alert.addButton(withTitle: "Cancel")
                
                alert.beginSheetModal(for: self.window!, completionHandler: { (modalResponse) in
                    if modalResponse == NSApplication.ModalResponse.alertFirstButtonReturn {
                        self.splitViewController.removeElement(sender)
                    }
                })
            }
        }
    }
    
    @IBAction func toggleHexData(_ sender: Any) {
        self.splitViewController.toggleHexData(sender)
    }
    
    @IBAction func export(_ sender: Any) {
        
    }
    
    @IBAction func search(_ sender: Any) {
        self.splitViewController.search(sender)
    }
    
    @IBAction func showSidebar(_ sender: Any) {
        self.splitViewController.splitView.setPosition(250, ofDividerAt: 0)
    }
    
    @IBAction func hideSidebar(_ sender: Any) {
        self.splitViewController.splitView.setPosition(0, ofDividerAt: 0)
    }
    
    

    @IBAction func views(_ sender: Any) {
        if let sc = sender as? NSSegmentedControl {
            if sc.selectedSegment == 0 {
                if !sc.isSelected(forSegment: sc.selectedSegment) {
                    self.splitViewController.splitView.setPosition(0, ofDividerAt: 0)
                    //self.viewsSegmentedControl.setSelected(false, forSegment: 0)
                }
                else {
                    self.splitViewController.splitView.setPosition(250, ofDividerAt: 0)
                   //self.viewsSegmentedControl.setSelected(true, forSegment: 0)
                }
            }
            else if sc.selectedSegment == 1 {
                if !sc.isSelected(forSegment: sc.selectedSegment) {
                    self.splitViewController.hideValidation(sender)
                    //self.viewsSegmentedControl.setSelected(false, forSegment: 1)
                }
                else {
                    self.splitViewController.showValidation(sender)
                    //self.viewsSegmentedControl.setSelected(true, forSegment: 1)
                }
            }
            else if sc.selectedSegment == 2 {
                if !sc.isSelected(forSegment: sc.selectedSegment) {
                    self.splitViewController.hideConsole(sender)
                    //self.viewsSegmentedControl.setSelected(false, forSegment: 2)
                }
                else {
                    self.splitViewController.showConsole(sender)
                    //self.viewsSegmentedControl.setSelected(true, forSegment: 2)
                }
            }
            else if sc.selectedSegment == 3 {
                if !sc.isSelected(forSegment: sc.selectedSegment) {
                    self.splitViewController.hideInspector(sender)
                    self.viewsSegmentedControl.setSelected(false, forSegment: 3)
                }
                else {
                    self.splitViewController.showInspector(sender)
                    self.viewsSegmentedControl.setSelected(true, forSegment: 3)
                }
            }
        }
    }
    
    
    
    
    
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        if item.itemIdentifier.rawValue == "Save" {
            return (self.document?.hasUnautosavedChanges)!
        }
        return true
    }
    
    
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if(segue.identifier == "ShowAddElement") {
            if let c = segue.destinationController as? AddElementController {
                c.representedObject = self.document
            }
        }
        else if(segue.identifier == "Export") {
            if let c = segue.destinationController as? ExportViewController {
                c.representedObject = self.document
            }
        }
    }
}
