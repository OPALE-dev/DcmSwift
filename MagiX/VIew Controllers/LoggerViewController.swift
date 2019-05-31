//
//  LoggerViewController.swift
//  MagiX
//
//  Created by paul on 23/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift

/**
 Displays Logs like the Console
 The logs are displayed in a table view, according to the following format:
 Level of importance, date, tag and message.
 The console can be cleaned, filtered with a textfield, or filtered by level
 with a popup button. To disable the filter, there is a refresh button.
 
 */
class LoggerViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource, NSSearchFieldDelegate, LoggerProtocol {

    /* Attributes */
    public var logs: [LogInput]         = []
    public var filteredLogs: [LogInput] = []
    public var searching: Bool          = false

    /* Outlets */
    @IBOutlet weak var consoleTable: NSTableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        Logger.shared.loggerProtocol = self

        self.consoleTable.delegate = self
        self.consoleTable.dataSource = self
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if searching  {
            return self.filteredLogs.count
        } else {
            return self.logs.count
        }
    }


    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: NSTableCellView?
        view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
        var array: [LogInput] = logs

        array = logs
        if searching {
            array = filteredLogs
        }

        /* setting the font */
        view?.textField?.font = NSFont(name: "Menlo", size: 11)

        if tableColumn?.title == "Time" {
            let df = DateFormatter()
            df.dateFormat = "yyyy/MM/dd HH:mm:ss"
            view?.textField?.stringValue = df.string(from: array[row].time)
        } else if tableColumn?.title == "Level" {
            view?.textField?.stringValue = array[row].level.description
        } else if tableColumn?.title == "Message" {
            view?.textField?.stringValue = array[row].message
        } else if tableColumn?.title == "Tag" {
            view?.textField?.stringValue = array[row].tag
        }

        return view
    }

    @IBAction func refresh(_ sender: Any) {
        consoleTable.reloadData()
    }

    /**
     Cleans the console

    */
    @IBAction func eraseLogs(_ sender: Any) {
        logs = []
        consoleTable.reloadData()
    }

    /**
     Filter the logs with input from a textfield. If the input is blank,
     the search is disabled.

     */
    @IBAction func searchLogs(_ sender: Any) {
        guard let sf = sender as? NSTextField else {
            return
        }

        if sf.stringValue.isEmpty {
            searching = false
        } else {
            setFilteredArray(sf.stringValue)
            searching = true
        }
        
        reloadAndScroll()
    }

    /**
     Used to disable the search and show all unfiltered logs

    */
    @IBAction func resetLogConsole(_ sender: Any) {
        searching = false
        reloadAndScroll()
    }

    /**
     Show logs with the log level selected on a popup button

    */
    @IBAction func changeLogLevel(_ sender: Any) {
        guard let pop = sender as? NSPopUpButton else {
            return
        }

        if let level = Logger.LogLevel.init(rawValue: pop.selectedTag()) {
            filterLogLevel(level)
            searching = true
        }

        reloadAndScroll()
    }

    /**
     Add a log to the log console

    */
    func setLogInformation(_ withInput: LogInput) {
        logs.append(withInput)
        reloadAndScroll()
    }

    /**
     Scroll the table view to the bottom, if the logs are too much for the
     window to handle.

    */
    func scrollToBottom() {
        DispatchQueue.main.async {
            self.consoleTable.scrollRowToVisible(self.getMessages().count - 1)
        }
    }

    /**
     Reload the table view and scroll to bottom.

    */
    func reloadAndScroll() {
        self.consoleTable.reloadData()
        self.scrollToBottom()
    }


    func getMessages() -> [LogInput] {
        if searching {
            return filteredLogs
        }
        return logs
    }

    /**
     Filter the logs at a specific log level
     - parameter at: the log level of the logs to filter

    */
    func filterLogLevel(_ at: Logger.LogLevel) {
        filteredLogs = []
        let logLevel = at.description.uppercased()

        for row in 0..<logs.count {
            if logs[row].level.description.contains(logLevel) {
                filteredLogs.append(logs[row])
            }
        }
    }

    /**
     Search logs
     - parameter withText: the string to search in the logs

    */
    func setFilteredArray(_ withText: String) {
        filteredLogs = []

        for row in 0..<logs.count {
            let df = DateFormatter()
            df.dateFormat = "yyyy/MM/dd HH:mm:ss"
            if df.string(from: logs[row].time).contains(withText) {
                filteredLogs.append(logs[row])
                continue
            } else if logs[row].level.description.contains(withText) {
                filteredLogs.append(logs[row])
                continue
            } else if logs[row].tag.contains(withText) {
                filteredLogs.append(logs[row])
                continue
            } else if logs[row].message.contains(withText) {
                filteredLogs.append(logs[row])
                continue
            }
        }
    }
}
