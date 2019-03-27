//
//  DicomPrefViewController.swift
//  DicomiX
//
//  Created by Rafael Warnault on 25/03/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa

class DicomPrefViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.preferredContentSize = NSMakeSize(self.view.frame.size.width, self.view.frame.size.height)
    }
    
}
