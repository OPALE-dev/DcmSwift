//
//  Document.swift
//  DicomiX
//
//  Created by Rafael Warnault on 24/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Cocoa
import DcmSwift


extension Notification.Name {
    static let documentsDidChange = Notification.Name(rawValue: "documentsDidChange")
}


class DicomDocument: NSDocument  {
    public var dicomFile:DicomFile!


    
    override init() {
        super.init()
    }
    
    
    override var isInViewingMode: Bool {
        if self.dicomFile.isCorrupted() {
            return true
        }
        return false
    }
    

    override class var autosavesInPlace: Bool {
        return false
    }
    
    override class var preservesVersions: Bool {
        return false
    }
    
    override var autosavingIsImplicitlyCancellable: Bool {
        return false
    }
    
    override var hasUnautosavedChanges: Bool {
        return false
    }
    
    override func makeWindowControllers() {
        // Returns the Storyboard that contains your Document window.
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        let windowController = storyboard.instantiateController(withIdentifier: "Document Window Controller") as! NSWindowController
        let vc:NSSplitViewController = windowController.contentViewController as! NSSplitViewController
        
        vc.representedObject = self
        
        self.addWindowController(windowController)
        
        NotificationCenter.default.post(name: .documentsDidChange, object: nil)
    }
    
    
    
    override func close() {
        super.close()
        
        NotificationCenter.default.post(name: .documentsDidChange, object: nil)
    }
    

    
    override func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, originalContentsURL absoluteOriginalContentsURL: URL?) throws {
        if !self.dicomFile.write(atPath: url.path) {
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
                
        NotificationCenter.default.post(name: .documentDidSave, object: self)
    }
    
    
    override func read(from url: URL, ofType typeName: String) throws {
        if let df = DicomFile(forPath: url.path) {
            self.dicomFile = df
            
            if self.dicomFile.isCorrupted() {
                let alert = NSAlert()
                alert.messageText = "Corrupted DICOM file"
                alert.informativeText = "This file is not a standard DICOM file, you will find more informations in the Validation panel.\nDo you want to open it anyway as read-only?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Read-Only")
                alert.addButton(withTitle: "Close")
                
                if(alert.runModal() != .alertFirstButtonReturn){
                    self.close()
                }
            }
        } else {
             throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
    }
    
    
    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        try super.revert(toContentsOf: url, ofType: typeName)
        
        NotificationCenter.default.post(name: .documentDidSave, object: self)
    }
}

