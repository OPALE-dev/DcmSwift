//
//  PictureViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 31/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Cocoa
import DcmSwift


class PictureViewController: NSViewController {
    public var dicomFile:DicomFile!
    
    @IBOutlet weak var imageView: NSImageView!
    
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
                    self.dicomFile = document.dicomFile
                    self.updateUI()
                }
            }
        }
    }
    
    
    
    private func updateUI() {
        self.imageView.wantsLayer = true
        self.imageView.layer?.backgroundColor = NSColor.black.cgColor
        
        self.photometricTextField.stringValue        = self.dicomFile.dataset.string(forTag: "PhotometricInterpretation") ?? ""
        self.samplesTextField.stringValue            = "\(self.dicomFile.dataset.integer16(forTag: "SamplesPerPixel"))"
        self.imageSizeTextField.stringValue          = "\(self.dicomFile.dataset.integer16(forTag: "Rows")) x \(self.dicomFile.dataset.integer16(forTag: "Columns"))"
        self.framesTextField.stringValue             = self.dicomFile.dataset.string(forTag: "NumberOfFrames")  ?? ""
        
        if let dicomImage = self.dicomFile.dicomImage {
            self.imageView.image = dicomImage.image()
        }
    }
}
