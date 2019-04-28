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
    
    var studies:[Study] = []
    
     // MARK: - View Controller

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        
        self.dataOutlineView.expandItem(self.dataOutlineView.item(atRow: 0), expandChildren: false)
        
        NotificationCenter.default.addObserver(self, selector: #selector(didLoadData(n:)), name: .didLoadData, object: nil)
        
        self.studies = DataController.shared.fetchStudies()
        self.dataOutlineView.reloadData()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    
    
    
    // MARK: - Notification
    
    @objc func didLoadData(n:Notification) {
        print("didLoadData")
        self.studies = DataController.shared.fetchStudies()
        self.dataOutlineView.reloadData()
    }

    
    
    @IBAction func remove(_ sender: Any) {
        let selectedItem = self.dataOutlineView.item(atRow: self.dataOutlineView.selectedRow)
        
        if let s = selectedItem as? Study {
            DataController.shared.removeStudy(s)
        }
    }
    
    

    
    // MARK: - NSOutlineView
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return self.studies.count
        } else {
            if let study = item as? Study {
                return study.series?.count ?? 0
            }
        }
        return 0
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let study = item as? Study {
            let soretd  = study.series?.sortedArray(using: [NSSortDescriptor(key: "seriesNumber", ascending: true)]) as! [Serie] as NSArray
            return soretd[index]
        }
        
        return self.studies[index]
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return ((item as? Serie) != nil) ? false : true
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        return (item as? Serie) != nil ? false : true
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return true
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        var view: NSTableCellView?
        
        let df = DateFormatter()
        df.dateFormat = "yyyy/MM/dd HH:mm:ss"
        
        if tableColumn?.title == "Name" {
            if let study = item as? Study {
                view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                view?.textField?.stringValue = study.patient?.patientName ?? "NO NAME"
            }
            else if let serie = item as? Serie {
                view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                view?.textField?.stringValue = String(serie.seriesNumber)
            }
        }
        else if tableColumn?.title == "Description" {
            if let study = item as? Study {
                view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                view?.textField?.stringValue = study.studyDescription ?? ""
            }
            else if let serie = item as? Serie {
                view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                view?.textField?.stringValue = serie.seriesDescription ?? ""
            }
        }
        else if tableColumn?.title == "Modality" {
            if let study = item as? Study {
                view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                view?.textField?.stringValue = (study.series?.allObjects.first as? Serie)?.modality ?? ""
            }
            else if let serie = item as? Serie {
                view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                view?.textField?.stringValue = serie.modality ?? ""
            }
        }
        else if tableColumn?.title == "ID" {
            if let study = item as? Study {
                view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                view?.textField?.stringValue = study.patient?.patientID ?? ""
            }
            else if let serie = item as? Serie {
                view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                view?.textField?.stringValue = serie.study?.studyID ?? ""
            }
        }
        else if tableColumn?.title == "Date" {
            if let study = item as? Study {
                view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                if let d = study.studyDate {
                    view?.textField?.stringValue = df.string(from: d)
                } else {
                    view?.textField?.stringValue = ""
                }
            }
            else if let serie = item as? Serie {
                view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                if let d = serie.seriesDate {
                    view?.textField?.stringValue = df.string(from: d)
                } else {
                    view?.textField?.stringValue = ""
                }
            }
        }
        else if tableColumn?.title == "#" {
            if let study = item as? Study {
                view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                view?.textField?.stringValue = "\(study.series?.count ?? 0)/\(String(study.numberOfInstances))"
            }
            else if let serie = item as? Serie {
                view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                view?.textField?.stringValue = String(serie.numberOfInstances)
            }
        }
        
        return view
    }
    
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        if let selectedItem = self.dataOutlineView.item(atRow: self.dataOutlineView.selectedRow) as? NSManagedObject {
            NotificationCenter.default.post(name: .dataSelectionDidChange, object: selectedItem)
        }
    }
}

