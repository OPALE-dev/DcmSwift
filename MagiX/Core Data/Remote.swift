//
//  Remote+CoreDataClass.swift
//  MagiX
//
//  Created by Rafael Warnault on 30/04/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//
//

import Foundation
import CoreData
import DcmSwift

public class Remote: Item {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Remote> {
        return NSFetchRequest<Remote>(entityName: "Remote")
    }
    
    @NSManaged public var title: String?
    @NSManaged public var hostname: String?
    @NSManaged public var port: Int32
    @NSManaged public var status: Int32
    
    public var dicomEntity:DicomEntity? {
        return DicomEntity(title: self.title!, hostname: self.hostname!, port: Int(self.port))
    }
}
