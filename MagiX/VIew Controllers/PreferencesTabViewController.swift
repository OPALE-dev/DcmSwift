//
//  PreferencesTabViewController.swift
//  MagiX
//
//  Created by paul on 15/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa

class PreferencesTabViewController: NSTabViewController {
    lazy var originalSizes = [String : NSSize]()


    override func viewWillAppear() {
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.

        self.preferredContentSize = NSMakeSize(self.view.frame.size.width, self.view.frame.size.height)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        self.parent?.view.window?.title = self.title!
    }


    /*

    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, willSelect: tabViewItem)

        _ = tabView.selectedTabViewItem
        let originalSize = self.originalSizes[tabViewItem!.label]
        if (originalSize == nil) {
            self.originalSizes[tabViewItem!.label] = (tabViewItem!.view?.frame.size)!
        }
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)

        let window = self.view.window
        if (window != nil) {
            window?.title = tabViewItem!.label
            let size = (self.originalSizes[tabViewItem!.label])!
            let contentFrame = (window?.frameRect(forContentRect: NSMakeRect(0.0, 0.0, size.width, size.height)))!
            var frame = (window?.frame)!
            frame.origin.y = frame.origin.y + (frame.size.height - contentFrame.size.height)
            frame.size.height = contentFrame.size.height;
            frame.size.width = contentFrame.size.width;
            window?.setFrame(frame, display: false, animate: true)
        }

        //        tabViewItem!.view?.hidden = false
    }*/

    
}


/*
extension NSTabViewController: NSTableViewDataSource {
    func tableView(_ tableView: NSTableView,
                   numberOfRowsInSection section: Int) -> Int {
        return remotes.count
    }

    func tableView(_ tableView: NSTableView,
                   cellForRowAt indexPath: IndexPath)
        -> NSTableCellView {

            let person = remotes[indexPath.row]
            let cell =
                tableView.dequeueReusableCell(withIdentifier: "Cell",
                                              for: indexPath)
            cell.textLabel?.text =
                person.value(forKeyPath: "name") as? String
            return cell
    }
}*/

/*
extension NSViewController: NSTableViewDelegate {

    fileprivate enum CellIdentifiers {
        static let NameCell = "NameCellID"
        static let DateCell = "DateCellID"
        static let SizeCell = "SizeCellID"
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {

        var image: NSImage?
        var text: String = ""
        var cellIdentifier: String = ""

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .long

        // 1
        guard let item = directoryItems?[row] else {
            return nil
        }

        // 2
        if tableColumn == tableView.tableColumns[0] {
            image = item.icon
            text = item.name
            cellIdentifier = CellIdentifiers.NameCell
        } else if tableColumn == tableView.tableColumns[1] {
            text = dateFormatter.string(from: item.date)
            cellIdentifier = CellIdentifiers.DateCell
        } else if tableColumn == tableView.tableColumns[2] {
            text = item.isFolder ? "--" : sizeFormatter.string(fromByteCount: item.size)
            cellIdentifier = CellIdentifiers.SizeCell
        }

        // 3
        if let cell = tableView.make(withIdentifier: cellIdentifier, owner: nil) as? NSTableCellView {
            cell.textField?.stringValue = text
            cell.imageView?.image = image ?? nil
            return cell
        }
        return nil
    }

}
*/
