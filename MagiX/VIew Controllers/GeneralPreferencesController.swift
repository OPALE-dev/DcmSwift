//
//  GeneralPreferencesController.swift
//  MagiX
//
//  Created by paul on 16/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift

class GeneralPreferencesController: NSViewController {

    /* Outlets */
    @IBOutlet weak var logLevel: NSPopUpButton!
    @IBOutlet weak var checkfileDestination: NSButton!
    @IBOutlet weak var buttonChooseFile: NSButton!
    @IBOutlet weak var checkConsoleDestination: NSButton!
    @IBOutlet weak var cleanLogPeriods: NSPopUpButton!



    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
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
        Logger.debug("file log rule changed")
    }

    @IBAction func logsInConsoleChanged(_ sender: Any) {
        if let checkButton = sender as? NSButton {
            if checkButton.state == NSControl.StateValue.init(0) {
                Logger.removeDestination(Logger.Output.Stdout)
            } else {
                Logger.addDestination(Logger.Output.Stdout)
            }
        }
        Logger.debug("console log rule changed")
    }

}
