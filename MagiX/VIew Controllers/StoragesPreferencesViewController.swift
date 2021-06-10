//
//  StoragesPreferencesViewController.swift
//  MagiX
//
//  Created by Rafael Warnault on 19/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Cocoa

class StoragesPreferencesViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
    @IBOutlet weak var tableView: NSTableView!
    
    @IBOutlet weak var onImportCopyRadio: NSButton!
    @IBOutlet weak var onImportLinkRadio: NSButton!
    @IBOutlet weak var onImportAskRadio: NSButton!
    
    @IBOutlet weak var storageTypeLabel: NSTextField!
    @IBOutlet weak var storagePathField: NSTextField!
    @IBOutlet weak var storageChooseButton: NSButton!
    @IBOutlet weak var storageDiskSpaceField: NSTextField!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        self.loadOnImport()
        self.clearFields()
        
        self.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }
    
    
    
    @IBAction func onImportChanged(_ sender: Any) {
        onImportCopyRadio.state = .off
        onImportLinkRadio.state = .off
        onImportAskRadio.state  = .off
        
        if let button = sender as? NSButton {
            if button == onImportCopyRadio {
                button.state = .on
                UserDefaults.standard.set(OnImportAction.Copy.rawValue, forKey: "OnImportAction")
            }
            else if button == onImportLinkRadio {
                button.state = .on
                UserDefaults.standard.set(OnImportAction.Link.rawValue, forKey: "OnImportAction")
            }
            else if button == onImportAskRadio {
                button.state = .on
                UserDefaults.standard.set(OnImportAction.Ask.rawValue, forKey: "OnImportAction")
            }
        }
    }
    
    
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return StorageController.shared.storages.count
    }
    
    
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: NSTableCellView?
        
        view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "StorageCellView"), owner: self) as? NSTableCellView
        
        if let cell = view as? StorageCellView {
            if let path = StorageController.shared.storages[row].path {
                cell.typeField.stringValue = self.storageType(forInt: 0)
                
                var url = URL(fileURLWithPath: path)
                url.deleteLastPathComponent()
                cell.pathField.stringValue = url.lastPathComponent
            }
        }
        
        return view
    }
    
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        if self.tableView.selectedRow != -1 {
            let selectedItem = StorageController.shared.storages[self.tableView.selectedRow]
            
            self.enableFields()
            
            self.storageTypeLabel.stringValue = self.storageType(forInt: selectedItem.storageType)
            self.storagePathField.stringValue = selectedItem.path!
            self.storageDiskSpaceField.objectValue = selectedItem.minimumRemainingDiskSpace
        } else {
            self.clearFields()
        }
    }
    
    
    
    private func loadOnImport() {
        let action = UserDefaults.standard.integer(forKey: "OnImportAction")
        
        onImportCopyRadio.state = .off
        onImportLinkRadio.state = .off
        onImportAskRadio.state  = .off
        
        switch action {
        case OnImportAction.Copy.rawValue:
            onImportCopyRadio.state  = .on
            
        case OnImportAction.Link.rawValue:
            onImportLinkRadio.state  = .on
            
        case OnImportAction.Ask.rawValue:
            onImportAskRadio.state  = .on
            
        default:
            onImportCopyRadio.state = .on
            onImportLinkRadio.state = .off
            onImportAskRadio.state  = .off
        }
    }
    
    
    
    private func enableFields() {
        self.storageTypeLabel.isEnabled = true
        self.storagePathField.isEnabled = true
        self.storageDiskSpaceField.isEnabled = true
        self.storageChooseButton.isEnabled = true
    }
    
    
    private func clearFields() {
        self.storageTypeLabel.stringValue = ""
        self.storagePathField.stringValue = ""
        self.storageDiskSpaceField.stringValue = ""
        
        self.storageTypeLabel.isEnabled = false
        self.storagePathField.isEnabled = false
        self.storageDiskSpaceField.isEnabled = false
        self.storageChooseButton.isEnabled = false
    }
    
    
    
    private func storageType(forInt type:Int32) -> String {
        switch type {
        case 0:
            return "Local Storage"
        default:
            return "Unknow Storage"
        }
    }
}
