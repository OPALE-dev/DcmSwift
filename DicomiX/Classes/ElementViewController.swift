//
//  ElementViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 25/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift

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
    override func controlTextDidEndEditing(_ obj: Notification) {
        if self.element != nil {
            
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
                
                
                if  self.element.vr == .OB ||
                    self.element.vr == .OW ||
                    self.element.vr == .SQ ||
                    self.element.vr == .UN ||
                    self.element.vr == .OW {
                    self.valueTextField.isEditable = false
                }
                else {
                    self.valueTextField.isEditable = true
                }
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
        if let el = notification.object as? DataElement {
            self.element = el
            self.updateUI()
        }
    }
}
