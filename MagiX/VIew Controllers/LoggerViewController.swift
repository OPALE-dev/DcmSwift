//
//  LoggerViewController.swift
//  MagiX
//
//  Created by paul on 23/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift

class LoggerViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource, NSSearchFieldDelegate, LoggerProtocol {

    public var logs: [LogInput]         = []
    public var filteredLogs: [LogInput] = []
    public var searching: Bool          = false

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
        var array: [LogInput] = []

        if searching {
            array = filteredLogs
        } else {
            array = logs
        }

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

    @IBAction func eraseLogs(_ sender: Any) {
        logs = []
        consoleTable.reloadData()
    }

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



    func setLogInformation(_ withInput: LogInput) {
        logs.append(withInput)
        reloadAndScroll()
    }


    func scrollToBottom() {
        DispatchQueue.main.async {
            self.consoleTable.scrollRowToVisible(self.getMessages().count - 1)
        }
    }

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

    func setFilteredArray(_ withText: String) /*-> [Int]*/ {
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
