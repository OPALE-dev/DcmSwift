//
//  ElementViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 25/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Cocoa
import DcmSwift

extension Notification.Name {
    static let didUpdateDcmElement = Notification.Name("didUpdateDcmElement")
}

class ElementViewController: NSViewController, NSControlTextEditingDelegate {
    @IBOutlet weak var nameTextField: NSTextField!
    @IBOutlet weak var tagGroupTextField: NSTextField!
    @IBOutlet weak var tagElementTextField: NSTextField!
    @IBOutlet weak var startOffsetTextField: NSTextField!
    @IBOutlet weak var representationTextField: NSTextField!
    
    @IBOutlet weak var vrTextField: NSTextField!
    @IBOutlet weak var lengthTextField: NSTextField!
    @IBOutlet weak var dataOffsetTextField: NSTextField!
    @IBOutlet weak var valueTextField: NSTextField!
    @IBOutlet weak var editableTextField: NSTextField!
    
    private var element:DataElement!
    
    
    // MARK: - Constructors
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        
        
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.addObservers()
    }
    
    
    

    // MARK: - NSViewController methods
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        self.updateUI()
    }
    
    
    
    
    // MARK: - NSControlTextEditingDelegate
    func controlTextDidEndEditing(_ obj: Notification) {
        if self.element != nil {
            if let textField = obj.object as? NSTextField {
                if (self.element.dataset?.set(value: textField.stringValue, toElement: self.element))! {
                    
                    if let document = representedObject as? DicomDocument {
                        document.updateChangeCount(NSDocument.ChangeType.changeDone)
                    }
                    
                    NotificationCenter.default.post(name: .didUpdateDcmElement, object: nil)
                } else {
                    // show error
                }
            }
        }
    }
    
    
    
    // MARK: - Privates
    private func updateUI() {
        if self.isViewLoaded {
            if self.element != nil {
                self.nameTextField.stringValue              = self.element.name
                self.tagGroupTextField.stringValue          = self.element.group
                self.tagElementTextField.stringValue        = self.element.element
                self.startOffsetTextField.stringValue       = "\(self.element.startOffset)"
                self.representationTextField.stringValue    = "\(self.element.vrMethod)"
                
                self.vrTextField.stringValue                = "\(self.element.vr)"
                self.lengthTextField.stringValue            = "\(self.element.length)"
                self.dataOffsetTextField.stringValue        = "\(self.element.dataOffset)"
                
                if let data = self.element.value as? Data {
                    self.valueTextField.objectValue = data.toHexString()
                }
                else {
                    self.valueTextField.objectValue = self.element.value
                }
                
                self.valueTextField.isEditable  = self.element.isEditable
                self.editableTextField.isHidden = self.element.isEditable
            }
        }
    }
    

    
    
    // MARK: - Notifications handling
    private func addObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector( ElementViewController.elementSelectionDidChange(_:) ) ,
            name: .elementSelectionDidChange,
            object: nil)
    }
    
    
    
    @objc private func elementSelectionDidChange(_ notification:Notification) {
        if let array = notification.object as? Array<Any> {
            let el  = array[0] as? DataElement
            let doc = array[1] as? DicomDocument
            
            if doc == self.representedObject as? DicomDocument {
                self.element = el
                self.updateUI()
            }
        }
    }
}
