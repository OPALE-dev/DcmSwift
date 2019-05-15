//
//  PreferencesTabViewController.swift
//  MagiX
//
//  Created by paul on 15/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa

class PreferencesTabViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.

        self.preferredContentSize = NSMakeSize(self.view.frame.size.width, self.view.frame.size.height)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        self.parent?.view.window?.title = self.title!
    }
    
}
