//
//  File.swift
//  
//
//  Created by Colombe on 29/06/2021.
//

import Foundation

/**
    Class representing a Dicom Directory and all associated methods.
    DICOMDIR stores the informatique about a DICOM files in a given file directoru (folder). Thus, DICOMDIR plays the role of
    a small DICOM database, or an index of DICOM files, placed in the root folder of the media (like a DVD).
 */
public class DicomDir:DicomFile {
    public var index:[String] = []
    
    // PatientID:PatientName
    public var patients:[String:String] = [:]
    
    // StudyInstanceUID:PatientID
    public var studies:[String:String] = [:]
    
    // SeriesInstanceUID:StudyInstanceUID
    public var series:[String:String] = [:]
    
    // ReferencedSOPInstanceUIDInFile:[SeriesInstanceUID,filepath]
    public var images:[String:[String]] = [:]
    
    
    // MARK: - Methods
    
    /**
        Load a DICOMDIR for a given path
     */
    public override init?(forPath filepath: String) {
        super.init(forPath: filepath)
    }
    
    /**
        Create a void DICOMDIR
     */
    public override init() {
        super.init()
    }
    
    /**
        Return a boolean that indicates if a file is a DICOMDIR. 
    */
    public static func isDicomDir(forPath filepath: String) -> Bool {
        let inputStream = DicomInputStream(filePath: filepath)
        
        do {
            if let dataset = try inputStream.readDataset() {
                //print("offset : \(inputStream.offset)")
                
                if dataset.hasElement(forTagName:"DirectoryRecordSequence") {
                    return true
                } else {
                    return false
                }
            }
        } catch _ {
            return false
        }
        return false
    }
    
    
    override func read() -> Bool {
        let rez = super.read()
        
        if rez == false {
            return false
        }
        
        load()
        
        return rez
    }
    
    /**
        Return an array of String wich represents all the DICOM files corresponding to a given patient
     */
    public func index(forPatientID givenID:String) -> [String] {
        var resultat : [String] = []
        
        for(patientsID,_) in patients {
            if(patientsID == givenID) {
                for(studyUID, patientsID_2) in studies {
                    if(patientsID == patientsID_2) {
                        for(seriesUID, studyUID_2) in series {
                            if(studyUID == studyUID_2) {
                                for(_,array) in images {
                                    if(array[0] == seriesUID) {
                                        let path = array[1]
                                        if(path != DicomDir.amputation(forPath: filepath)) {
                                            resultat.append(path)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return resultat
    }
    
    /**
        Return an array of String wich represents all the DICOM files corresponding to a given study
     */
    public func index(forStudyInstanceUID givenStudyUID:String) -> [String] {
        var resultat : [String] = []
        
        for(_,_) in patients {
            for(studyUID, _) in studies {
                if(studyUID == givenStudyUID) {
                    for(seriesUID, studyUID_2) in series {
                        if(studyUID == studyUID_2) {
                            for(_,array) in images {
                                if(array[0] == seriesUID) {
                                    let path = array[1]
                                    if(path != DicomDir.amputation(forPath: filepath)) {
                                        resultat.append(path)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return resultat
    }
    
    /**
        Return an array of String wich represents all the DICOM files corresponding to a given serie
     */
    public func index(forSeriesInstanceUID givenSeriesUID:String) -> [String] {
        var resultat : [String] = []
        
        for(_,_) in patients {
            for(_,_) in studies {
                for(seriesUID, _) in series {
                    if(seriesUID == givenSeriesUID) {
                        for(_,array) in images {
                            if(array[0] == seriesUID) {
                                let path = array[1]
                                if(path != DicomDir.amputation(forPath: filepath)) {
                                    if !resultat.contains(path) {
                                        resultat.append(path)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return resultat
    }
    
    /**
        Load all the properties of a DicomDir instance (patients, index etc)
     */
    private func load() {
        if let dataset = self.dataset {
            if let directoryRecordSequence = dataset.element(forTagName: "DirectoryRecordSequence") as? DataSequence {
                var patientName = ""
                var patientID = ""
                var studyUID = ""
                var serieUID = ""
                var SOPUID = ""
                var path = ""
                
                for item in directoryRecordSequence.items {
                    
                    for element in item.elements {
                    // Load the index property
                        if(element.name == "ReferencedFileID") {
                            path = DicomDir.amputation(forPath: filepath)
                            for dataValue in element.values {
                                path += "/" + dataValue.value
                            }
                            if(path != DicomDir.amputation(forPath: filepath)) {
                                index.append(path)
                            }
                        } 
                         
                    // Load the patients property
                        
                        if element.name == "PatientName" {
                            patientName = "\(element.value)"
                        }
                            
                        if element.name == "PatientID" {
                            patientID = "\(element.value)"
                        }
                        
                    // Load the studies property
                        if element.name == "StudyInstanceUID" {
                            studyUID = "\(element.value)"
                            if studyUID.count > 0 {
                                studies[studyUID] = patientID
                            }
                        }
                        
                    // Load the series property
                        if element.name == "SeriesInstanceUID" {
                            serieUID = "\(element.value)"
                            if serieUID.count > 0 {
                                series[serieUID] = studyUID
                            }
                        }
                    
                    // Load the images property
                        if element.name == "ReferencedSOPInstanceUIDInFile" {
                            SOPUID = "\(element.value)"
                            if SOPUID.count > 0 && serieUID.count > 0 {
                                if(path != DicomDir.amputation(forPath: filepath)) {
                                    images[SOPUID] = [serieUID,path]
                                }
                            }
                        }
                    }
                    
                    if patientName.count > 0 && patientID.count > 0 {
                        patients[patientID] = patientName
                    }
                }
            }
        }
    }
    
    public static func studies(forPath filepath: String) {
        
    }
    
//    private func truncate(forPath filepath: String) -> String  {
//        return NSString(string: filepath).deletingLastPathComponent
//    }
    
    /**
        Return a String without the last part (after the last /)
     */
    public static func amputation(forPath filepath: String) -> String {
        var stringAmputee = ""
        let array = filepath.components(separatedBy: "/")
        let size = array.count
        for i in 0 ..< size-1 {
            if i == size-2 {
                stringAmputee += array[i]
            } else {
                stringAmputee += array[i] + "/"
            }
        }
        return stringAmputee
    }
    
    /**
        Write a new DICOMDIR using a folder
     */
    public func writeDicomDir(atPath folderPath:String) -> Bool {
        self.write(atPath: folderPath) // On appelle la méthode write de DicomFile
        
        
       // var sequence = DataSequence(withTag: "DirectoryRecordSequence")
     //   print(sequence)
        
        for _ in patients {
            //var patientItem = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"))
            //patientItem.elements.append(newElement: DataElement()//
        }
        
        
        
        return false
    }
    
    /**
        Create a DicomDir instance wich contains the interesting data of the given folder
     */
    public static func parse(atPath folderPath:String) -> DicomDir? {
        
        let dcmDir = DicomDir.init()
        dcmDir.filepath = amputation(forPath:folderPath)
        
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: folderPath)
            
            var pathFolder = folderPath
            if(pathFolder.last != "/") {
                pathFolder += "/"
            }
            
            for file in files {
                // add to DicomDir.index the file path
                let absolutePath = pathFolder+file
                
                dcmDir.index.append(absolutePath)
                
                guard let dcmFile = DicomFile(forPath: absolutePath) else {
                    return nil
                }
            
                // fill patient property
                let patientKey = dcmFile.dataset.string(forTag: "PatientID")
                let patientVal = dcmFile.dataset.string(forTag: "PatientName")
                if let key = patientKey {
                    dcmDir.patients[key] = patientVal
                }
                
                // fill study property
                let studyKey = dcmFile.dataset.string(forTag: "StudyInstanceUID")
                let studyVal = patientKey
                if let key = studyKey {
                    dcmDir.studies[key] = studyVal
                }
                
                // fill serie property
                let serieKey = dcmFile.dataset.string(forTag: "SeriesInstanceUID")
                let serieVal = studyKey
                if let key = serieKey {
                    dcmDir.series[key] = serieVal
                }
                
                // fill images property
                let imageKey = dcmFile.dataset.string(forTag: "SOPInstanceUID")
                if let serieKeyUnwrapped = serieKey {
                    let imageVal = [serieKeyUnwrapped,absolutePath]
                    if let key = imageKey {
                        dcmDir.images[key] = imageVal
                    }
                }
            }
        } catch {
            print(error)
            return nil
        }
        return dcmDir
    }
}
