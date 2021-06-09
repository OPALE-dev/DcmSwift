//
//  AppDelegate.swift
//  DicomiX
//
//  Created by Rafael Warnault on 24/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Cocoa
import DcmSwift

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Logger.setDestinations([Logger.Output.Stdout, Logger.Output.File], filePath: "dicomix.log")

        // Default preferences
        UserDefaults.standard.register(defaults: [
            "LocalAET": "DICOMIX",
            "MaxPDU": 16384,
            "AllowDICOMEditing": false,
            "SidebarExpanded": true
        ])
        
        DocumentController.canOpenUntitledDocument = true
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    
    func applicationDidBecomeActive(_ notification: Notification) {
        if NSApp.windows.count == 0 {
            NSDocumentController.shared.openDocument(self)
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }
    
    // MARK: - Actions
    @IBAction func showLogs(_ sender: Any) {
        let appName = Bundle.main.infoDictionary![kCFBundleNameKey as String] as! String
        let caches = (NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.cachesDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)[0])
        let logFile = [caches, appName, "Logger.log"]
        
        NSWorkspace.shared.openFile(logFile.joined(separator: "/"))
    }
}

