//
//  RemoteEditViewController.swift
//  MagiX
//
//  Created by Rafael Warnault on 29/04/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift


extension Notification.Name {
    static let didUpdateRemote = Notification.Name(rawValue: "didUpdateRemote")
}

class RemoteEditViewController: NSViewController {
    @IBOutlet weak var nameTextField: NSTextField!
    @IBOutlet weak var aeTitleTextField: NSTextField!
    @IBOutlet weak var hostnameTextField: NSTextField!
    @IBOutlet weak var portTextField: NSTextField!
    @IBOutlet weak var echoTextField: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    @IBAction func echo(_ sender: Any) {
        if !self.validateFields() {
            NSSound.beep()
            return
        }
        
        let localAET    = UserDefaults.standard.string(forKey: "LocalAET")!
        let callingAE   = DicomEntity(title: localAET, hostname: "127.0.0.1", port: 11112)
        let calledAE    = DicomEntity(title: self.aeTitleTextField.stringValue, hostname: self.hostnameTextField.stringValue, port: Int(self.portTextField!.intValue))
        let client      = DicomClient(localEntity: callingAE, remoteEntity: calledAE)
        
        client.connect { (ok, error) in
            if ok {
                client.echo { (ok, error) in
                    if ok {
                        self.setEcho(text: "Echo succeeded", color: NSColor.darkGray)
                    } else {
                        self.setEcho(text: error!, color: NSColor.red)
                    }
                }
            } else {
                self.setEcho(text: error!, color: NSColor.red)
            }
        }
    }
    
    @IBAction func ok(_ sender: Any) {
        if !self.validateFields() {
            NSSound.beep()
            return
        }
        
        let newRemote = Remote(context: DataController.shared.context)
        newRemote.name = self.nameTextField.stringValue
        newRemote.title = self.aeTitleTextField.stringValue
        newRemote.hostname = self.hostnameTextField.stringValue
        newRemote.port = self.portTextField.intValue
        
        DataController.shared.save()
        
        NotificationCenter.default.post(name: .didUpdateRemote, object: newRemote)
        
        self.dismiss(sender)
    }
    
    
    private func setEcho(text:String, color:NSColor) {
        self.echoTextField.stringValue = text
        self.echoTextField.textColor = color
    }
    
    
    private func validateFields() -> Bool {
        if self.nameTextField.stringValue.count == 0 {
            return false
        }
        if self.aeTitleTextField.stringValue.count == 0 {
            return false
        }
        if self.hostnameTextField.stringValue.count == 0 {
            return false
        }
        if self.portTextField.stringValue.count == 0 {
            // TODO: check integer type and network port range here
            return false
        }
        
        return true
    }
}
