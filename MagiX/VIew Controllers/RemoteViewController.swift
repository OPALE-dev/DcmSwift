//
//  RemoteViewController.swift
//  MagiX
//
//  Created by Rafael Warnault on 30/04/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift

class RemoteViewController: NSViewController {
    @IBOutlet weak var queryTableView: NSTableView!
    
    var remote:Remote!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
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
        let localAET = UserDefaults.standard.string(forKey: "LocalAET")!
        let callingAE = DicomEntity(title: localAET, hostname: "127.0.0.1", port: 11112)
        if let calledAE = self.remote.dicomEntity {
            let client = DicomClient(localEntity: callingAE, remoteEntity: calledAE)
            
            client.connect { (ok, error) in
                if ok {
//                    let dataset = DataSet()
//                    _ = dataset.set(value: "cd*", forTagName: "PatientName")
//                    
                    client.echo() { (ok, error) in
                        if ok {
                            print("Query OK")
                        } else {
                            print("Query error")
                        }
                    }
                } else {
                    print("Connection error")
                }
            }
        }
    }
}
