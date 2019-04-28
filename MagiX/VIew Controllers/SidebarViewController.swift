//
//  SidebarViewController.swift
//  MagiX
//
//  Created by Rafael Warnault on 28/04/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa
import CoreData

class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDelegate, NSOutlineViewDataSource {
    @IBOutlet weak var directoriesOutlineView: NSOutlineView!
    @IBOutlet weak var operationsTableView: NSTableView!
    
    var categories:[String] = ["DIRECTORIES", "REMOTES"]
    var directories:[Directory] = []
    var remotes:[Remote] = []
    
    
    // MARK: - View Controller
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        NotificationCenter.default.addObserver(self, selector: #selector(loadOperationChanged(n:)), name: .loadOperationStarted, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(loadOperationChanged(n:)), name: .loadOperationFinished, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(loadOperationChanged(n:)), name: .loadOperationCancelled, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(loadOperationChanged(n:)), name: .loadOperationUpdated, object: nil)
        
        self.directories = DataController.shared.fetchDirectories()
        self.remotes = DataController.shared.fetchRemotes()
        
        self.directoriesOutlineView.reloadData()
        self.directoriesOutlineView.expandItem(self.directoriesOutlineView.item(atRow: 1), expandChildren: true)
        self.directoriesOutlineView.expandItem(self.directoriesOutlineView.item(atRow: 0), expandChildren: true)
    }
    
    
    
    
    
    
    
    
    // MARK: - Notification
    
    @objc func loadOperationChanged(n:Notification) {
        self.operationsTableView.reloadData()
    }
    
    
    
    // MARK: - IBAction
    
    @IBAction func newDirectory(_ sender: Any) {
        let newDirectory = PrivateDirectory(context: DataController.shared.context)
        newDirectory.name = "New Directory \(directories.count)"
        
        DataController.shared.save()
        
        self.directories.append(newDirectory)
        self.directoriesOutlineView.reloadData()
    }
    
    @IBAction func newRemote(_ sender: Any) {
        let newRemote = Remote(context: DataController.shared.context)
        newRemote.name = "New Remote \(remotes.count)"
        
        DataController.shared.save()
        
        self.remotes.append(newRemote)
        self.directoriesOutlineView.reloadData()
    }
    
    @IBAction func remove(_ sender: Any) {
        let selectedItem = self.directoriesOutlineView.item(atRow: self.directoriesOutlineView.selectedRow)
        
        if let d = selectedItem as? PrivateDirectory {
            DataController.shared.removeDirectory(d)
            
            if let index = self.directories.index(of:d) {
                self.directories.remove(at: index)
            }
        }
        
        self.directoriesOutlineView.reloadData()
    }
    
    
    
    // MARK: - Outline View
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return self.categories.count
        } else {
            if (item as! String) == self.categories.first {
                return self.directories.count
            }
            else if (item as! String) == self.categories.last {
                return self.remotes.count
            }
        }
        return 0
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let headerItem = item as? String {
            if headerItem == self.categories.first {
                return self.directories[index]
            }
            else if headerItem == self.categories.last {
                return self.remotes[index]
            }
        }
        
        return self.categories[index]
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return ((item as? String) != nil) ? true : false
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        return false
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return ((item as? String) != nil) ? false : true
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        var view: NSTableCellView?
        
        if let headerItem = item as? String {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "HeaderCell"), owner: self) as? NSTableCellView
            view?.textField?.stringValue = headerItem
        }
        else if let directory = item as? Directory {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "DataCell"), owner: self) as? NSTableCellView

            if item is PrivateDirectory {
                view?.imageView?.image = NSImage(named: NSImage.Name("NSFolderSmart"))
            }
            view?.textField?.stringValue = directory.name ?? "NO NAME"
        }
        else if let remote = item as? Remote {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "DataCell"), owner: self) as? NSTableCellView
            view?.imageView?.image = NSImage(named: NSImage.Name("NSNetwork"))
            view?.textField?.stringValue = remote.name ?? "NO NAME"
        }
        
        return view
    }
    
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        if let selectedItem = self.directoriesOutlineView.item(atRow: self.directoriesOutlineView.selectedRow) {
            if let tabViewController = (self.parent as? NSSplitViewController)?.splitViewItems[1].viewController as? NSTabViewController {
                if let doc = selectedItem as? Directory {
                    tabViewController.tabView.selectTabViewItem(at: 0)
                }
                else if let doc = selectedItem as? Remote {
                    tabViewController.tabView.selectTabViewItem(at: 1)
                }
            }
            if let doc = selectedItem as? Directory {
                // NotificationCenter.default.post(name: .documentSelectionDidChange, object: self.documentsOutlineView.selectedRow)
            }
        }
    }
    
    
    
    // MARK: - Table View
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return DataController.shared.operationQueue.operations.count
    }
    
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: OperationCellView?
        
        view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "OperationCellView"), owner: self) as? OperationCellView
        
        if let laodOperation = DataController.shared.operationQueue.operations[row] as? LoadOperation {
            view?.textField?.stringValue = "Load files: \(laodOperation.currentIndex)/\(laodOperation.numberOfFiles)"
            view?.progressBar.doubleValue = Double(laodOperation.percents)
        }
        
        return view
    }
}
