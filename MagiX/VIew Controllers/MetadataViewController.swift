//
//  MetadataViewController.swift
//  MagiX
//
//  Created by Rafael Warnault on 27/04/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift


extension Notification.Name {
    static let elementSelectionDidChange = Notification.Name(rawValue: "elementSelectionDidChange")
}


class MetadataViewController: NSViewController, NSOutlineViewDelegate, NSOutlineViewDataSource {
    @IBOutlet weak var datasetOutlineView: NSOutlineView!
    
    var dataset:DataSet!
    var searchedElements:[DataElement] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        NotificationCenter.default.addObserver(self, selector: #selector(dataSelectionDidChange(n:)), name: .dataSelectionDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(valueFormatChanged(n:)), name: .valueFormatChanged, object: nil)
    }
    
    
    @objc func valueFormatChanged(n:Notification) {
        self.datasetOutlineView.reloadData()
    }
    
    
    @objc func dataSelectionDidChange(n:Notification) {
        if let managedObject = n.object as? NSManagedObject {
            var instance:Instance!
            
            if let patient = managedObject as? Patient {
                if let st = patient.studies?.allObjects.first as? Study {
                    if let se = st.series?.allObjects.first as? Serie {
                        if let i = se.instances?.allObjects.first as? Instance {
                            instance = i
                        }
                    }
                }
            }
            else if let study = managedObject as? Study {
                if let se = study.series?.allObjects.first as? Serie {
                    if let i = se.instances?.allObjects.first as? Instance {
                        instance = i
                    }
                }
            }
            else if let serie = managedObject as? Serie {
                if let i = serie.instances?.allObjects.first as? Instance {
                    instance = i
                }
            }
            
            if instance != nil {
                if let dicomFile = DicomFile(forPath: instance.filePath!) {
                    if let ds = dicomFile.dataset {
                        self.dataset = ds
                        self.datasetOutlineView.reloadData()
                        
                        self.datasetOutlineView.expandItem(self.datasetOutlineView.item(atRow: 1), expandChildren: false)
                        self.datasetOutlineView.expandItem(self.datasetOutlineView.item(atRow: 0), expandChildren: false)
                    }
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
            
            if (tableColumn?.identifier)!.rawValue == "StartOffset" {
                view?.textField?.stringValue = "\(element.startOffset-4)"
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
                    let valueFormat = UserDefaults.standard.integer(forKey: "ValueFormat")
                    
                    if valueFormat == ValueFormat.Original.rawValue {
                        view?.textField?.objectValue = element.value
                    }
                    else  if valueFormat == ValueFormat.Formatted.rawValue {
                        if element.vr == .DA || element.vr == .TM || element.vr == .DT {
                            if let date = element.value as? Date {
                                view?.textField?.objectValue = date.format(accordingTo: element.vr)
                            }
                        }
                        else if element.vr == .UI {
                            view?.textField?.objectValue = DicomSpec.shared.nameForUID(withUID: element.value as! String, append: true)
                        }
                        else {
                            view?.textField?.objectValue = element.value
                        }
                    }
                    else  if valueFormat == ValueFormat.Hexa.rawValue {
                        if element.data != nil {
                            let end = element.data.count >= 50 ? 50 : element.data.count-1
                            view?.textField?.stringValue = element.data[0..<end].toHex().separate(every: 2, with: " ").uppercased()
                        }
                    }
                } else {
                    if element.data != nil {
                        let end = element.data.count >= 50 ? 50 : element.data.count-1
                        view?.textField?.stringValue = element.data[0..<end].toHex().separate(every: 2, with: " ").uppercased()
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
//        if let selectedItem = self.datasetOutlineView.item(atRow: self.datasetOutlineView.selectedRow) {
//            NotificationCenter.default.post(name: .elementSelectionDidChange, object: [selectedItem, self.representedObject!])
//        }
    }
}
