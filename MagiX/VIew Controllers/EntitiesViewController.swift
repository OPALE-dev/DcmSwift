//
//  EntitiesViewController.swift
//  MagiX
//
//  Created by paul on 16/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa

class EntitiesViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
    @IBOutlet weak var tableView: NSTableView!
    public var remotes:[Remote] = []
    @IBOutlet weak var removeButton: NSButton!


    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        self.remotes = DataController.shared.fetchRemotes()
    }


    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.remotes.count
    }




    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: NSTableCellView?

        if tableColumn?.identifier.rawValue == "name" {
            view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
            if let string = self.remotes[row].name {
                view?.textField?.stringValue = string
            }
        }
        else if tableColumn?.identifier.rawValue == "title" {
            view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
            if let string = self.remotes[row].title {
                view?.textField?.stringValue = string
            }
        }
        else if tableColumn?.identifier.rawValue == "hostname" {
            view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
            if let string = self.remotes[row].hostname {
                view?.textField?.stringValue = string
            }
        }
        else if tableColumn?.identifier.rawValue == "port" {
            view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
            let integer:Int32 = self.remotes[row].port
            view?.textField?.stringValue = String(integer)
        }
        else if tableColumn?.identifier.rawValue == "status" {
            view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
            let integer:Int32 = self.remotes[row].status
            view?.textField?.stringValue = String(integer)

        }
        return view
    }


    @IBAction func removeButtonClicked(_ sender: Any) {
        let index = tableView.selectedRow
        let remote = remotes[index]

        DataController.shared.removeRemote(remote)
        self.remotes = DataController.shared.fetchRemotes()
        
        self.tableView.reloadData()
    }
}
