//
//  DataController.swift
//  MagiX
//
//  Created by Rafael Warnault on 22/04/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
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



class DataController {
    public static let shared = DataController()
    
    public var context: NSManagedObjectContext {
        return (NSApp.delegate as! AppDelegate).persistentContainer.viewContext
    }
    
    private init() {
        
    }
    
    
    public func load(fileURLs urls:[URL]) {
        DispatchQueue.global(qos: .background).async {
            for url in urls {
                self.loadFile(atURL: url)
            }
        }
    }
    
    
    public func fetchPatients() -> [Patient] {
        return self.findEntities(withName: "Patient", predicate: nil) as? [Patient] ?? []
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
                    let nserror = error as NSError
                    NSApplication.shared.presentError(nserror)
                }
            }
        }
    }
    
    
    private func loadFile(atURL url:URL) {
        var isDir : ObjCBool = false
        
        if FileManager.default.fileExists(atPath: url.path, isDirectory:&isDir) {
            if isDir.boolValue {
                // file exists and is a directory
                // list the content and loadFile(atURL) recursively
                do {
                    let URLs = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: FileManager.DirectoryEnumerationOptions.skipsHiddenFiles)
                    for u in URLs {
                        self.loadFile(atURL: u)
                    }
                } catch {
                    
                }
            } else {
                // file exists and is not a directory
                // check if it's a DICOM file
                if let df = DicomFile(forPath: url.path) {
                    self.load(dicomFile:df)
                }
            }
        } else {
            // file does not exist
        }
    }
    
    
    private func load(dicomFile:DicomFile) {
        if let patient = self.findOrCreatePatient(forDicomFile: dicomFile) {
            if let study = self.findOrCreateStudy(forDicomFile: dicomFile, forPatient:patient) {
                let serie = self.findOrCreateSeries(forDicomFile: dicomFile, forStudy:study)
                let _ = self.findOrCreateInstance(forDicomFile: dicomFile, forSerie:serie)
                
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .didLoadData, object: nil)
                }
            }else {
                print("ERROR: Study rejected, no Study Instance UID found")
            }
        }
    }
    
    
    
    
    private func findOrCreateInstance(forDicomFile dicomFile:DicomFile, forSerie serie:Serie) -> Instance {
        var instance:Instance!
        
        // try to find a patient with ID
        if let sopInstanceUID = dicomFile.dataset.string(forTag: "SOPInstanceUID") {
            if let i = self.findInstance(withUID: sopInstanceUID) {
                instance = i
            } else {
                // we do not find any patient with this ID
                // so we create it
                instance = Instance(context: self.context)
                instance.serie = serie
                instance.sopInstanceUID = sopInstanceUID
                instance.filePath = dicomFile.filepath
                
                if let patientOrientation = dicomFile.dataset.string(forTag: "PatientOrientation") {
                    instance.patientOrientation = patientOrientation
                }
                
                if let instanceNumber = dicomFile.dataset.integer32(forTag: "InstanceNumber") {
                    instance.instanceNumber = instanceNumber
                }
                
                if let contentDate = dicomFile.dataset.string(forTag: "ContentDate") {
                    if let contentTime = dicomFile.dataset.string(forTag: "ContentTime") {
                        instance.contentDate = Date(dicomDate: contentDate, dicomTime: contentTime)
                    }
                }
                
                serie.addToInstances(instance)
                
                self.save()
            }
        }
        
        return instance
    }
    
    
    
    
    private func findOrCreateSeries(forDicomFile dicomFile:DicomFile, forStudy study:Study) -> Serie {
        var serie:Serie!
        
        // try to find a patient with ID
        if let seriesInstanceUID = dicomFile.dataset.string(forTag: "SeriesInstanceUID") {
            if let s = self.findSerie(withUID: seriesInstanceUID) {
                serie = s
            } else {
                // we do not find any patient with this ID
                // so we create it
                serie = Serie(context: self.context)
                serie.study = study
                serie.seriesInstanceUID = seriesInstanceUID
                
                if let modality = dicomFile.dataset.string(forTag: "Modality") {
                    serie.modality = modality
                }
                
                if let seriesNumber = dicomFile.dataset.integer32(forTag: "SeriesNumber") {
                    serie.seriesNumber = seriesNumber
                }
                
                if let seriesDate = dicomFile.dataset.string(forTag: "SeriesDate") {
                    if let seriesTime = dicomFile.dataset.string(forTag: "SeriesTime") {
                        serie.seriesDate = Date(dicomDate: seriesDate, dicomTime: seriesTime)
                    }
                }
                
                study.addToSeries(serie)
                
                self.save()
            }
        }
        
        return serie
    }
    
    
    private func findOrCreateStudy(forDicomFile dicomFile:DicomFile, forPatient patient:Patient) -> Study? {
        var study:Study
        
        // try to find a patient with ID
        if let studyInstanceUID = dicomFile.dataset.string(forTag: "StudyInstanceUID") {
            if let s = self.findStudy(withUID: studyInstanceUID) {
                study = s
            } else {
                // we do not find any patient with this ID
                // so we create it
                study = Study(context: self.context)
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
                
                patient.addToStudies(study)
                
                self.save()
            }
        } else {
            return nil
        }
        
        return study
    }
    
    private func findOrCreatePatient(forDicomFile dicomFile:DicomFile) -> Patient? {
        var patient:Patient?
        
        var patientID:String? = dicomFile.dataset.string(forTag: "PatientID")
        
        if patientID == nil {
            patientID = "UNKNOW PATIENT"
        }
        
        // try to find a patient with ID
        print("patientID: \(patientID!)")
        
        if let p = self.findPatient(withID:patientID!) {
            print("findPatient: \(p)")
            patient = p
        } else {
            // we do not find any patient with this ID
            // so we create it
            patient = Patient(context: self.context)
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
            
            self.save()
        }
        
        return patient
    }
    
    
    private func findPatient(withID patientID:String) -> Patient? {
        let predicate = NSPredicate(format: "patientID = %@", patientID)
        return findEntity(withName: "Patient", predicate: predicate) as? Patient
    }
    
    
    private func findStudy(withUID studyInstanceUID:String) -> Study? {
        let predicate = NSPredicate(format: "studyInstanceUID = %@", studyInstanceUID)
        return findEntity(withName: "Study", predicate: predicate) as? Study
    }
    
    private func findSerie(withUID seriesInstanceUID:String) -> Serie? {
        let predicate = NSPredicate(format: "seriesInstanceUID = %@", seriesInstanceUID)
        return findEntity(withName: "Serie", predicate: predicate) as? Serie
    }
    
    private func findInstance(withUID sopInstanceUID:String) -> Instance? {
        let predicate = NSPredicate(format: "sopInstanceUID = %@", sopInstanceUID)
        return findEntity(withName: "Instance", predicate: predicate) as? Instance
    }
    
    
    private func findEntity(withName name:String, predicate:NSPredicate) -> Any? {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: name)
        
        request.predicate = predicate
        request.returnsObjectsAsFaults = false
        request.fetchLimit = 1
        
        do {
            let result = try context.fetch(request)
            return result.first
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
            let result = try context.fetch(request)
            
            return result
        } catch {
            print("Failed")
        }
        
        return []
    }
}
