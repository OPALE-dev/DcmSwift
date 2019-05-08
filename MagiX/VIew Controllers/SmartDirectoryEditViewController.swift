//
//  FolderEditViewController.swift
//  MagiX
//
//  Created by Rafael Warnault on 08/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa

class SmartDirectoryEditViewController: NSViewController {
    @IBOutlet weak var nameTextField: NSTextField!
    
    public var directory:SmartDirectory?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        self.loadFields()
    }
 
    
    @IBAction func ok(_ sender: Any) {
        if !self.validateFields() {
            NSSound.beep()
            return
        }
        
        if let r = self.directory {
            r.name = self.nameTextField.stringValue

        }
        else {
            let newDir = SmartDirectory(context: DataController.shared.context)
            newDir.name = self.nameTextField.stringValue
            
            self.directory = newDir
        }
        
        DataController.shared.save()
        
        NotificationCenter.default.post(name: .didUpdateRemote, object: self.directory)
        
        self.dismiss(sender)
    }
    
    
    
    private func loadFields() {
        if let d = self.directory {
            self.nameTextField.stringValue = d.name ?? ""
        }
    }
    
    private func validateFields() -> Bool {
        if self.nameTextField.stringValue.count == 0 {
            return false
        }
        return true
    }
}
