//
//  AppDelegate.swift
//  MagiX
//
//  Created by Rafael Warnault on 22/04/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift


extension Notification.Name {
    static let valueFormatChanged = Notification.Name(rawValue: "valueFormatChanged")
}

public enum ValueFormat:Int {
    case Original   = 1
    case Formatted  = 2
    case Hexa       = 3
}


@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet weak var valueFormatMenu: NSMenu!
    
    override init() {
        // Default preferences
        UserDefaults.standard.register(defaults: [
            "LocalAET": "MAGIX",
            "LocalPort": DicomConstants.dicomDefaultPort,
            "ServerEnabled": true,
            "MaxPDU": 16384,
            "ValueFormat": ValueFormat.Formatted.rawValue,
        ])
        
        UserDefaults.standard.synchronize()
    }


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // setup the Logger
        Logger.setPreferences()
        Logger.info("Application did finish launching")
        Logger.info("IMPORTANT : \(Logger.getFileDestination())")
        
        // select the default value format
        for mi in valueFormatMenu.items {
            let savedFormat = UserDefaults.standard.integer(forKey: "ValueFormat")
            
            if mi.tag == savedFormat {
                mi.state = .on
            } else {
                mi.state = .off
            }
        }

        // start a local server instance
        if UserDefaults.standard.bool(forKey: "ServerEnabled") {
            ServerController.shared.startServer()
        }
    }
        

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        Logger.info("APPLICATION WILL TERMINATE")
        Logger.info("IMPORTANT : \(Logger.getFileDestination())")
    }
    
    
    
    @IBAction func loadDicomFiles(_ sender: Any) {
        let openPanel = NSOpenPanel()
        
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        openPanel.begin { (result) -> Void in
            if result == NSApplication.ModalResponse.OK {
                DataController.shared.load(fileURLs: openPanel.urls)
            }
        }
    }
    
    @IBAction func valueFormatChanged(_ sender: AnyObject?) {
        if let menuItem = sender as? NSMenuItem {
            for mi in menuItem.menu!.items {
                mi.state = .off
            }
            
            menuItem.state = .on
            UserDefaults.standard.set(menuItem.tag, forKey: "ValueFormat")
            UserDefaults.standard.synchronize()
            
            print("post notif")
            NotificationCenter.default.post(name: .valueFormatChanged, object: nil)
        }
    }
    
    
    func application(_ application: NSApplication, open urls: [URL]) {
        DataController.shared.load(fileURLs: urls)
    }
    
    
    

    // MARK: - Core Data stack

    lazy var persistentContainer: NSPersistentContainer = {
        /*
         The persistent container for the application. This implementation
         creates and returns a container, having loaded the store for the
         application to it. This property is optional since there are legitimate
         error conditions that could cause the creation of the store to fail.
        */
        let container = NSPersistentContainer(name: "MagiX")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                 
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error)")
            }
        })
        return container
    }()

    // MARK: - Core Data Saving and Undo support

    @IBAction func saveAction(_ sender: AnyObject?) {
        // Performs the save action for the application, which is to send the save: message to the application's managed object context. Any encountered errors are presented to the user.
        let context = persistentContainer.viewContext

        if !context.commitEditing() {
            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing before saving")
        }
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Customize this code block to include application-specific recovery steps.
                let nserror = error as NSError
                NSApplication.shared.presentError(nserror)
            }
        }
    }

    func windowWillReturnUndoManager(window: NSWindow) -> UndoManager? {
        // Returns the NSUndoManager for the application. In this case, the manager returned is that of the managed object context for the application.
        return persistentContainer.viewContext.undoManager
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Save changes in the application's managed object context before the application terminates.
        let context = persistentContainer.viewContext
        
        if !context.commitEditing() {
            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing to terminate")
            return .terminateCancel
        }
        
        if !context.hasChanges {
            return .terminateNow
        }
        
        do {
            try context.save()
        } catch {
            let nserror = error as NSError

            // Customize this code block to include application-specific recovery steps.
            let result = sender.presentError(nserror)
            if (result) {
                return .terminateCancel
            }
            
            let question = NSLocalizedString("Could not save changes while quitting. Quit anyway?", comment: "Quit without saves error question message")
            let info = NSLocalizedString("Quitting now will lose any changes you have made since the last successful save", comment: "Quit without saves error question info");
            let quitButton = NSLocalizedString("Quit anyway", comment: "Quit anyway button title")
            let cancelButton = NSLocalizedString("Cancel", comment: "Cancel button title")
            let alert = NSAlert()
            alert.messageText = question
            alert.informativeText = info
            alert.addButton(withTitle: quitButton)
            alert.addButton(withTitle: cancelButton)
            
            let answer = alert.runModal()
            if answer == .alertSecondButtonReturn {
                return .terminateCancel
            }
        }
        // If we got here, it is time to quit.
        return .terminateNow
    }


}

