//
//  AppDelegate.swift
//  DicomiX
//
//  Created by Rafael Warnault on 24/10/2017.
//  Copyright © 2017 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: {
            if NSDocumentController.shared.currentDocument == nil {
                NSDocumentController.shared.openDocument(self)
            }
        })
        
        
        // Default preferences
        UserDefaults.standard.register(defaults: [
            "LocalAET": "DICOMIX",
            "MaxPDU": 16384
        ])
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }
    
//    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
//        return true
//    }
    
    
//    func application(_ sender: NSApplication, openFiles filenames: [String]) {
//        Swift.print(filenames)
//    }
}

