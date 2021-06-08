//
//  ConsoleViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 25/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Cocoa
import DcmSwift

class ConsoleViewController: NSViewController, NSTextViewDelegate {
    @IBOutlet var textView: NSTextView!
    @IBOutlet var littleIntegerTextField: NSTextField!
    @IBOutlet var bigIntegerTextField: NSTextField!
    @IBOutlet var byteOffsetTextField: NSTextField!
    @IBOutlet var bytesNumberTextField: NSTextField!
    public var dicomFile:DicomFile!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(elementSelectionDidChange(_:)),
            name: .elementSelectionDidChange,
            object: nil)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentDidSave(_:)),
            name: .documentDidSave,
            object: nil)
        
        self.textView.delegate = self
    }
    
    
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
            self.reloadTextView()
        }
    }
    
    
    private func reloadTextView() {
        self.textView.string = ""
        if let document:DicomDocument = self.representedObject as? DicomDocument {
            DispatchQueue.global(qos: .background).async {
                if document.dicomFile != nil {
                    self.dicomFile  = document.dicomFile
                    
                    if let data = self.getFileData(file: self.dicomFile) {
                        data.withUnsafeBytes { (u8Ptr: UnsafePointer<UInt8>) in
                            let mutRawPointer = UnsafeMutableRawPointer(mutating: u8Ptr)
                            let uploadChunkSize = 1024
                            let totalSize = data.count
                            var offset = 0
                            
                            while offset < totalSize {
                                
                                let chunkSize = offset + uploadChunkSize > totalSize ? totalSize - offset : uploadChunkSize
                                let chunk = Data(bytesNoCopy: mutRawPointer+offset, count: chunkSize, deallocator: Data.Deallocator.none)
                                
                                let hexString = chunk.toHex().separate(every: 2, with: " ").uppercased()
                                let attrs: [NSAttributedString.Key: Any] = [
                                    .font : NSFont(name: "Courier", size: 14) as Any,
                                    .foregroundColor: NSColor.labelColor
                                ]
                                DispatchQueue.main.async {
                                    self.textView.textStorage?.append(NSAttributedString(string: hexString, attributes: attrs))
                                    self.textView.textStorage?.append(NSAttributedString(string: " ", attributes: attrs))
                                }
                                
                                offset += chunkSize
                            }
                        }
                    }
                }
            }
        }
    }
    
    
    private func getFileData(file:DicomFile) -> Data? {
        if file.isCorrupted() {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: file.filepath)) {
                return data
            } else {
                return nil
            }
        }
        return self.dicomFile.dataset.toData()
    }
    
    
    @objc func documentDidSave(_ notification:Notification) {
        if let selfDoc = representedObject as? DicomDocument {
            if let notifDoc = notification.object as? DicomDocument {
                if selfDoc == notifDoc {
                    self.reloadTextView()
                }
            }
        }
    }
        
    
    @objc func elementSelectionDidChange(_ notification:Notification) {
        if let params = notification.object as? [Any] {
            if let element = params[0] as? DataElement {
                if let doc = params[1] as? DicomDocument {
                    if let document:DicomDocument = representedObject as? DicomDocument {
                        if doc == document {
                            let start = element.startOffset - 4
                            let length = 8 + element.length
                            let range = NSRange(location: start*3, length: length*3)
                            
                            self.byteOffsetTextField.stringValue = "Offset \(start)"
                            
                            self.textView.setSelectedRange(range)
                            self.textView.scrollRangeToVisible(range)
                        }
                    }
                }
            }
        }
    }
    
    
    func textViewDidChangeSelection(_ notification: Notification) {
        let selectedRange = self.textView.selectedRange()
        
        if selectedRange.length > 1 {
            self.byteOffsetTextField.stringValue = "Offset \(selectedRange.location/3)"
            
            let selectedText = self.textView.attributedSubstring(forProposedRange: selectedRange, actualRange: nil)

            if let string = selectedText?.string.replacingOccurrences(of: " ", with: "") {
                if string.count % 2 == 0 && selectedRange.length <= 2048 {
                    let d = string.hexData()!
                    
                    if string.count == 2 {
                        let count = d.count / MemoryLayout<UInt8>.size
                        let u = d.withUnsafeBytes { (p: UnsafePointer<UInt8>) -> [UInt8] in
                            let bp = UnsafeBufferPointer(start: p, count: count)
                            return bp.map { UInt8(littleEndian: $0) }
                        }
                        if let intVal = u.first {
                            self.littleIntegerTextField.stringValue = "\(intVal)"
                            self.bigIntegerTextField.stringValue = "\(intVal.bigEndian)"
                        }
                    }
                    else if string.count == 4 {
                        let count = d.count / MemoryLayout<UInt16>.size
                        let u = d.withUnsafeBytes { (p: UnsafePointer<UInt16>) -> [UInt16] in
                            let bp = UnsafeBufferPointer(start: p, count: count)
                            return bp.map { UInt16(littleEndian: $0) }
                        }
                        
                        if let intVal = u.first {
                            self.littleIntegerTextField.stringValue = "\(intVal)"
                            self.bigIntegerTextField.stringValue = "\(intVal.bigEndian)"
                        }
                    }
                    else if string.count == 8 {
                        let count = d.count / MemoryLayout<UInt32>.size
                        let u = d.withUnsafeBytes { (p: UnsafePointer<UInt32>) -> [UInt32] in
                            let bp = UnsafeBufferPointer(start: p, count: count)
                            return bp.map { UInt32(littleEndian: $0) }
                        }
                        if let intVal = u.first {
                            self.littleIntegerTextField.stringValue = "\(intVal)"
                            self.bigIntegerTextField.stringValue = "\(intVal.bigEndian)"
                        }
                    }
                    else {
                        self.littleIntegerTextField.stringValue = "<NaN>"
                        self.bigIntegerTextField.stringValue = "<NaN>"
                    }
                }
                else {
                    self.littleIntegerTextField.stringValue = "<NaN>"
                    self.bigIntegerTextField.stringValue = "<NaN>"
                }
                
                self.bytesNumberTextField.stringValue = "\(string.count/2) bytes"
            }
        } else {
            self.littleIntegerTextField.stringValue = "<NaN>"
            self.bigIntegerTextField.stringValue = "<NaN>"
            self.bytesNumberTextField.stringValue = "0 byte"
        }
    }
    

 
    
    @IBAction func clear(_ sender: Any) {
        self.textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
    }
}
