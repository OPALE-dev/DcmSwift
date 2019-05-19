//
//  ListenerPreferencesViewController.swift
//  MagiX
//
//  Created by Rafael Warnault on 18/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift


class ServiceItem {
    var name:String
    var uid:String?
    var children:[ServiceItem] = []
    var enabled = true
    var count:Int {
        return children.count
    }
    
    init(name:String, uid:String?, children:[ServiceItem]) {
        self.name = name
        self.uid = uid
        self.children = children
    }
}

class ListenerPreferencesViewController: NSViewController, NSOutlineViewDelegate, NSOutlineViewDataSource {
    @IBOutlet weak var servicesOutlineView: NSOutlineView!
    
    private var services:[ServiceItem] = []

    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        // load data
        self.loadDefaultServices()
        
        // reload view
        self.servicesOutlineView.reloadData()
        
        // auto expand items
        for s in self.services {
            let index = self.servicesOutlineView.row(forItem: s)
            self.servicesOutlineView.expandItem(self.servicesOutlineView.item(atRow: index), expandChildren: true)
        }
    }

    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let serviceItem = item as? ServiceItem {
            return serviceItem.count
        }
        
        return services.count
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let serviceItem = item as? ServiceItem {
            return serviceItem.children[index]
        }
        
        return self.services[index]
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let serviceItem = item as? ServiceItem {
            return serviceItem.count > 0
        }
        return services.count > 0
    }
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        var view: NSTableCellView?
        
        if tableColumn?.identifier.rawValue == "Enabled" {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ServiceItemCellView"), owner: self) as? NSTableCellView
            
            if let itemview = view as? ServiceItemCellView {
                if let serviceItem = item as? ServiceItem {
                    itemview.serviceItem = serviceItem
                }
            }
        }
        else if tableColumn?.identifier.rawValue == "Services" {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
            
            if let serviceItem = item as? ServiceItem {
                view?.textField?.stringValue = serviceItem.name
            }
        }
        else if tableColumn?.identifier.rawValue == "UID" {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TextCell"), owner: self) as? NSTableCellView
            
            if let serviceItem = item as? ServiceItem {
                if let uid = serviceItem.uid {
                    view?.textField?.stringValue = uid
                    view?.textField?.font = NSFont.systemFont(ofSize: 11.0)
                    view?.textField?.textColor = NSColor.disabledControlTextColor
                } else {
                    view?.textField?.stringValue = ""
                }
            }
        }
        
        return view
    }
    
    
    
    private func loadDefaultServices() {
        services.append(
            ServiceItem(name: "C-ECHO", uid: nil, children: [
                ServiceItem(name: DicomSpec.shared.nameForUID(withUID: DicomConstants.verificationSOP), uid:DicomConstants.verificationSOP, children: [
                    ServiceItem(name: DicomSpec.shared.nameForUID(withUID: DicomConstants.explicitVRLittleEndian), uid: DicomConstants.explicitVRLittleEndian, children: [ ])
                    ])
                ]))
        
        services.append(
            ServiceItem(name: "C-FIND", uid: nil, children: [
                ServiceItem(name: DicomSpec.shared.nameForUID(withUID: DicomConstants.StudyRootQueryRetrieveInformationModelFIND), uid: DicomConstants.StudyRootQueryRetrieveInformationModelFIND, children: [
                    ServiceItem(name: DicomSpec.shared.nameForUID(withUID: DicomConstants.explicitVRLittleEndian), uid: DicomConstants.explicitVRLittleEndian, children: [ ]),
                    ServiceItem(name: DicomSpec.shared.nameForUID(withUID: DicomConstants.implicitVRLittleEndian), uid: DicomConstants.implicitVRLittleEndian, children: [ ])
                    ])
                ]))
        
        let cstore = ServiceItem(name: "C-STORE", uid: nil, children:[])
        for sop in DicomConstants.storageSOPClasses {
            cstore.children.append(ServiceItem(name: DicomSpec.shared.nameForUID(withUID: sop), uid: sop, children:[
                ServiceItem(name: DicomSpec.shared.nameForUID(withUID: DicomConstants.explicitVRLittleEndian), uid: DicomConstants.explicitVRLittleEndian, children: [ ]),
                ServiceItem(name: DicomSpec.shared.nameForUID(withUID: DicomConstants.implicitVRLittleEndian), uid: DicomConstants.implicitVRLittleEndian, children: [ ])
                ]))
        }
        services.append(cstore)
    }
}
