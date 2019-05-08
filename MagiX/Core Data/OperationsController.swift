//
//  OperationsController.swift
//  MagiX
//
//  Created by Rafael Warnault on 08/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa

class OperationsController: NSObject {
    public static let shared = OperationsController()
    
    public var operationQueue:OperationQueue = OperationQueue()
    
    private override init() {
        super.init()
        
        self.operationQueue.maxConcurrentOperationCount = 1
    }
}
