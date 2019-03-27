//
//  DocumentsViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 19/03/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa



extension Notification.Name {
    static let documentSelectionDidChange = Notification.Name(rawValue: "documentSelectionDidChange")
}



class NoIndentOutlineView: NSOutlineView {
    override var indentationPerLevel: CGFloat {
        get {
            return 0;
        }
        set {
            // Do nothing
        }
    }
    
    override var intercellSpacing: NSSize {
        get {
            return NSZeroSize;
        }
        set {
            // Do nothing
        }
    }
}

class DocumentsViewController: NSViewController, NSOutlineViewDelegate, NSOutlineViewDataSource, NSMenuDelegate {
    @IBOutlet weak var documentsOutlineView: NSOutlineView!
    @IBOutlet weak var documentsMenu: NSMenu!
    
    public var categories:[String] = ["OPEN DOCUMENTS", "RECENT DOCUMENTS"]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        // Observe
        NotificationCenter.default.addObserver(self, selector: #selector(documentsDidChange(_:)), name: .documentsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(documentSelectionDidChange(_:)), name: .documentSelectionDidChange, object: nil)
        
        // Expand root items
        self.documentsOutlineView.expandItem(self.documentsOutlineView.item(atRow: 1), expandChildren: false)
        self.documentsOutlineView.expandItem(self.documentsOutlineView.item(atRow: 0), expandChildren: false)
        
        // Double click
        self.documentsOutlineView.target = self
        self.documentsOutlineView.doubleAction = #selector(doubleClick(_:))
    }
    
    
    @objc func doubleClick(_:Any) {
        if let selectedItem = self.documentsOutlineView.item(atRow: self.documentsOutlineView.selectedRow) {
            if let doc = selectedItem as? URL {
                NSDocumentController.shared.openDocument(withContentsOf: doc, display: true) { (doc, flag, error) in
                    
                }
            }
        }
    }
    
    
    // MARK: - Notifications
    
    @objc func documentsDidChange(_ notification: Notification) {
        self.documentsOutlineView.reloadData()
    }
    
    @objc func documentSelectionDidChange(_ notification: Notification) {
        if let index = notification.object as? Int {
            self.documentsOutlineView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            self.documentsOutlineView.becomeFirstResponder()
        }
    }
    
    
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu == self.documentsMenu {
            menu.removeAllItems()
            print("menuNeedsUpdate")
            //menu.addItem(withTitle: "Reveal in Finder", action: nil, keyEquivalent: nil)
        }
    }
    
    
    
    
    // MARK: - NSOutlineView
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return categories.count
        } else {
            if (item as! String) == categories.first {
                return NSDocumentController.shared.documents.count
            } else if (item as! String) == categories.last {
                return NSDocumentController.shared.recentDocumentURLs.count
            }
        }
        return 0
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let headerItem = item as? String {
            if headerItem == categories.first {
                return NSDocumentController.shared.documents[index]
            }
            else if headerItem == categories.last {
                return NSDocumentController.shared.recentDocumentURLs[index]
            }
        }
        
        return categories[index]
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
        else if let doc = item as? NSDocument {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "DataCell"), owner: self) as? NSTableCellView
            
            view?.textField?.stringValue = doc.displayName
        }
        else if let url = item as? NSURL {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "DataCell"), owner: self) as? NSTableCellView
            
            view?.textField?.stringValue = url.lastPathComponent ?? "No name"
        }
        
        return view
    }
    
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        if let selectedItem = self.documentsOutlineView.item(atRow: self.documentsOutlineView.selectedRow) {
            if let doc = selectedItem as? NSDocument {
                NSDocumentController.shared.openDocument(withContentsOf: doc.fileURL!, display: true) { (doc, flag, error) in
                    NotificationCenter.default.post(name: .documentSelectionDidChange, object: self.documentsOutlineView.selectedRow)
                }
            }
        }
    }
}
