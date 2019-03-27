//
//  ViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 24/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift


extension Notification.Name {
    static let elementSelectionDidChange = Notification.Name(rawValue: "elementSelectionDidChange")
}


class DatasetViewController: NSViewController, NSOutlineViewDelegate, NSOutlineViewDataSource {
    @IBOutlet weak var datasetOutlineView: NSOutlineView!
    
    public var dataset:DataSet!
    public var dicomFile:DicomFile!
    public var searchedElements:[DataElement] = []
    
    private var showHexData:Bool = false
    
    // MARK: - NSViewController methods
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        self.datasetOutlineView.delegate    = self
        self.datasetOutlineView.dataSource  = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(didUpdateDcmElement(_:)), name: .didUpdateDcmElement, object: nil)
    }
    

    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
            if let document:DicomDocument = representedObject as? DicomDocument {
                if document.dicomFile != nil {
                    self.dataset    = document.dicomFile.dataset
                    self.dicomFile  = document.dicomFile
                    
                    self.datasetOutlineView.reloadData()
                    
                    // Expand root items
                    self.datasetOutlineView.expandItem(self.datasetOutlineView.item(atRow: 1), expandChildren: true)
                    self.datasetOutlineView.expandItem(self.datasetOutlineView.item(atRow: 0), expandChildren: true)
                }
            }
        }
    }
    
    
    
    
    // MARK: - Notifications
    @objc func didUpdateDcmElement(_ notification: Notification) {
        let selectedRow = self.datasetOutlineView.selectedRow
        if let selectedItem = self.datasetOutlineView.item(atRow: selectedRow) {
            self.datasetOutlineView.reloadData()
            
            NotificationCenter.default.post(name: .elementSelectionDidChange, object: [selectedItem, self.representedObject!])
            
            self.datasetOutlineView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
        }
    }
    
    
    
    // MARK: - IBAction
    @IBAction func expandAll(_ sender: Any) {
        self.datasetOutlineView.expandItem("Meta Information Header", expandChildren: true)
        self.datasetOutlineView.expandItem("Dataset", expandChildren: true)
        
        for item in self.dataset.metaInformationHeaderElements {
            self.datasetOutlineView.expandItem(item, expandChildren: true)
        }
        
        for item in self.dataset.datasetElements {
            self.datasetOutlineView.expandItem(item, expandChildren: true)
        }
    }
    
    
    @IBAction func collapseAll(_ sender: Any) {
        for item in self.dataset.metaInformationHeaderElements {
            self.datasetOutlineView.collapseItem(item, collapseChildren: true)
        }
        
        for item in self.dataset.datasetElements {
            self.datasetOutlineView.collapseItem(item, collapseChildren: true)
        }
    }
    
    
    @IBAction func removeElement(_ sender: Any) {
        if let selectedElement = self.datasetOutlineView.item(atRow: self.datasetOutlineView.selectedRow) as? DataElement {
            let _ = self.dataset.remove(dataElement: selectedElement)
            self.datasetOutlineView.reloadData()
            
            if let document = representedObject as? DicomDocument {
                document.updateChangeCount(NSDocument.ChangeType.changeDone)
            }
        }
    }
    
    
    
    @IBAction func toggleHexData(_ sender: Any) {
        if let button = sender as? NSButton {
            self.showHexData = button.state == NSControl.StateValue.on ? true : false
            self.datasetOutlineView.reloadData()
        }
        
    }
    
    
    
    @IBAction func search(_ sender: Any) {
        if let searchField = sender as? NSSearchField {
            let searchString = searchField.stringValue.lowercased()
            
            if searchString.count > 0 {
                if let document = representedObject as? DicomDocument {
                    for element in document.dicomFile.dataset.allElements {
                        if element.name.lowercased().contains(searchString) {
                            if !searchedElements.contains(where: { $0 === element }) {
                                searchedElements.append(element)
                            }
                        }
                        if element.tagCode().lowercased().contains(searchString) {
                            if !searchedElements.contains(where: { $0 === element }) {
                                searchedElements.append(element)
                            }
                        }
                        if let string = element.value as? String {
                            if string.lowercased().contains(searchString) {
                                if !searchedElements.contains(where: { $0 === element }) {
                                    searchedElements.append(element)
                                }
                            }
                        }
                        self.datasetOutlineView.reloadData()
                        let row = self.datasetOutlineView.row(forItem: searchedElements.first)
                        self.datasetOutlineView.scrollRowToVisible(row)
                    }
                }
            }  else {
                searchedElements.removeAll()
                self.datasetOutlineView.reloadData()
            }
        }
    }
    
    
    


    
    // MARK: - NSOutlineViewDataSource methods
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if self.dataset == nil {
            return 0
        }
        
        if let headerItem = item as? String {
            if headerItem == "Meta Information Header" {
                return self.dataset.metaInformationHeaderElements.count
            }
            else {
                return self.dataset.datasetElements.count
            }
        }
        else if let sequence = item as? DataSequence {
            return sequence.items.count
        }
        else if let item = item as? DataItem {
            return item.elements.count
        }
        else if let item = item as? DataElement {
            if item.isMultiple {
                return item.values.count
            }
        }
        
        return 2
    }
    
        
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let headerItem = item as? String {
            if headerItem == "Meta Information Header" {
                return self.dataset.metaInformationHeaderElements[index]
            }
            else {
                return self.dataset.datasetElements[index]
            }
        }
        else if let sequence = item as? DataSequence {
            return sequence.items[index]
        }
        else if let item = item as? DataItem {
            return item.elements[index]
        }
        
        if let element = item as? DataElement {
            if element.isMultiple {
                return element.values[index]
            }
        }
        
        return index == 0 ? "Meta Information Header" : "Dataset"
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let _ = item as? String {
            return true
        }
        else if let sequence = item as? DataSequence {
            return sequence.items.count > 0
        }
        else if let item = item as? DataItem {
            return item.elements.count > 0
        }
        else if let item = item as? DataElement {
            if item.isMultiple {
                return true
            }
        }
        
        return false
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        var view: NSTableCellView?
        
        if let headerItem = item as? String {
            if (tableColumn?.identifier)!.rawValue == "ElementName" {
                view                                    = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                let attrs:[NSAttributedString.Key:Any]   = [NSAttributedString.Key(rawValue: NSAttributedString.Key.font.rawValue) : NSFont.boldSystemFont(ofSize: 12)]
                let attrString:NSAttributedString       = NSMutableAttributedString(string: headerItem, attributes:attrs)
                view?.textField?.attributedStringValue  = attrString
                
            }
        } else if let element = item as? DataElement {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
            
            view?.textField?.stringValue = ""
            
            if (tableColumn?.identifier)!.rawValue == "StartOffset" {
                view?.textField?.stringValue = "\(element.startOffset)"
            }
            else if (tableColumn?.identifier)!.rawValue == "TagCode" {
                view?.textField?.stringValue = "\(element.group),\(element.element)"
            }
            else if (tableColumn?.identifier)!.rawValue == "ElementName" {
                view?.textField?.stringValue = element.name
            }
            else if (tableColumn?.identifier)!.rawValue == "VR" {
                view?.textField?.stringValue = "\(element.vr)"
            }
            else if (tableColumn?.identifier)!.rawValue == "Length" {
                view?.textField?.stringValue = "\(element.length)"
            }
            else if (tableColumn?.identifier)!.rawValue == "DataOffset" {
                view?.textField?.stringValue = "\(element.dataOffset)"
            }
            else if (tableColumn?.identifier)!.rawValue == "ElementValue" {
                if !(element.value is Data) {
                    if !self.showHexData {
                        view?.textField?.objectValue = element.value
                    } else {
                        if element.data != nil {
                            let end = element.data.count >= 50 ? 50 : element.data.count-1
                            view?.textField?.objectValue = element.data[0..<end]
                        }
                    }
                }
               
            } else {
                view?.textField?.stringValue = ""
            }
            
            if searchedElements.count > 0 {
                if searchedElements.contains(where: { $0 === element }) {
                    view?.textField?.alphaValue = 1.0
                } else {
                    view?.textField?.alphaValue = 0.5
                }
            } else {
                view?.textField?.alphaValue = 1.0
            }
        }
        else if let value = item as? DataValue {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
            
            if (tableColumn?.identifier)!.rawValue == "ElementName" {
                view?.textField?.stringValue = "Value \(value.index+1)"
            }
            else if (tableColumn?.identifier)!.rawValue == "ElementValue" {
                view?.textField?.stringValue = value.value
                
            } else {
                view?.textField?.stringValue = ""
            }
        }
        
        else {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
            view?.textField?.stringValue = ""
        }
        
        return view
    }
    
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        if let selectedItem = self.datasetOutlineView.item(atRow: self.datasetOutlineView.selectedRow) {
            NotificationCenter.default.post(name: .elementSelectionDidChange, object: [selectedItem, self.representedObject!])
        }
    }
}

