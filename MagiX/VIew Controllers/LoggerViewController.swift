//
//  LoggerViewController.swift
//  MagiX
//
//  Created by paul on 23/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift

class LoggerViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource, LoggerProtocol {

    public var logs: [LogInput] = []

    @IBOutlet weak var consoleTable: NSTableView!



    override func viewDidLoad() {
        super.viewDidLoad()
        Logger.shared.loggerProtocol = self

        self.consoleTable.delegate = self
        self.consoleTable.dataSource = self
    }





    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.logs.count
    }


    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: NSTableCellView?
        view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView




        if tableColumn?.title == "Time" {
            let df = DateFormatter()
            df.dateFormat = "yyyy/MM/dd HH:mm:ss"
            view?.textField?.stringValue = df.string(from: logs[row].time)
        } else if tableColumn?.title == "Level" {
            view?.textField?.stringValue = logs[row].level.description
        } else if tableColumn?.title == "Message" {
            view?.textField?.stringValue = logs[row].message
        } else if tableColumn?.title == "Tag" {
            view?.textField?.stringValue = logs[row].tag
        }



        return view
    }


    func setLogInformation(_ withInput: LogInput) {
        logs.append(withInput)
        consoleTable.reloadData()
    }

    
}
