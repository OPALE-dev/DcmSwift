//
//  LoadOperation.swift
//  MagiX
//
//  Created by Rafael Warnault on 28/04/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Cocoa


import Foundation
import CoreData

class LoadOperation: BlockOperation {
    public let managedObjectContext = NSManagedObjectContext(
        concurrencyType: NSManagedObjectContextConcurrencyType.privateQueueConcurrencyType
    )
    
    public var numberOfFiles = 0
    public var currentIndex = 0
    public var percents = 0
    
    
    init(parentContext:NSManagedObjectContext) {
        super.init()
        
        self.managedObjectContext.automaticallyMergesChangesFromParent = true
        self.managedObjectContext.parent = parentContext
        
        NotificationCenter.default.addObserver(self, selector: #selector(contextDidSave(_:)), name: Notification.Name.NSManagedObjectContextDidSave, object: nil)
    }
    
    
    @objc func contextDidSave(_ notification: Notification) {
        if let savedContext = notification.object as? NSManagedObjectContext {
            if savedContext == self.managedObjectContext {
                self.managedObjectContext.mergeChanges(fromContextDidSave: notification)
            }
        }
    }
    
    
    
    public func save() {
        // Performs the save action for the application, which is to send the save: message to the application's managed object context. Any encountered errors are presented to the user.
        let context = self.managedObjectContext
        
        if !context.commitEditing() {
            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing before saving")
        }
        if context.hasChanges {
            do {
                try context.save()
                
            } catch {
                // Customize this code block to include application-specific recovery steps.
                let nserror = error as NSError
                NSApplication.shared.presentError(nserror)
                
                let detailedErrors = ((error as NSError).userInfo)[NSDetailedErrorsKey] as? [Any]
                
                if detailedErrors != nil && (detailedErrors?.count ?? 0) > 0 {
                    for detailedError in detailedErrors as? [Error] ?? [] {
                        print("  DetailedError: \((detailedError as NSError).userInfo)")
                    }
                }
                
            }
        }
    }
}
