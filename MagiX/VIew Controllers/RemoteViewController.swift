//
//  RemoteViewController.swift
//  MagiX
//
//  Created by Rafael Warnault on 30/04/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift

class RemoteViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
    @IBOutlet weak var queryTableView: NSTableView!
    
    var queryOperation:FindOperation?
    
    var studies:[Any] = []
    var remote:Remote!
    var queryDataset:DataSet = DataSet()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let studyDate = DateRange(startDate: Date(),
                                  endDate: nil,
                                  rangeType: .afterDate).description
        
        queryDataset.prefixHeader = false
        
        _ = queryDataset.set(value: "STUDY", forTagName: "QueryRetrieveLevel")
        _ = queryDataset.set(value: "", forTagName: "PatientID")
        _ = queryDataset.set(value: "", forTagName: "PatientName")
        _ = queryDataset.set(value: "", forTagName: "PatientBirthDate")
        _ = queryDataset.set(value: "", forTagName: "AccessionNumber")
        _ = queryDataset.set(value: "", forTagName: "NumberOfStudyRelatedInstances")
        _ = queryDataset.set(value: "", forTagName: "ModalitiesInStudy")
        _ = queryDataset.set(value: "", forTagName: "StudyDescription")
        _ = queryDataset.set(value: "", forTagName: "StudyInstanceUID")
        _ = queryDataset.set(value: studyDate, forTagName: "StudyDate")
        _ = queryDataset.set(value: "", forTagName: "StudyTime")

        NotificationCenter.default.addObserver(self, selector: #selector(queryDidChange(n:)), name: .queryDidChange, object: nil)
    }
    
    
    
    @objc func queryDidChange(n:Notification) {
        if let d = n.object as? DataSet {
            self.queryDataset = d
            
            print(self.queryDataset)
            
            query()
        }
    }
    
    
    override var representedObject: Any? {
        didSet {
            if let r = representedObject as? Remote {
                self.remote = r
                
                self.query()
            }
        }
    }
    
    
    
    private func query() {
        if self.queryOperation == nil {
            self.queryOperation = FindOperation()
            
            self.queryOperation?.addExecutionBlock {
                let localAET = UserDefaults.standard.string(forKey: "LocalAET")!
                let callingAE = DicomEntity(title: localAET, hostname: "127.0.0.1", port: 11112)
                
                if let calledAE = self.remote.dicomEntity {
                    let client = DicomClient(localEntity: callingAE, remoteEntity: calledAE)
                    
                    client.connect { (ok, error) in
                        if ok {
                            let dataset = self.queryDataset
                            
                            client.find(dataset) { (okFind, receivedMessage, findError) in
                                if okFind {
                                    if let findRSP = receivedMessage as? CFindRSP {
                                        self.studies = findRSP.queryResults
                                        
                                        DispatchQueue.main.async {
                                            self.queryTableView.reloadData()
                                        }
                                    }
                                } else {
                                    if let alert = findError?.alert() {
                                        DispatchQueue.main.async {
                                            self.studies = []
                                            self.queryTableView.reloadData()
                                            alert.runModal()
                                        }
                                    }
                                }
                            }
                        } else {
                            if let alert = error?.alert() {
                                DispatchQueue.main.async {
                                    self.studies = []
                                    self.queryTableView.reloadData()
                                    alert.runModal()
                                }
                            }
                        }
                    }
                }
            }
            
            self.queryOperation?.completionBlock = {
                DispatchQueue.main.async {
                    OperationsController.shared.stopObserveOperation(self.queryOperation)
                    self.queryOperation = nil
                }
            }
        }
        
        if let operation = self.queryOperation {
            if operation.isExecuting {
                print("Already running")
            }
            else {
                OperationsController.shared.addOperation(operation)
            }
        }
    }
    
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.studies.count
    }
    
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: NSTableCellView?
        
        let df = DateFormatter()
        df.dateFormat = "yyyy/MM/dd HH:mm:ss"
        
        if let study = self.studies[row] as? [String:[String:Any]] {
            if tableColumn?.title == "Name" {
                view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                if let name = study["00100010"] {
                    view?.textField?.stringValue = name["value"] as! String
                }
            }
            else if tableColumn?.title == "ID" {
                view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                if let name = study["00100020"] {
                    view?.textField?.stringValue = name["value"] as! String
                }
            }
            else if tableColumn?.title == "Birthdate" {
                view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                if let name = study["00100030"] {
                    view?.textField?.stringValue = name["value"] as! String
                }
            }
            else if tableColumn?.title == "Description" {
                view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                if let name = study["00081030"] {
                    view?.textField?.stringValue = name["value"] as! String
                }
            }
            else if tableColumn?.title == "Modalities" {
                view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                if let name = study["00080061"] {
                    view?.textField?.stringValue = name["value"] as! String
                }
            }
            else if tableColumn?.title == "Date" {
                view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                if let name = study["00080020"] {
                    view?.textField?.stringValue = name["value"] as! String
                }
            }
            else if tableColumn?.title == "Accession" {
                view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                if let name = study["00080050"] {
                    view?.textField?.stringValue = name["value"] as! String
                }
            }
            else if tableColumn?.title == "#" {
                view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
                if let name = study["00201208"] {
                    view?.textField?.stringValue = name["value"] as! String
                }
            }
        }
        
        return view
    }

}
