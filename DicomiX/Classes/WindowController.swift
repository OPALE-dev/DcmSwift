//
//  WindowController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 24/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
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
        
        if UserDefaults.standard.bool(forKey: "SidebarExpanded") {
            sidebarSplitViewExpanded()
        } else {
            sidebarSplitViewCollapsed()
        }
        
        // update addRemoveSegmentedControl regarding current AllowDICOMEditing setting
        self.updateAddRemoveButton()
        
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
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeKeyNotification(notification:) ) ,
            name: NSWindow.didBecomeKeyNotification,
            object: nil)
    }
    
    
    
    
    
    // MARK: - Notifications
    @objc func didBecomeKeyNotification(notification:Notification) {
        if let window = notification.object as? NSWindow, window == self.window {
            /// we update DICOM editing buttons when window changed
            self.updateAddRemoveButton()
            
            if let splitViewItem = self.splitViewController.splitViewItems.first {
                viewsSegmentedControl.setSelected(!splitViewItem.isCollapsed, forSegment: 0)
            }
            
            if let consoleSplitViewController = self.splitViewController.splitViewItems[1].viewController as? ConsoleSplitViewController {
                if let datasetViewController = consoleSplitViewController.splitViewItems.first?.viewController as? DatasetViewController {
                    if let datasetSplitView = datasetViewController.splitView {
                        viewsSegmentedControl.setSelected(!datasetSplitView.isSubviewCollapsed(datasetSplitView.subviews[1]), forSegment: 1)
                    }
                }
                
                if let splitViewItem = consoleSplitViewController.splitViewItems.last {
                    viewsSegmentedControl.setSelected(!splitViewItem.isCollapsed, forSegment: 2)
                }
            }
            
            if let splitViewItem = self.splitViewController.splitViewItems.last {
                viewsSegmentedControl.setSelected(!splitViewItem.isCollapsed, forSegment: 3)
            }
        }
    }
    
    
    @objc func sidebarSplitViewCollapsed(notification:Notification) {
        self.sidebarSplitViewCollapsed()
    }
    
    
    @objc func sidebarSplitViewExpanded(notification:Notification) {
        self.sidebarSplitViewExpanded()
    }

    
    
    
    
    @objc func validationSplitViewCollapsed(notification:Notification) {
        viewsSegmentedControl.setSelected(false, forSegment: 1)
        
        if let menu = NSApp.mainMenu?.items[4] {
            if let item = menu.submenu?.item(withTag: 20) {
                item.title = "Show Validation"
                item.action = #selector(MainSplitViewController.showValidation(_:))
            }
        }
    }
    
    @objc func validationSplitViewExpanded(notification:Notification) {
        viewsSegmentedControl.setSelected(true, forSegment: 1)
        
        if let menu = NSApp.mainMenu?.items[4] {
            if let item = menu.submenu?.item(withTag: 20) {
                item.title = "Hide Validation"
                item.action = #selector(MainSplitViewController.hideValidation(_:))
            }
        }
    }
    
    
    
    
    @objc func consoleSplitViewCollapsed(notification:Notification) {
        viewsSegmentedControl.setSelected(false, forSegment: 2)
        
        if let menu = NSApp.mainMenu?.items[4] {
            if let item = menu.submenu?.item(withTag: 30) {
                item.title = "Show Hex View"
                item.action = #selector(MainSplitViewController.showConsole(_:))
            }
        }
    }
    
    @objc func consoleSplitViewExpanded(notification:Notification) {
        viewsSegmentedControl.setSelected(true, forSegment: 2)
        
        if let menu = NSApp.mainMenu?.items[4] {
            if let item = menu.submenu?.item(withTag: 30) {
                item.title = "Hide Hex View"
                item.action = #selector(MainSplitViewController.hideConsole(_:))
            }
        }
    }
    
    
    
    
    @objc func inspectorSplitViewCollapsed(notification:Notification) {
        viewsSegmentedControl.setSelected(false, forSegment: 3)
        
        if let menu = NSApp.mainMenu?.items[4] {
            if let item = menu.submenu?.item(withTag: 40) {
                item.title = "Show Inspector"
                item.action = #selector(MainSplitViewController.showInspector(_:))
            }
        }
    }
    
    @objc func inspectorSplitViewExpanded(notification:Notification) {
        viewsSegmentedControl.setSelected(true, forSegment: 3)
        
        if let menu = NSApp.mainMenu?.items[4] {
            if let item = menu.submenu?.item(withTag: 40) {
                item.title = "Hide Inspector"
                item.action = #selector(MainSplitViewController.hideInspector(_:))
            }
        }
    }
    
    
    
    
    @objc func elementSelectionDidChange(notification:Notification) {
        self.updateAddRemoveButton()
        
        if UserDefaults.standard.bool(forKey: "AllowDICOMEditing") {
            if (notification.object as? Array<Any>) != nil {
                addRemoveSegmentedControl.setEnabled(true, forSegment: 1)
            } else {
                addRemoveSegmentedControl.setEnabled(false, forSegment: 1)
            }
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
//        if let menuItem = sender as? NSMenuItem {
//            menuItem.title = "Hide Sidebar"
//            menuItem.target = self
//            menuItem.action = #selector(hideSidebar(_:))
//        }
        self.splitViewController.splitView.setPosition(250, ofDividerAt: 0)
    }
    
    @IBAction func hideSidebar(_ sender: Any) {
//        if let menuItem = sender as? NSMenuItem {
//            menuItem.title = "Show Sidebar"
//            menuItem.target = self
//            menuItem.action = #selector(showSidebar(_:))
//        }
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
                    //self.viewsSegmentedControl.setSelected(false, forSegment: 3)
                }
                else {
                    self.splitViewController.showInspector(sender)
                    //self.viewsSegmentedControl.setSelected(true, forSegment: 3)
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
    
    
    
    // MARK: -
    
    private func updateAddRemoveButton() {
        addRemoveSegmentedControl.setEnabled(UserDefaults.standard.bool(forKey: "AllowDICOMEditing"), forSegment: 0)
        addRemoveSegmentedControl.setEnabled(UserDefaults.standard.bool(forKey: "AllowDICOMEditing"), forSegment: 1)
    }
    
    
    private func sidebarSplitViewCollapsed() {
        viewsSegmentedControl.setSelected(false, forSegment: 0)
        
        UserDefaults.standard.set(false, forKey: "SidebarExpanded")
        
        if let menu = NSApp.mainMenu?.items[4] {
            if let item = menu.submenu?.item(withTag: 10) {
                item.title = "Show Sidebar"
                item.action = #selector(showSidebar(_:))
            }
        }
    }
    
    private func sidebarSplitViewExpanded() {
        viewsSegmentedControl.setSelected(true, forSegment: 0)
        
        UserDefaults.standard.set(true, forKey: "SidebarExpanded")
        
        if let menu = NSApp.mainMenu?.items[4] {
            if let item = menu.submenu?.item(withTag: 10) {
                item.title = "Hide Sidebar"
                item.action = #selector(hideSidebar(_:))
            }
        }
    }
}
