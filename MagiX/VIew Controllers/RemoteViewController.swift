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
                    let dataset = DataSet()
                    dataset.prefixHeader = false
                    _ = dataset.set(value: "STUDY", forTagName: "QueryRetrieveLevel")
                    _ = dataset.set(value: "", forTagName: "PatientID")
                    _ = dataset.set(value: "", forTagName: "ModalitiesInStudy")
                    _ = dataset.set(value: "", forTagName: "StudyDescription")
                    _ = dataset.set(value: "", forTagName: "StudyDate")
                    
                    print(dataset)
                    
                    client.find(dataset) { (okEcho, receivedMessage, errorEcho) in
                        if okEcho {
                            print("Query OK")
                        } else {
                            if let alert = errorEcho?.alert() {
                                alert.runModal()
                            }
                        }
                    }
                } else {
                    print("Connection error: \(error)")
                }
            }
        }
    }
}
