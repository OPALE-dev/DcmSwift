//
//  DataController.swift
//  MagiX
//
//  Created by Rafael Warnault on 22/04/2019.
//  Copyright © 2019 OPALE. All rights reserved.
//

import Foundation
import CoreData
import DcmSwift



extension Notification.Name {
    static let didLoadData = Notification.Name(rawValue: "didLoadData")
}




extension FileManager {
    func urls(for directory: FileManager.SearchPathDirectory, skipsHiddenFiles: Bool = true ) -> [URL]? {
        let documentsURL = urls(for: directory, in: .userDomainMask)[0]
        let fileURLs = try? contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: skipsHiddenFiles ? .skipsHiddenFiles : [] )
        return fileURLs
    }
}



class DataController : NSObject {
    public static let shared = DataController()

    public var context: NSManagedObjectContext {
        return (NSApp.delegate as! AppDelegate).persistentContainer.viewContext
    }
    
    public var mainDirectory:Directory!
    
    private override init() {
        super.init()
        
        if let mainDir = self.findEntity(withName: "Directory", predicate: NSPredicate(format: "main = YES")) as? Directory {
            self.mainDirectory = mainDir
            
        } else {
            self.mainDirectory = Directory(context: self.context)
            self.mainDirectory.main = true
            self.mainDirectory.name = "Local Storage"
            
            self.save()
        }
        
    }
    

    
    
    
    // MARK: - Public
    
    
    public func removeStudy(_ study:Study) {
        self.context.delete(study)
        self.save()
        
        NotificationCenter.default.post(name: .didLoadData, object: nil)
    }
    
    
    public func removeDirectory(_ dir:Directory) {
        self.context.delete(dir)
        self.save()
    }
    
    public func removeRemote(_ remote:Remote) {
        self.context.delete(remote)
        self.save()
    }
    
    
    public func fetchDirectories() -> [Directory] {
        return self.findEntities(withName: "Directory", predicate: nil) as? [Directory] ?? []
    }
    
    public func fetchRemotes() -> [Remote] {
        return self.findEntities(withName: "Remote", predicate: nil) as? [Remote] ?? []
    }

    public func fetchStorages() -> [Storage] {
        return self.findEntities(withName: "Storage", predicate: nil) as? [Storage] ?? []
    }
    
    public func fetchPatients() -> [Patient] {
        return self.findEntities(withName: "Patient", predicate: nil) as? [Patient] ?? []
    }
    
    public func fetchStudies() -> [Study] {
        return self.findEntities(withName: "Study", predicate: nil) as? [Study] ?? []
    }
    
    
    public func save() {
        DispatchQueue.main.async {
            // Performs the save action for the application, which is to send the save: message to the application's managed object context. Any encountered errors are presented to the user.
            let context = self.context
            
            if !context.commitEditing() {
                NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing before saving")
            }
            if context.hasChanges {
                do {
                    try context.save()
                } catch {
                    // Customize this code block to include application-specific recovery steps.
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
    
    
    public func loadFile(atURL url:URL, copy:Bool, inStorage storage:Storage, operation: LoadOperation) {
        var isDir : ObjCBool = false
        
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
                        self.loadFile(atURL: u, copy: copy, inStorage: storage, operation: operation)
                    }
                } catch {
                    
                }
            } else {
                // file exists and is not a directory
                // check if it's a DICOM file
                if let df = DicomFile(forPath: url.path) {
                    self.load(dicomFile:df, copy: copy, inStorage: storage, operation: operation)
                }
            }
        } else {
            // file does not exist
        }
    }
    
    
    
    // MARK: - Private
    
    private func load(dicomFile:DicomFile, copy:Bool, inStorage storage:Storage, operation: LoadOperation) {
        if let patient = self.findOrCreatePatient(forDicomFile: dicomFile, operation: operation) {
            patient.storage = storage
            patient.copied = copy
            
            if let study = self.findOrCreateStudy(forDicomFile: dicomFile, forPatient:patient, operation: operation) {
                study.storage = storage
                study.copied = copy
                
                if let serie = self.findOrCreateSeries(forDicomFile: dicomFile, forStudy:study, operation: operation) {
                    serie.storage = storage
                    serie.copied = copy
                    
                    if let instance = self.findOrCreateInstance(forDicomFile: dicomFile, forSerie:serie, operation: operation) {
                        instance.storage = storage
                        instance.copied = copy
                        
                        if copy {
                            StorageController.shared.copyDicomFile(dicomFile,
                                                                   intoStorage: storage,
                                                                   withPatient: patient,
                                                                   withStudy: study,
                                                                   withSerie: serie,
                                                                   withInstance: instance)
                        }
                    }
                
                    serie.numberOfInstances += 1
                    study.numberOfInstances += 1
                    
                    operation.save()
                    
                } else {
                    print("ERROR: Series rejected, no Series Instance UID found")
                }
            } else {
                print("ERROR: Study rejected, no Study Instance UID found")
            }
        }
    }
    
    
    
    
    private func findOrCreateInstance(forDicomFile dicomFile:DicomFile, forSerie serie:Serie, operation: LoadOperation) -> Instance? {
        var instance:Instance!
        
        // try to find a patient with ID
        if let sopInstanceUID = dicomFile.dataset.string(forTag: "SOPInstanceUID") {
            if let i = self.findInstance(withUID: sopInstanceUID, moc: operation.managedObjectContext) {
                instance = i
            } else {
                // we do not find any patient with this ID
                // so we create it
                instance = Instance(context: operation.managedObjectContext)
                instance.serie = serie
                instance.sopInstanceUID = sopInstanceUID
                instance.filePath = dicomFile.filepath
                
                if let patientOrientation = dicomFile.dataset.string(forTag: "PatientOrientation") {
                    instance.patientOrientation = patientOrientation
                }
                
                if let instanceNumber = dicomFile.dataset.integer32(forTag: "InstanceNumber") {
                    instance.instanceNumber = instanceNumber
                }
                
                if let transferSyntax = dicomFile.dataset.string(forTag: "TransferSyntaxUID") {
                    instance.transferSyntaxUID = transferSyntax
                }
                
                if let contentDate = dicomFile.dataset.string(forTag: "ContentDate") {
                    if let contentTime = dicomFile.dataset.string(forTag: "ContentTime") {
                        instance.contentDate = Date(dicomDate: contentDate, dicomTime: contentTime)
                    }
                }
                
                serie.addToInstances(instance)
            }
        } else {
            return nil
        }
        
        
        return instance
    }
    
    
    
    
    private func findOrCreateSeries(forDicomFile dicomFile:DicomFile, forStudy study:Study, operation: LoadOperation) -> Serie? {
        var serie:Serie!
        
        // try to find a patient with ID
        if let seriesInstanceUID = dicomFile.dataset.string(forTag: "SeriesInstanceUID") {
            if let s = self.findSerie(withUID: seriesInstanceUID, moc: operation.managedObjectContext) {
                serie = s
            } else {
                // we do not find any patient with this ID
                // so we create it
                serie = Serie(context: operation.managedObjectContext)
                serie.study = study
                serie.seriesInstanceUID = seriesInstanceUID
                
                if let modality = dicomFile.dataset.string(forTag: "Modality") {
                    serie.modality = modality
                }
                
                if let seriesNumber = dicomFile.dataset.integer32(forTag: "SeriesNumber") {
                    serie.seriesNumber = seriesNumber
                }
                
                if let transferSyntax = dicomFile.dataset.string(forTag: "TransferSyntaxUID") {
                    serie.transferSyntaxUID = transferSyntax
                }
                
                
                
                if let seriesDate = dicomFile.dataset.string(forTag: "SeriesDate") {
                    if let seriesTime = dicomFile.dataset.string(forTag: "SeriesTime") {
                        serie.seriesDate = Date(dicomDate: seriesDate, dicomTime: seriesTime)
                    }
                }
                
                // image proxy
                if serie.imageProxy == nil {
                    if let dicomImage = dicomFile.dicomImage {
                        if let image = dicomImage.image() {
                            serie.imageProxy = image.tiffRepresentation
                        }
                    }
                }
                
                study.addToSeries(serie)
            }
        } else {
            return nil
        }
        
        
        return serie
    }
    
    
    private func findOrCreateStudy(forDicomFile dicomFile:DicomFile, forPatient patient:Patient, operation: LoadOperation) -> Study? {
        var study:Study
        
        // try to find a patient with ID
        if let studyInstanceUID = dicomFile.dataset.string(forTag: "StudyInstanceUID") {
            if let s = self.findStudy(withUID: studyInstanceUID, moc: operation.managedObjectContext) {
                study = s
            } else {
                // we do not find any patient with this ID
                // so we create it
                study = Study(context: operation.managedObjectContext)
                study.patient = patient
                study.studyInstanceUID = studyInstanceUID
                
                if let studyID = dicomFile.dataset.string(forTag: "StudyID") {
                    study.studyID = studyID
                }
                
                if let studyDescription = dicomFile.dataset.string(forTag: "StudyDescription") {
                    study.studyDescription = studyDescription
                }
                
                if let accessionNumber = dicomFile.dataset.string(forTag: "AccessionNumber") {
                    study.accessionNumber = accessionNumber
                }
                
                if let studyDate = dicomFile.dataset.string(forTag: "StudyDate") {
                    if let studyTime = dicomFile.dataset.string(forTag: "StudyTime") {
                        study.studyDate = Date(dicomDate: studyDate, dicomTime: studyTime)
                    }
                }
                
                // image proxy
                if study.imageProxy == nil {
                    if let dicomImage = dicomFile.dicomImage {
                        if let image = dicomImage.image() {

                            study.imageProxy = image.tiffRepresentation
                        }
                    }
                }
                
                
                patient.addToStudies(study)
            }
        } else {
            return nil
        }
        
        return study
    }
    
    private func findOrCreatePatient(forDicomFile dicomFile:DicomFile, operation: LoadOperation) -> Patient? {
        var patient:Patient?
        
        var patientID:String? = dicomFile.dataset.string(forTag: "PatientID")
        
        if patientID == nil {
            patientID = "UNKNOW ID"
        }
        
        // try to find a patient with ID
        if let p = self.findPatient(withID:patientID!, moc: operation.managedObjectContext) {
            patient = p
            
        } else {
            // we do not find any patient with this ID
            // so we create it
            patient = Patient(context: operation.managedObjectContext)
            patient?.patientID = patientID!
            
            if let patientName = dicomFile.dataset.string(forTag: "PatientName") {
                patient?.patientName = patientName
            }
            
            if let patientSex = dicomFile.dataset.string(forTag: "PatientSex") {
                patient?.patientSex = patientSex
            }
            
            if let patientBirthDate = dicomFile.dataset.string(forTag: "PatientBirthDate") {
                patient?.patientBirthdate = Date(dicomDate: patientBirthDate)
            }
        }
        
        return patient
    }
    
    
    private func findPatient(withID patientID:String, moc: NSManagedObjectContext) -> Patient? {
        let predicate = NSPredicate(format: "patientID = %@", patientID)
        
        if let objectID = findEntityID(withName: "Patient", predicate: predicate) as? NSManagedObjectID {
            return moc.object(with: objectID) as? Patient
        }
        
        return nil
    }
    
    
    private func findStudy(withUID studyInstanceUID:String, moc: NSManagedObjectContext) -> Study? {
        let predicate = NSPredicate(format: "studyInstanceUID = %@", studyInstanceUID)
        
        if let objectID = findEntityID(withName: "Study", predicate: predicate) as? NSManagedObjectID {
            return moc.object(with: objectID) as? Study
        }
        
        return nil
    }
    
    private func findSerie(withUID seriesInstanceUID:String, moc: NSManagedObjectContext) -> Serie? {
        let predicate = NSPredicate(format: "seriesInstanceUID = %@", seriesInstanceUID)
        
        if let objectID = findEntityID(withName: "Serie", predicate: predicate) as? NSManagedObjectID {
            return moc.object(with: objectID) as? Serie
        }
        
        return nil
    }
    
    private func findInstance(withUID sopInstanceUID:String, moc: NSManagedObjectContext) -> Instance? {
        let predicate = NSPredicate(format: "sopInstanceUID = %@", sopInstanceUID)
        
        if let objectID = findEntityID(withName: "Instance", predicate: predicate) as? NSManagedObjectID {
            return moc.object(with: objectID) as? Instance
        }
        
        return nil
    }
    
    
    private func findEntity(withName name:String, predicate:NSPredicate) -> Any? {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: name)
        
        request.predicate = predicate
        request.returnsObjectsAsFaults = false
        request.fetchLimit = 1
        
        do {
            let result = try self.context.fetch(request)
            if let managedObject = result.first {
                return managedObject
            }
        } catch {
            print("Failed")
        }
        
        return nil
    }
    
    
    private func findEntityID(withName name:String, predicate:NSPredicate) -> Any? {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: name)
        
        request.predicate = predicate
        request.returnsObjectsAsFaults = false
        request.fetchLimit = 1
        
        do {
            let result = try self.context.fetch(request)
            if let managedObject = result.first as? NSManagedObject {
                return managedObject.objectID
            }
        } catch {
            print("Failed")
        }
        
        return nil
    }
    
    private func findEntities(withName name:String, predicate:NSPredicate?) -> [Any?] {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: name)
        
        if let p = predicate {
            request.predicate = p
        }
        
        request.returnsObjectsAsFaults = false
        
        do {
            let result = try self.context.fetch(request)
            
            return result
        } catch {
            print("Failed")
        }
        
        return []
    }
}
