
//
//  AddElementController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 12/11/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift

class AddElementController: NSViewController, NSComboBoxDelegate, NSComboBoxDataSource {
    @IBOutlet var comboBox: NSComboBox!
    @IBOutlet var groupTextField: NSTextField!
    @IBOutlet var elementTextField: NSTextField!
    @IBOutlet var valueTextField: NSTextField!
    @IBOutlet var errorTextField: NSTextField!
    
    var keys: [String] = []
    var filteredKeys: [String] = []
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // cache keys into array first
        self.keys = Array(DicomSpec.shared.tagsByName.keys).sorted(by: <)
        self.filteredKeys = Array(self.keys) // yeah
        
        self.comboBox.target = self
        self.comboBox.action = #selector(AddElementController.selectValue)
    }
    
    
    @IBAction func add(_ sender: Any) {
        if self.comboBox.stringValue.count == 0 {
            self.errorTextField.stringValue = "You must select a Tag"
            return
        }
        
        if self.groupTextField.stringValue.count != 4 {
            self.errorTextField.stringValue = "Invalid Tag group"
            return
        }
        
        if self.elementTextField.stringValue.count != 4 {
            self.errorTextField.stringValue = "Invalid Tag element"
            return
        }
        
        if self.valueTextField.stringValue.count == 0 {
            self.errorTextField.stringValue = "Value cannot be empty"
            return
        }
        
        self.errorTextField.stringValue = ""
        
        if let dataset = (self.representedObject as? DicomDocument)?.dicomFile.dataset {
            self.dismiss(self)
            
            if dataset.hasElement(forTagName: self.comboBox.stringValue) {
                let alert = NSAlert()
                alert.messageText = "Tag already exists"
                alert.informativeText = "An element with tag \(self.comboBox.stringValue) already exists in the dataset. Do you want to update it?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Update")
                alert.addButton(withTitle: "Cancel")
                
                alert.beginSheetModal(for: NSApp.keyWindow!) { (modalResponse: NSApplication.ModalResponse) in
                   if(modalResponse == .alertFirstButtonReturn){
                        _ = dataset.set(value: self.valueTextField.stringValue, forTagName: self.comboBox.stringValue)
                        NotificationCenter.default.post(name: .didUpdateDcmElement, object: nil)
                        
                        if let document = self.representedObject as? DicomDocument {
                            document.updateChangeCount(NSDocument.ChangeType.changeDone)
                        }
                        
                    }
                }
                
//                if alert.runModal() == .alertFirstButtonReturn {
//                    _ = dataset.set(value: self.valueTextField.stringValue, forTagName: self.comboBox.stringValue)
//                    NotificationCenter.default.post(name: .didUpdateDcmElement, object: nil)
//
//                    if let document = representedObject as? DicomDocument {
//                        document.updateChangeCount(NSDocument.ChangeType.changeDone)
//                    }
//
//                }
                
            } else {
                _ = dataset.set(value: self.valueTextField.stringValue, forTagName: self.comboBox.stringValue)
                NotificationCenter.default.post(name: .didUpdateDcmElement, object: nil)
                
                if let document = representedObject as? DicomDocument {
                    document.updateChangeCount(NSDocument.ChangeType.changeDone)
                }
            }
        }
    }
    
    
    
    @objc func selectValue() {
        if let tag = DicomSpec.shared.dataTag(forName: self.comboBox.stringValue) {
            self.groupTextField.stringValue = tag.group
            self.elementTextField.stringValue = tag.element
        }
    }
    
    
    
    func numberOfItems(in comboBox: NSComboBox) -> Int {
        return self.filteredKeys.count
    }
    
    
    
    func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
        return self.filteredKeys[index]
    }
    
    
    
    func comboBox(_ comboBox: NSComboBox, indexOfItemWithStringValue string: String) -> Int {
        return self.filteredKeys.firstIndex(of: string) ?? 0
    }
    
    
    
    func comboBox(_ comboBox: NSComboBox, completedString string: String) -> String? {
        for dataString in self.keys{
            // substring must have less characters then stings to search
            if string.count < dataString.count{
                // only use first part of the strings in the list with length of the search string
                let statePartialStr = dataString.lowercased()[dataString.lowercased().startIndex..<dataString.lowercased().index(dataString.lowercased().startIndex, offsetBy: string.count)]
                if statePartialStr.range(of: string.lowercased()) != nil {
                    return dataString
                }
            }
        }
        return ""
    }
    

    
    func filterDataArray(_ string: String) {
        self.filteredKeys = []

        if (string.isEmpty || string == "" || string == " ") {
            self.filteredKeys = Array(self.keys)

        } else {
            for (i, _) in self.keys.enumerated() {
                let searchNameRange = (self.keys[i] as NSString).range(of: string, options: NSString.CompareOptions.caseInsensitive)
                if searchNameRange.location != NSNotFound {
                    self.filteredKeys.append(self.keys[i])
                }
            }
            if self.filteredKeys.count == 0 {
                self.filteredKeys = Array(self.keys)
            }
        }
        print(self.filteredKeys)

        self.comboBox.reloadData()
    }

    
    
    func comboBoxSelectionDidChange(_ notification: Notification) {
        self.selectValue()
    }
}
