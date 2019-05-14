//
//  ViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 24/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Cocoa
import DcmSwift


extension Notification.Name {
    static let elementSelectionDidChange = Notification.Name(rawValue: "elementSelectionDidChange")
}


class DatasetViewController: NSViewController, NSOutlineViewDelegate, NSOutlineViewDataSource, NSMenuDelegate, NSTableViewDelegate, NSTableViewDataSource, NSSplitViewDelegate {
    @IBOutlet weak var splitView: NSSplitView!
    @IBOutlet weak var validationView: NSView!
    @IBOutlet weak var validationToggleButton: NSButton!
    @IBOutlet weak var validationTextField: NSTextField!
    @IBOutlet weak var severityPopUpButton: NSPopUpButton!
    
    @IBOutlet weak var datasetOutlineView: NSOutlineView!
    @IBOutlet weak var validationTableView: NSTableView!
    
    public var dataset:DataSet!
    public var dicomFile:DicomFile!
    public var searchedElements:[DataElement] = []
    
    public var validationResults:[ValidationResult] = []
    public var filteredValidationResults:[ValidationResult] = []
    
    private var showHexData:Bool = false
    private var nbError:Int = 0
    private var nbWarning:Int = 0
    
    // MARK: - NSViewController methods
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        self.datasetOutlineView.delegate    = self
        self.datasetOutlineView.dataSource  = self
        
        self.splitView.delegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(didUpdateDcmElement(_:)), name: .didUpdateDcmElement, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(documentDidSave(_:)), name: .documentDidSave, object: nil)
    }
    

    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
            if let document:DicomDocument = representedObject as? DicomDocument {
                if document.dicomFile != nil {
                    self.dataset    = document.dicomFile.dataset
                    self.dicomFile  = document.dicomFile
                    
                    self.datasetOutlineView.reloadData()
                    self.reloadValidation()
                    
                    if self.nbError == 0 && self.nbWarning == 0 {
                        self.hideValidation(self)
                    }
                    
                    // Expand root items
                    self.datasetOutlineView.expandItem(self.datasetOutlineView.item(atRow: 1), expandChildren: false)
                    self.datasetOutlineView.expandItem(self.datasetOutlineView.item(atRow: 0), expandChildren: false)
                }
            }
        }
    }
    
    
    
    
    // MARK: - Notifications
    @objc func documentDidSave(_ notification: Notification) {
        if let selfDoc = representedObject as? DicomDocument {
            if let notifDoc = notification.object as? DicomDocument {
                if selfDoc == notifDoc {
                    let url = URL(fileURLWithPath: selfDoc.dicomFile.filepath)
                    if let data = try? Data(contentsOf: url) {
                        _ = self.dataset.loadData(data)
                        self.datasetOutlineView.reloadData()
                    }
                }
            }
        }
    }
    
    @objc func didUpdateDcmElement(_ notification: Notification) {
        let selectedRow = self.datasetOutlineView.selectedRow
        
        self.datasetOutlineView.reloadData()
        
        if let selectedItem = self.datasetOutlineView.item(atRow: selectedRow) {
            NotificationCenter.default.post(name: .elementSelectionDidChange, object: [selectedItem, self.representedObject!])
            self.datasetOutlineView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
        }
    }
    
    
    
    // MARK: - NSMenu
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let selectedItem = self.datasetOutlineView.item(atRow: self.datasetOutlineView.clickedRow) {
            menu.removeAllItems()
            
            if selectedItem is DataElement {
                if selectedItem is DataSequence {
                    menu.addItem(withTitle: "Add Item", action: #selector(removeElement(_:)), keyEquivalent: "")
                    menu.addItem(NSMenuItem.separator())
                }
                
                if selectedItem is DataItem {
                    menu.addItem(withTitle: "Add Element", action: #selector(removeElement(_:)), keyEquivalent: "")
                    menu.addItem(NSMenuItem.separator())
                }
                menu.addItem(withTitle: "Remove Element", action: #selector(removeElement(_:)), keyEquivalent: "")
            }
            
        }
    }
    
    
    
    
    // MARK: - IBAction
    @IBAction func expandAll(_ sender: Any) {
        self.datasetOutlineView.expandItem("Prefix Header", expandChildren: true)
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
    
    
    @IBAction func toggleValidation(_ sender: Any) {
        let bottomView = self.splitView.subviews[1]
        
        if bottomView.frame.size.height == 0 {
            self.showValidation(sender)
        } else {
            self.hideValidation(sender)
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
    
    
    @IBAction func validate(_ sender: Any) {
        self.reloadValidation()
    }

    
    @IBAction func showValidation(_ sender: Any) {
        let bottomView = self.splitView.subviews[1]
        
        if bottomView.frame.size.height == 0 {
            self.splitView.setPosition(self.view.frame.size.height-200, ofDividerAt: 0)
            bottomView.isHidden = false
        }
    }
    
    @IBAction func hideValidation(_ sender: Any) {
        let bottomView = self.splitView.subviews[1]
        
        if bottomView.frame.size.height > 0 {
            self.splitView.setPosition(self.view.frame.size.height, ofDividerAt: 0)
            bottomView.isHidden = true
        }
    }
    
    @IBAction func severityChanged(_ sender: Any) {
        self.reloadValidation()
    }
    
    
    
    
    // MARK: - NSTableView
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.filteredValidationResults.count
    }
    
    
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: NSTableCellView?
        
        let result = self.filteredValidationResults[row]
        
        if (tableColumn?.identifier)!.rawValue == "Severity" {
            view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ResultIconCell"), owner: self) as? NSTableCellView
            
            if result.severity == ValidationResult.Severity.Notice {
                view?.imageView?.image = NSImage(named: NSImage.Name("NSStatusNone"))
                
            } else if result.severity == ValidationResult.Severity.Warning {
                view?.imageView?.image = NSImage(named: NSImage.Name("NSStatusPartiallyAvailable"))
                
            } else if result.severity == ValidationResult.Severity.Error {
                view?.imageView?.image = NSImage(named: NSImage.Name("NSStatusUnavailable"))
                
            } else if result.severity == ValidationResult.Severity.Fatal {
                view?.imageView?.image = NSImage(named: NSImage.Name("NSStatusUnavailable"))
            }
            
        } else if (tableColumn?.identifier)!.rawValue == "ElementName" {
            view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ResultElementCell"), owner: self) as? NSTableCellView
            
            if let e = result.object as? DataElement {
                view?.textField?.stringValue = "[\(e.group),\(e.element)] \(e.name)"
            }
            else if let f = result.object as? DicomFile {
                view?.textField?.stringValue = f.fileName()
            }
            
        } else if (tableColumn?.identifier)!.rawValue == "Message" {
            view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ResultMessageCell"), owner: self) as? NSTableCellView
            view?.textField?.stringValue = result.message
            
        } else {
            
        }
        
        return view
    }
    
    
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        if self.validationTableView.selectedRow != -1 {
            // expand all fisrt
            self.expandAll(self)
            
            // get selected validation item
            let result = self.filteredValidationResults[self.validationTableView.selectedRow]
            
            if let element = result.object as? DataElement {
                // translate to outline view selected row index
                let index = self.datasetOutlineView.row(forItem: element)
                
                if index != -1 {
                    self.datasetOutlineView.deselectAll(self)
                    self.datasetOutlineView.selectRowIndexes(IndexSet.init(integer: index), byExtendingSelection: true)
                    self.datasetOutlineView.scrollToVisible(self.datasetOutlineView.frameOfCell(atColumn: 0, row: index))
                }
            }
        }
    }
    

    
    // MARK: - NSOutlineView
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if self.dataset == nil {
            return 0
        }
        
        if let headerItem = item as? String {
            if headerItem == "Prefix Header" {
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
            if headerItem == "Prefix Header" {
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
        
        return index == 0 ? "Prefix Header" : "Dataset"
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
    
    /**
    */
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        var view: NSTableCellView?
        
        if let headerItem = item as? String {
            if (tableColumn?.identifier)!.rawValue == "ElementName" {
                view                                    = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                let attrs:[NSAttributedString.Key:Any]  = [NSAttributedString.Key(rawValue: NSAttributedString.Key.font.rawValue) : NSFont.boldSystemFont(ofSize: 12)]
                let attrString:NSAttributedString       = NSMutableAttributedString(string: headerItem, attributes:attrs)
                view?.textField?.attributedStringValue  = attrString
                
            }
        } else if let element = item as? DataElement {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
            
            view?.textField?.stringValue = ""

            let identifier = (tableColumn?.identifier)!.rawValue

            
            if identifier == "StartOffset" {
                view?.textField?.stringValue = "\(element.startOffset-4)"
            }
            else if identifier == "TagCode" {
                view?.textField?.stringValue = "\(element.group),\(element.element)"
            }
            else if identifier == "ElementName" {
                view?.textField?.stringValue = element.name
            }
            else if identifier == "VR" {
                view?.textField?.stringValue = "\(element.vr)"
            }
            else if identifier == "Length" {
                view?.textField?.stringValue = "\(element.length)"
            }
            else if identifier == "DataOffset" {
                view?.textField?.stringValue = "\(element.dataOffset)"
            }
            else if identifier == "ElementValue" {
                if !(element.value is Data) {
                    if !self.showHexData {
                        
                        if element.vr == .DA || element.vr == .TM || element.vr == .DT {
                            if let date = element.value as? Date {
                                view?.textField?.objectValue = date.format(accordingTo: element.vr)
                            }
                        } else {
                            view?.textField?.objectValue = element.value
                        }
                    } else {
                        if element.data != nil {
                            //view?.textField?.stringValue = element.data.toHex()
                            let end = element.data.count >= 50 ? 50 : element.data.count-1
                            view?.textField?.stringValue = element.data[0..<end].toHex().separate(every: 2, with: " ").uppercased()
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
    
    
    // MARK: - Split View

    func splitView(_ splitView: NSSplitView, additionalEffectiveRectOfDividerAt dividerIndex: Int) -> NSRect {
        let rect = NSRect(
            x: self.validationView.bounds.origin.x+120,
            y: self.splitView.subviews.first!.frame.size.height-(self.validationView.frame.size.height)-1,
            width: self.validationView.bounds.size.width-180,
            height: self.validationView.bounds.size.height
        )
        return rect
    }
    
    
    func splitViewDidResizeSubviews(_ notification: Notification) {
        let bottomView = self.splitView.subviews[1]
        
        if bottomView.frame.size.height == 0 {
            self.validationToggleButton.state = NSControl.StateValue.off
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "validationSplitViewCollapsed"), object: self)
        } else {
            self.validationToggleButton.state = NSControl.StateValue.on
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "validationSplitViewExpanded"), object: self)
        }
    }
    
    
    
    // MARK: - Private
    private func reloadValidation() {
        // reload validation results
        self.validationResults = self.dicomFile.validate()
        
        // filtered and sorted by severity
        self.filterResults()
        self.filteredValidationResults = self.filteredValidationResults.sorted()
        
        self.validationTableView.reloadData()
        self.updateValidationString()
    }
    
    
    private func filterResults() {
        self.filteredValidationResults = []
        
        if self.severityPopUpButton.selectedTag() != -1 {
            
            for r in self.validationResults {
                if r.severity.rawValue == self.severityPopUpButton.selectedTag() {
                    self.filteredValidationResults.append(r)
                }
            }
        } else {
            self.filteredValidationResults = self.validationResults
        }
    }
    
    
    
    private func updateValidationString() {
        var errorString = ""
        var warningString = ""
        
        self.nbError = 0
        self.nbWarning = 0
        
        for r in self.validationResults {
            if r.severity == .Error {
                self.nbError += 1
            }
            if r.severity == .Warning {
                self.nbWarning += 1
            }
        }
        
        errorString = "\(self.nbError) error(s)"
        warningString = "\(self.nbWarning) warning(s)"
        
        self.validationTextField.stringValue = "\(errorString), \(warningString)"
    }
}

