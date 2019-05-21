//
//  GeneralPreferencesController.swift
//  MagiX
//
//  Created by paul on 16/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift

class AdvancedPreferencesController: NSViewController {

    /* Outlets */
    @IBOutlet weak var logLevel: NSPopUpButton!
    @IBOutlet weak var checkfileDestination: NSButton!
    @IBOutlet weak var buttonChooseFile: NSButton!
    @IBOutlet weak var checkConsoleDestination: NSButton!
    @IBOutlet weak var cleanLogPeriods: NSPopUpButton!
    @IBOutlet weak var fileField: NSTextField!



    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        if let filePath = Logger.getFileDestination() {
            fileField.stringValue = filePath
        }
    }

    /* Actions */
    @IBAction func logLevelChanged(_ sender: Any) {
        if let button = sender as? NSPopUpButton {
            if let level = Logger.LogLevel(rawValue: button.selectedTag()) {
                Logger.setMaxLevel(level)
            }
        }
    }

    @IBAction func fileDestinationChanged(_ sender: Any) {
        if let checkButton = sender as? NSButton {
            if checkButton.state == NSControl.StateValue.init(0) {
                Logger.removeDestination(Logger.Output.File)
            } else {
                Logger.addDestination(Logger.Output.File)
            }
        }
    }

    @IBAction func logsInConsoleChanged(_ sender: Any) {
        if let checkButton = sender as? NSButton {
            if checkButton.state == NSControl.StateValue.init(0) {
                Logger.removeDestination(Logger.Output.Stdout)
            } else {
                Logger.addDestination(Logger.Output.Stdout)
            }
        }
    }

    @IBAction func chooseFile(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.canChooseFiles = false

        let i = openPanel.runModal()
        if(i.rawValue == NSApplication.ModalResponse.OK.rawValue) {

            if let path = openPanel.url?.path {
                if Logger.setFileDestination(path) {
                    // success
                }
                fileField.stringValue = path
            }

        }
    }


    @IBAction func limitCleanLogs(_ sender: Any) {
        if let button = sender as? NSPopUpButton {
            Logger.setLimitLogSize(UInt64(button.selectedTag()))
        }
        Logger.fatal(String(Logger.getSizeLimit()))
    }
    

    /**/
    func isSandboxingEnabled() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}
