//
//  EntitiesViewController.swift
//  MagiX
//
//  Created by paul on 16/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Cocoa
import DcmSwift

class RemotesPreferencesViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
    @IBOutlet weak var tableView: NSTableView!
    public var remotes:[Remote] = []
    @IBOutlet weak var removeButton: NSButton!


    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        self.remotes = DataController.shared.fetchRemotes()

        NotificationCenter.default.addObserver(self, selector: #selector(didUpdateRemote(n:)), name: .didUpdateRemote, object: nil)
//        tableView.doubleAction = #selector(SidebarViewController.editRemote(_:))
        tableView.doubleAction = #selector(editOnDoubleClick(r:))
        
    }
    


    @objc func didUpdateRemote(n:Notification) {
        if let r = n.object as? Remote
        {
            if !self.remotes.contains(r) {
                self.remotes.append(r)
            }
            self.tableView.reloadData()
        }
    }

    @objc func editOnDoubleClick(r: Any?) {
        let selectedItem = selectedRow()
        let remote = remotes[selectedItem]
        if let remoteVC:RemoteEditViewController = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "RemoteEditViewController") as? RemoteEditViewController {
            remoteVC.remote = remote
            self.presentAsSheet(remoteVC)
        }

    }


    private func selectedRow() -> Int {
        if self.tableView.clickedRow != -1 {
            return self.tableView.clickedRow
        }

        return self.tableView.selectedRow
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
            view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "StatusCell"), owner: self) as? NSTableCellView
            let status:Int32 = self.remotes[row].status
            
            if status == 0 {
                view?.imageView?.image = NSImage(named: NSImage.Name("NSStatusNone"))
            }
            else if status == 1 {
                view?.imageView?.image = NSImage(named: NSImage.Name("NSStatusAvailable"))
            }
            else if status == 2 {
                view?.imageView?.image = NSImage(named: NSImage.Name("NSStatusUnavailable"))
            }
        }
        return view
    }


    @IBAction func removeButtonClicked(_ sender: Any) {
        let index = selectedRow()
        if index <= 0 {
            return
        }
        let remote = remotes[index]

        DataController.shared.removeRemote(remote)
        self.remotes = DataController.shared.fetchRemotes()

        self.tableView.reloadData()
    }
}
