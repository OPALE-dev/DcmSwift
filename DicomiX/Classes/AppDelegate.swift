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
        // Default preferences
        UserDefaults.standard.register(defaults: [
            "LocalAET": "DICOMIX",
            "MaxPDU": 16384
        ])
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    
    func applicationDidBecomeActive(_ notification: Notification) {
        if DocumentController.shared.documents.count == 0 {
            NSDocumentController.shared.openDocument(self)
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }
    
    
    
    @IBAction func showLogs(_ sender: Any) {
        let appName = Bundle.main.infoDictionary![kCFBundleNameKey as String] as! String
        let caches = (NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.cachesDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)[0])
        let logFile = [caches, appName, "swiftybeaver.log"]
        
        NSWorkspace.shared.openFile(logFile.joined(separator: "/"))
    }
}

