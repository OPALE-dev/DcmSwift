//
//  Document.swift
//  DicomiX
//
//  Created by Rafael Warnault on 24/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
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
        // Add your subclass-specific initialization here.
    }
    

    override class var autosavesInPlace: Bool {
        return true
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
    
    
    
    override var autosavingIsImplicitlyCancellable: Bool {
        return true
    }
    
    
    
    override func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, originalContentsURL absoluteOriginalContentsURL: URL?) throws {
        if !self.dicomFile.write(atPath: url.path) {
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }

        NotificationCenter.default.post(name: .didUpdateDcmElement, object: nil)
        NotificationCenter.default.post(name: .documentsDidChange, object: nil)
    }
    
    

    override func read(from url: URL, ofType typeName: String) throws {
        if let df = DicomFile(forPath: url.path) {
            self.dicomFile = df
        } else {
             throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
    }
}

