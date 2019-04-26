//
//  ViewController.swift
//  MagiX
//
//  Created by Rafael Warnault on 22/04/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa


extension Notification.Name {
    static let dataSelectionDidChange = Notification.Name(rawValue: "dataSelectionDidChange")
}



class DataViewController: NSViewController, NSOutlineViewDelegate, NSOutlineViewDataSource {
    @IBOutlet weak var dataOutlineView: NSOutlineView!
    
    var categories:[String] = ["DATABASE"]
    
    
     // MARK: - View Controller

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        
        self.dataOutlineView.expandItem(self.dataOutlineView.item(atRow: 0), expandChildren: false)
        
        NotificationCenter.default.addObserver(self, selector: #selector(didLoadData(n:)), name: .didLoadData, object: nil)
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    
    
    
    // MARK: - Notification
    
    @objc func didLoadData(n:Notification) {
        self.dataOutlineView.reloadData()
    }


    
    // MARK: - NSOutlineView
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return categories.count
        } else {
            if let cat = item as? String {
                if cat == categories.first {
                    return DataController.shared.fetchPatients().count
                }
            }
            else if let patient = item as? Patient {
                return patient.studies?.count ?? 0
            }
            else if let study = item as? Study {
                return study.series?.count ?? 0
            }
        }
        return 0
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let headerItem = item as? String {
            if headerItem == categories.first {
                return DataController.shared.fetchPatients()[index]
            }
        }
        else if let patient = item as? Patient {
            let soretd  = patient.studies?.sortedArray(using: [NSSortDescriptor(key: "studyDate", ascending: true)]) as! [Study] as NSArray
            return soretd[index]
        }
        else if let study = item as? Study {
            let soretd  = study.series?.sortedArray(using: [NSSortDescriptor(key: "seriesNumber", ascending: true)]) as! [Serie] as NSArray
            return soretd[index]
        }
        
        return categories[index]
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return ((item as? Serie) != nil) ? false : true
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        return ((item as? String) != nil || (item as? Serie) != nil) ? false : true
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
        else if let patient = item as? Patient {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "DataCell"), owner: self) as? NSTableCellView
            view?.textField?.stringValue = patient.patientID ?? "NO PATIENT ID"
        }
        else if let study = item as? Study {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "DataCell"), owner: self) as? NSTableCellView
            view?.textField?.stringValue = study.studyDescription ?? "UNKNOW STUDY"
        }
        else if let serie = item as? Serie {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "DataCell"), owner: self) as? NSTableCellView
            view?.textField?.stringValue = serie.seriesDescription ?? "UNKNOW SERIES"
        }
        
        return view
    }
    
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        if let selectedItem = self.dataOutlineView.item(atRow: self.dataOutlineView.selectedRow) as? NSManagedObject {
            NotificationCenter.default.post(name: .dataSelectionDidChange, object: selectedItem)
        }
    }
}

