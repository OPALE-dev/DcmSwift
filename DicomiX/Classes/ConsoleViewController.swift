//
//  ConsoleViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 25/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Cocoa

class ConsoleViewController: NSViewController {
    @IBOutlet var textView: NSTextView!
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
 
    
    @IBAction func clear(_ sender: Any) {
        self.textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
    }
}
