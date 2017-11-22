//
//  PictureViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 31/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift


class PictureViewController: NSViewController {
    public var dicomFile:DicomFile!
    
    
    @IBOutlet weak var photometricTextField: NSTextField!
    @IBOutlet weak var samplesTextField: NSTextField!
    @IBOutlet weak var imageSizeTextField: NSTextField!
    @IBOutlet weak var framesTextField: NSTextField!
    
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    
    
    override var representedObject: Any? {
        didSet {
            if let document:DicomDocument = representedObject as? DicomDocument {
                if document.dicomFile != nil {
                    Swift.print("representedObject")
                    self.dicomFile = document.dicomFile
                    self.updateUI()
                }
            }
        }
    }
    
    
    
    private func updateUI() {
        self.photometricTextField.stringValue        = self.dicomFile.dataset.string(forTag: "PhotometricInterpretation") ?? ""
        self.samplesTextField.stringValue            = "\(self.dicomFile.dataset.integer16(forTag: "SamplesPerPixel"))"
        self.imageSizeTextField.stringValue          = "\(self.dicomFile.dataset.integer16(forTag: "Rows")) x \(self.dicomFile.dataset.integer16(forTag: "Columns"))"
        self.framesTextField.stringValue             = self.dicomFile.dataset.string(forTag: "NumberOfFrames")  ?? ""
    }
}
