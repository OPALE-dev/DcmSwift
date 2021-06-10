//
//  ServerController.swift
//  MagiX
//
//  Created by Rafael Warnault on 18/05/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Cocoa
import DcmSwift

class ServerController: NSObject {
    public static let shared = ServerController()
    
    private var server:DicomServer?
    
    private override init() {
        super.init()
    }
    
    public func startServer() {
        let settings = UserDefaults.standard
        guard let portString = settings.string(forKey: "LocalPort") else {
            Logger.error("No network port set, cannot start DICOM services")
            return
        }
        
        guard let localAET = settings.string(forKey: "LocalAET") else {
            Logger.error("No local AET set, cannot start DICOM services")
            return
        }
        
        if let port = Int(portString) {
            self.server = DicomServer(port: port, localAET: localAET)
            
            Thread.detachNewThread {
                self.server?.run()
            }
        }
    }
}
