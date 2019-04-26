//
//  ExportViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 07/11/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Cocoa


class ExportViewController: NSViewController {
    @IBOutlet var myStackView: NSStackView!
    
    var oldSelection: Int = 0
    var newSelection: Int = 0
    var buttons: [NSButton]?
    var tabViewDelegate: NSTabViewController?
    
    
    
    // MARK: - View methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        buttons = (myStackView.arrangedSubviews as! [NSButton])
    }
    
    
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        // Once on load
        tabViewDelegate = segue.destinationController as?  NSTabViewController
    }
    
    
    
    // MARK: - IBAction
    
    @IBAction func selectedButton(_ sender: NSButton) {
        newSelection = sender.tag
        tabViewDelegate?.selectedTabViewItemIndex = newSelection
        
        buttons![oldSelection].state = .off
        sender.state = .on
        
        oldSelection = newSelection
    }
    
    
    @IBAction func export(_ sender: Any) {
        let savePanel = NSSavePanel()
        
        if let doc = self.representedObject as? DicomDocument {
            savePanel.isExtensionHidden = false
            savePanel.nameFieldStringValue = doc.displayName
            
            self.dismiss(sender)
            
            if oldSelection == 0 {
                savePanel.allowedFileTypes = ["dcm"]
                
            } else if oldSelection == 1 {
                savePanel.allowedFileTypes = ["xml"]
                
            } else if oldSelection == 2 {
                savePanel.allowedFileTypes = ["json"]
            }
            
            guard let window = NSApp.keyWindow else { return }
            savePanel.beginSheetModal(for: window) { (resp) in
                if resp.rawValue == NSFileHandlingPanelOKButton {
                    if let exportedFileURL = savePanel.url {
                        //print(exportedFileURL)
                        
                        if self.oldSelection == 0 {
                            if let ts = self.selectTransferSyntax() {
                                if !doc.dicomFile.write(atPath: exportedFileURL.path,
                                                        transferSyntax: ts) {
                                    print("Write error \(exportedFileURL.path)")
                                }
                            }
                        } else if self.oldSelection == 1 {
                            let xml = doc.dicomFile.dataset.toXML()
                            do {
                                try xml.data(using: .utf8)?.write(to: exportedFileURL)
                            } catch let e {
                                print(e)
                            }
                            
                        } else if self.oldSelection == 2 {
                            let json = doc.dicomFile.dataset.toJSON()
                            do {
                                try json.data(using: .utf8)?.write(to: exportedFileURL)
                            } catch let e {
                                print(e)
                            }
                        }
                    }
                }
            }
        }
    }
    
    
    
    // MARK: - Private
    
    private func selectTransferSyntax() -> String? {
        if let c = tabViewDelegate?.tabView.tabViewItems[0].viewController as? ExportDICOMViewController {
            return c.syntaxesPopUpButton.selectedItem?.representedObject as? String
        }
        
        if let doc = self.representedObject as? DicomDocument {
            return doc.dicomFile.dataset.transferSyntax
        }
        
        return nil
    }
}
