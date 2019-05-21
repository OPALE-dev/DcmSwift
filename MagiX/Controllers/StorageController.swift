//
//  StorageController.swift
//  MagiX
//
//  Created by Rafael Warnault on 19/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Cocoa
import DcmSwift

class StorageController: NSObject {
    public static let shared = StorageController()
    
    public var storages:[Storage] = []
    
    
    private override init() {
        super.init()
        
        self.storages = DataController.shared.fetchStorages()
        
        if self.storages.count == 0 {
            let storage = Storage(context: DataController.shared.context)
            storage.path = "\(getDocumentsDirectory().path)/MagixData"
            storage.storageType = 0
            storage.minimumRemainingDiskSpace = 500
            
            self.verifyDataDirectory(forStorage: storage)
            self.storages.append(storage)
            
            DataController.shared.save()
        }
    }
    
    
    public func activeStorage() -> Storage? {
        let request: NSFetchRequest<Storage> = Storage.fetchRequest()
        request.fetchLimit = 1
        
        let predicate = NSPredicate(format: "priority == max(priority)")
        request.predicate = predicate
        
        do {
            return try DataController.shared.context.fetch(request).first
        } catch {
            print("Unresolved error in retrieving max personId value \(error)")
        }
        return nil
    }
    
    
    
    public func load(fileURLs urls:[URL]) {
        if let storage = self.activeStorage() {
            self.load(fileURLs: urls, copy: true, inStorage: storage)
        }
    }
    
    
    
    public func load(fileURLs urls:[URL], copy:Bool, inStorage storage:Storage) {
        let loadOperation = LoadOperation(parentContext: DataController.shared.context)
        var flattenURLs:[URL] = []
        let storageID = storage.objectID
        var percent = 0
        
        loadOperation.numberOfFiles = urls.count
        
        loadOperation.addExecutionBlock {
            for url in urls {
                flattenURLs.append(contentsOf: self.getURLs(atURL: url))
            }
            
            loadOperation.numberOfFiles = flattenURLs.count
            
            var count = 0
            for url in flattenURLs {
                if let operationStorage = loadOperation.managedObjectContext.object(with: storageID) as? Storage {
                    DataController.shared.loadFile(atURL: url, copy: copy, inStorage:operationStorage, operation: loadOperation)
                    
                    count += 1
                    percent = Int((Float(count) / Float(loadOperation.numberOfFiles)) * 100)
                    
                    loadOperation.currentIndex = count
                    loadOperation.percents = percent
                    
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .loadOperationUpdated, object: loadOperation)
                    }
                }
            }
        }
        
        loadOperation.completionBlock = {
            DispatchQueue.main.async {
                // save background and main contexts
                loadOperation.save()
                DataController.shared.save()
                
                OperationsController.shared.stopObserveOperation(loadOperation)
                
                NotificationCenter.default.post(name: .didLoadData, object: nil)
            }
        }
        
        OperationsController.shared.addOperation(loadOperation)
    }
    
    
    
    public func copyDicomFile(_ dicomFile: DicomFile, intoStorage storage:Storage, withPatient patient:Patient, withStudy study:Study, withSerie serie:Serie, withInstance instance:Instance) {
        if let path = instance.filePath {
            do {
                var destinationDirPath = "\(storage.path!)"
                destinationDirPath += "/\(patient.objectID.uriRepresentation().lastPathComponent)"
                destinationDirPath += "/\(study.objectID.uriRepresentation().lastPathComponent)"
                destinationDirPath += "/\(serie.objectID.uriRepresentation().lastPathComponent)"
                
                try FileManager.default.createDirectory(at: URL(fileURLWithPath: destinationDirPath), withIntermediateDirectories: true, attributes: [:])
                
                let destinationFilePath = "\(destinationDirPath)/\(instance.objectID.uriRepresentation().lastPathComponent)"
                
                try FileManager.default.copyItem(atPath: path, toPath: destinationFilePath)
                
                instance.filePath = destinationFilePath
                
            } catch {
                Logger.error("Failed to copy file \(path)")
            }
        }
    }
    
    
    
    private func getURLs(atURL url:URL) -> [URL] {
        var urls:[URL]      = []
        var isDir:ObjCBool  = false
        
        if FileManager.default.fileExists(atPath: url.path, isDirectory:&isDir) {
            if isDir.boolValue {
                // file exists and is a directory
                // list the content and loadFile(atURL) recursively
                do {
                    let URLs = try FileManager.default.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: nil,
                        options: FileManager.DirectoryEnumerationOptions.skipsHiddenFiles)
                    
                    for u in URLs {
                        urls.append(contentsOf: self.getURLs(atURL: u))
                    }
                    return urls
                } catch {
                    
                }
            } else {
                // file exists and is not a directory
                // check if it's a DICOM file
                urls.append(url)
            }
        } else {
            // file does not exist
        }
        
        print(urls)
        
        return urls
    }
    
    
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }
    
    
    private func verifyDataDirectory(forStorage storage:Storage) {
        var isDir:ObjCBool  = false
        
        if let path = storage.path {
            if !FileManager.default.fileExists(atPath: path, isDirectory:&isDir) {
                do {
                    try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true, attributes: [:])
                } catch {
                    Logger.error("Cannot create directory: \(path)")
                }
            }
        }
    }
}
