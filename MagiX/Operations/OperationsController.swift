//
//  OperationsController.swift
//  MagiX
//
//  Created by Rafael Warnault on 08/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa



extension Notification.Name {
    static let loadOperationStarted     = Notification.Name(rawValue: "loadOperationStarted")
    static let loadOperationFinished    = Notification.Name(rawValue: "loadOperationFinished")
    static let loadOperationCancelled   = Notification.Name(rawValue: "loadOperationCancelled")
    static let loadOperationUpdated     = Notification.Name(rawValue: "loadOperationUpdated")
}





class OperationsController: NSObject {
    // MARK: - Init
    public static let shared = OperationsController()
    
    public var operationQueue:OperationQueue = OperationQueue()
    
    private override init() {
        super.init()
        
        self.operationQueue.maxConcurrentOperationCount = 5
    }
    
    
    // MARK: - Manage operations
    
    public func addOperation(_ operation: Operation, observe: Bool = true) {
        if observe {
            self.observeOperation(op: operation)
        }
        
        self.operationQueue.addOperation(operation)
    }
    
    
    public func operation(atIndex index:Int) -> Operation? {
        if index <= self.operationQueue.operations.count-1 {
            return self.operationQueue.operations[index]
        }
        return nil
    }
    
    
    
    
    // MARK: - Observer
    
    func observeOperation(op: Operation) {
        op.addObserver(self, forKeyPath: "executing", options: .new, context: nil)
        op.addObserver(self, forKeyPath: "cancelled", options: .new, context: nil)
        op.addObserver(self, forKeyPath: "finished", options: .new, context: nil)
        op.addObserver(self, forKeyPath: "concurrent", options: .new, context: nil)
        op.addObserver(self, forKeyPath: "asynchronous", options: .new, context: nil)
        op.addObserver(self, forKeyPath: "ready", options: .new, context: nil)
        op.addObserver(self, forKeyPath: "name", options: .new, context: nil)
    }
    
    func stopObserveOperation(_ operation: Operation?) {
        if let op = operation {
            op.removeObserver(self, forKeyPath: "executing")
            op.removeObserver(self, forKeyPath: "cancelled")
            op.removeObserver(self, forKeyPath: "finished")
            op.removeObserver(self, forKeyPath: "concurrent")
            op.removeObserver(self, forKeyPath: "asynchronous")
            op.removeObserver(self, forKeyPath: "ready")
            op.removeObserver(self, forKeyPath: "name")
        }
    }
    
    func observeQueue(queue: OperationQueue) {
        queue.addObserver(self, forKeyPath: "operations", options: .new, context: nil)
        queue.addObserver(self, forKeyPath: "operationCount", options: .new, context: nil)
        queue.addObserver(self, forKeyPath: "maxConcurrentOperationCount", options: .new, context: nil)
        queue.addObserver(self, forKeyPath: "suspended", options: .new, context: nil)
        queue.addObserver(self, forKeyPath: "name", options: .new, context: nil)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        let key = keyPath!
        switch key {
        case "executing":
            DispatchQueue.main.async { NotificationCenter.default.post(name: .loadOperationStarted, object: object) }
        case "finished":
            DispatchQueue.main.async { NotificationCenter.default.post(name: .loadOperationFinished, object: object) }
        case "cancelled":
            DispatchQueue.main.async { NotificationCenter.default.post(name: .loadOperationCancelled, object: object) }
        default:
            return
        }
    }
}
