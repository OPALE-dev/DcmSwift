//
//  SendViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 25/03/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Cocoa
import DcmSwift

class SendViewController: NSViewController {
    @IBOutlet var entitiesPopUpButton: NSPopUpButton!
    @IBOutlet var syntaxesPopUpButton: NSPopUpButton!
    
    private var entities:[DicomEntity] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        self.loadEntities()
    }
    
    
    @IBAction func send(_ sender: Any) {
        let localAET    = UserDefaults.standard.string(forKey: "LocalAET")!
        let callingAE   = DicomEntity(title: localAET, hostname: "127.0.0.1", port: 11112)
        let calledAE    = self.entities[self.entitiesPopUpButton.indexOfSelectedItem]
        let client      = DicomClient(localEntity: callingAE, remoteEntity: calledAE)
        
        
        
        client.connect { (ok, error) in
            if ok {
//                if let document = NSDocumentController.shared.currentDocument as? DicomDocument {
//                    client.store([document.dicomFile!], completion: { (ok, error) in
//                        print(ok)
//                        print(error)
//                    })
//                }
            }
        }
        
        self.dismiss(self)
    }
    
    
    
    
    private func loadEntitiesMenu() {
        self.entitiesPopUpButton.menu?.removeAllItems()
        
        for e in self.entities {
            self.entitiesPopUpButton.addItem(withTitle: e.fullname())
        }
    }
    
    
    private func loadEntities() {
        if let data = UserDefaults.standard.object(forKey: "DicomEntities") as? Data {
            let decoder = PropertyListDecoder()
            if let savedEntities = try? decoder.decode(Array<DicomEntity>.self, from: data) {
                self.entities = savedEntities
                self.loadEntitiesMenu()
            }
        }
    }
}
