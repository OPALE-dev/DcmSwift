//
//  DicomPrefViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 25/03/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Cocoa
import DcmSwift

class EntitiesPrefViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
    @IBOutlet var entitiesTableView: NSTableView!
    @IBOutlet var echoTextField: NSTextField!
    
    private var entities:[DicomEntity] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.preferredContentSize = NSMakeSize(self.view.frame.size.width, self.view.frame.size.height)
        
        self.loadEntities()
    }
    
    
    
    @IBAction func addEntity(_ sender: Any) {
        let newEntity = DicomEntity(title: "NEWENTITY", hostname: "127.0.0.1", port: 11112)
        self.entities.append(newEntity)
        self.entitiesTableView.reloadData()
        self.saveEntities()
    }
    
    @IBAction func removeEntity(_ sender: Any) {
        if self.entitiesTableView.selectedRow != -1 {
            self.entities.remove(at: self.entitiesTableView.selectedRow)
            self.entitiesTableView.reloadData()
            self.saveEntities()
        }
    }
    
    @IBAction func echoEntity(_ sender: Any) {
//        if self.entitiesTableView.selectedRow != -1 {
//            let localAET    = UserDefaults.standard.string(forKey: "LocalAET")!
//            let callingAE   = DicomEntity(title: localAET, hostname: "127.0.0.1", port: 11112)
//            let calledAE    = self.entities[self.entitiesTableView.selectedRow]
//            let client      = DicomClient(localEntity: callingAE, remoteEntity: calledAE)
//            
//            client.connect { (ok, error) in
//                if ok {
//                    client.echo { (ok, error) in
//                        if ok {
//                            self.setEcho(text: "Echo succeeded", color: NSColor.darkGray)
//                        } else {
//                            self.setEcho(text: error!, color: NSColor.red)
//                        }
//                    }
//                } else {
//                    self.setEcho(text: error!, color: NSColor.red)
//                }
//            }
//        }
    }
    
    
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.entities.count
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        if (tableColumn?.identifier)!.rawValue == "AET" {
            return self.entities[row].title
            
        } else if (tableColumn?.identifier)!.rawValue == "Hostname" {
            return self.entities[row].hostname
            
        } else if (tableColumn?.identifier)!.rawValue == "Port" {
            return self.entities[row].port
            
        }
        return ""
    }
    
    
    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        if (tableColumn?.identifier)!.rawValue == "AET" {
            self.entities[row].title = object as! String
            
        } else if (tableColumn?.identifier)!.rawValue == "Hostname" {
            self.entities[row].hostname = object as! String
            
        } else if (tableColumn?.identifier)!.rawValue == "Port" {
            self.entities[row].port = Int(object as! String) ?? 11112
        }
        
        self.saveEntities()
    }
    
    
    
    private func setEcho(text:String, color:NSColor) {
        self.echoTextField.stringValue = text
        self.echoTextField.textColor = color
    }
    
    
    private func loadEntities() {
        if let data = UserDefaults.standard.object(forKey: "DicomEntities") as? Data {
            let decoder = PropertyListDecoder()
            if let savedEntities = try? decoder.decode(Array<DicomEntity>.self, from: data) {
                self.entities = savedEntities
            }
        }
    }
    
    private func saveEntities() {
        let encoder = PropertyListEncoder()
        if let encoded = try? encoder.encode(self.entities) {
            UserDefaults.standard.set(encoded, forKey: "DicomEntities")
        }
    }
}
