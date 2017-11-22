//
//  SplitViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 25/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Cocoa


extension NSTextView {
    func appendString(string:String) {
        self.string += string
        self.scrollRangeToVisible(NSRange(location:self.string.count, length: 0))
    }
}



class MainSplitViewController: NSSplitViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
            if let _ = representedObject as? DicomDocument {
                for vc in self.childViewControllers {
                    vc.representedObject = representedObject
                }
            }
        }
    }
    
    
    
    
    
    // MARK: - IBAction
    @IBAction func expandAll(_ sender: Any) {
        if let vc:ConsoleSplitViewController = self.childViewControllers[0] as? ConsoleSplitViewController {
            vc.expandAll(sender)
        }
    }
    
    
    @IBAction func collapseAll(_ sender: Any) {
        if let vc:ConsoleSplitViewController = self.childViewControllers[0] as? ConsoleSplitViewController {
            vc.collapseAll(sender)
        }
    }
    
    
    @IBAction func removeElement(_ sender: Any) {
        if let vc:ConsoleSplitViewController = self.childViewControllers[0] as? ConsoleSplitViewController {
            vc.removeElement(sender)
        }
    }
    
    
    @IBAction func toggleHexData(_ sender: Any) {
        if let vc:ConsoleSplitViewController = self.childViewControllers[0] as? ConsoleSplitViewController {
            vc.toggleHexData(sender)
        }
    }
    
    
    @IBAction func validate(_ sender: Any) {
        let dciodvfyUrl = Bundle.main.url(forResource: "dciodvfy", withExtension: "")
        
        if let document = self.representedObject as? DicomDocument {
            let commandResult = self.execCommand(command: dciodvfyUrl!.path, args: [document.dicomFile.filepath])
            
            if let vc:ConsoleSplitViewController = self.childViewControllers[0] as? ConsoleSplitViewController {
                if let consoleViewController = vc.childViewControllers[1] as? ConsoleViewController {
                    let lines = commandResult.split(separator: "\n")

                    for line in lines {
                        let attrString = attributedStringFor(line: String(line + "\n"))
                        let range = NSRange(location:commandResult.count, length: 0)
                        
                        consoleViewController.textView.textStorage?.append(attrString)
                        consoleViewController.textView.scrollRangeToVisible(range)
                    }
                }
            }
        }
    }
    
    
  
    @IBAction func search(_ sender: Any) {
        if let vc:ConsoleSplitViewController = self.childViewControllers[0] as? ConsoleSplitViewController {
            vc.search(sender)
        }
    }
    
    
    
    
    
    
    @IBAction func showInspector(_ sender: Any) {
        let rightView = self.splitView.subviews[1]
        
        if self.splitView.isSubviewCollapsed(rightView) {
            self.splitView.setPosition(self.view.frame.size.width-200, ofDividerAt: 0)
            rightView.isHidden = false
        }
    }
    
    @IBAction func hideInspector(_ sender: Any) {
        let rightView = self.splitView.subviews[1]
        
        if !self.splitView.isSubviewCollapsed(rightView) {
            self.splitView.setPosition(self.view.frame.size.width, ofDividerAt: 0)
            rightView.isHidden = true
        }
    }
    
    
    
    @IBAction func showConsole(_ sender: Any) {
        if let vc:ConsoleSplitViewController = self.childViewControllers[0] as? ConsoleSplitViewController {
            vc.showConsole(sender)
        }
    }
    
    @IBAction func hideConsole(_ sender: Any) {
        if let vc:ConsoleSplitViewController = self.childViewControllers[0] as? ConsoleSplitViewController {
            vc.hideConsole(sender)
        }
    }
    
    
    
    // MARK: - Privates
    func attributedStringFor(line:String) -> NSAttributedString {
        var attrs:[NSAttributedStringKey : Any] = [
            NSAttributedStringKey.font: NSFont(name: "Courier New", size: 12.0) as Any
        ]

        if line.hasPrefix("Error") {
            attrs[NSAttributedStringKey.foregroundColor] = NSColor.red
        }
        else if line.hasPrefix("Warning") {
            attrs[NSAttributedStringKey.foregroundColor] = NSColor.orange
        }
        else {
            attrs[NSAttributedStringKey.foregroundColor] = NSColor.black
        }
        
        return NSAttributedString(string: line, attributes: attrs)
    }
    
    

    func execCommand(command: String, args: [String]) -> String {
        if !command.hasPrefix("/") {
            let commandFull = execCommand(command: "/usr/bin/which", args: [command]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return execCommand(command: commandFull, args: args)
        } else {
            let proc = Process()
            proc.launchPath = command
            proc.arguments = args
            
            let pipe = Pipe()
            proc.standardError = pipe
            proc.standardOutput = pipe
            proc.launch()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: data, encoding: String.Encoding.utf8)!
            Swift.print(output)
            
            if output.characters.count > 0 {
                //remove newline character.
                let lastIndex = output.index(before: output.endIndex)
                return String(output[output.startIndex ..< lastIndex])
            }
            
            return output
        }
    }
    
    
    
    override func splitViewDidResizeSubviews(_ notification: Notification) {
        let rightView = self.splitView.subviews[1]
        
        if self.splitView.isSubviewCollapsed(rightView) {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "inspectorSplitViewCollapsed"), object: self)
        } else {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "inspectorSplitViewExpanded"), object: self)
        }
    }
}
